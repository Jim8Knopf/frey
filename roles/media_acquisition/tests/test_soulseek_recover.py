#!/usr/bin/env python3
"""Protect existing music when recovering interrupted Soulseek downloads."""
import json
import configparser
import io
from pathlib import Path
import tempfile
import unittest

from jinja2 import Environment, FileSystemLoader


class SoulseekRecoveryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        templates = Path(__file__).resolve().parents[1] / "templates"
        env = Environment(loader=FileSystemLoader(templates))
        env.filters["to_json"] = json.dumps
        source = env.get_template("frey-soulseek-recover.py.j2").render(
            media={"data_dir": "/tmp/data", "network": {"name": "test"}},
            media_acquisition={"configure": {"key_file": "/tmp/keys"}},
            frey={"service_address": "127.0.0.1", "local_domain": "frey"},
        )
        cls.module = {"__name__": "test_recovery"}
        exec(compile(source, "frey-soulseek-recover", "exec"), cls.module)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name) / "Album"
        self.folder.mkdir()
        self.items = []
        self.tracks = []
        for i in (1, 2):
            (self.folder / f"{i}.flac").write_bytes(b"track")
            self.items.append({"path": f"/data/slskd/complete/Album/{i}.flac",
                               "artist": {"id": 1}, "album": {"id": 2},
                               "albumReleaseId": 3, "tracks": [{"id": i}],
                               "quality": {}, "rejections": []})
            self.tracks.append({"id": i, "hasFile": False, "trackFileId": 0})

    def eligible(self):
        return self.module["eligible"](self.folder, self.items, self.tracks, {2})

    def test_complete_album_is_eligible(self):
        self.assertEqual(len(self.eligible()), 2)

    def test_incomplete_rejected_existing_and_duplicate_tracks_are_skipped(self):
        self.items[0]["rejections"] = [{"reason": "Has missing tracks"}]
        self.assertIsNone(self.eligible())
        self.items[0]["rejections"] = []
        self.tracks[0]["hasFile"] = True
        self.assertIsNone(self.eligible())
        self.tracks[0]["hasFile"] = False
        self.items[0]["tracks"] = [{"id": 2}]
        self.assertIsNone(self.eligible())

    def test_active_transfer_folder_is_identified(self):
        peers = [{"directories": [{"directory": "Music\\Artist\\Album", "files": [{"state": "Queued, Remotely"}]}]}]
        self.assertEqual(self.module["active_folders"](peers), {"album"})

    def test_search_prefers_mp3_and_limits_album_concurrency(self):
        templates = Path(__file__).resolve().parents[1] / "templates"
        env = Environment(loader=FileSystemLoader(templates))
        config = configparser.ConfigParser()
        config.read_file(io.StringIO(env.get_template("soularr.ini.j2").render(
            media_secrets={"lidarr": "test", "slskd_api": "test"})))
        self.assertEqual(config["Search Settings"]["allowed_filetypes"], "mp3 320,mp3 256,mp3 192,flac")
        self.assertEqual(config.getint("Search Settings", "number_of_albums_to_grab"), 2)


if __name__ == "__main__":
    unittest.main()
