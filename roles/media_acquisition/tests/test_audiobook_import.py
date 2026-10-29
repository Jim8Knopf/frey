#!/usr/bin/env python3
"""Check safe, repeatable imports without needing a running torrent client."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

from jinja2 import Environment, FileSystemLoader


class ImportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = Path(self.tmp.name) / "data"
        self.data.mkdir()
        source = self.data / "torrents" / "audiobookrequest"
        source.mkdir(parents=True)
        (source / "book").mkdir()
        (source / "book" / "chapter.mp3").write_bytes(b"audio")
        templates = Path(__file__).resolve().parents[1] / "templates"
        environment = Environment(loader=FileSystemLoader(templates))
        environment.filters["to_json"] = json.dumps
        script = environment.get_template(
            "frey-audiobook-import.py.j2"
        ).render(media={"data_dir": str(self.data), "user": {"uid": os.getuid(), "gid": os.getgid()}},
                 frey={"service_address": "127.0.0.1", "local_domain": "frey"})
        path = Path(self.tmp.name) / "importer.py"
        path.write_text(script)
        spec = importlib.util.spec_from_file_location("audiobook_import", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.torrent = {"hash": "a" * 40, "name": "Book", "save_path": "/data/torrents/audiobookrequest"}
        self.files = [{"name": "book/chapter.mp3", "progress": 1, "priority": 1}]

    def test_hardlinks_are_repeatable(self):
        self.module.import_torrent(self.torrent, self.files)
        self.module.import_torrent(self.torrent, self.files)
        source = self.data / "torrents/audiobookrequest/book/chapter.mp3"
        target = self.data / "media/audiobooks/Requests/Book [aaaaaaaa]/book/chapter.mp3"
        self.assertTrue(os.path.samefile(source, target))

    def test_rejects_incomplete_and_unsafe_paths(self):
        for name, progress in (("book/chapter.mp3", 0.5), ("../outside.mp3", 1)):
            with self.assertRaises(ValueError):
                self.module.import_torrent(self.torrent, [{"name": name, "progress": progress}])
        source = self.data / "torrents/audiobookrequest/book/link.mp3"
        source.symlink_to(self.data / "torrents/audiobookrequest/book/chapter.mp3")
        with self.assertRaises(ValueError):
            self.module.import_torrent(self.torrent, [{"name": "book/link.mp3", "progress": 1}])


if __name__ == "__main__":
    unittest.main()
