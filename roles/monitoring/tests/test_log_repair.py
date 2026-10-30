#!/usr/bin/env python3
"""Exercise frey-log-repair against damaged Docker logs, without Docker.

The damage these tests reproduce is what an unclean shutdown does to Docker's
own json-file logs: ext4 commits the file's new size but not the data blocks
behind it, so after the next mount a run of log lines reads back as NUL bytes.
The daemon then refuses to stream that container's log at all and Alloy retries
against the hole for ever, which stops the container's logs reaching Loki while
`docker logs` still appears to work.

The two properties worth protecting here are the ones that make the repair safe
to run against a live file:

  * only damaged lines are removed - every intact line survives, in order;
  * the inode is preserved, because the daemon is holding the file open and
    appending to it. Replacing the file would leave it writing to an unlinked
    inode and the container's log would appear to stop for good.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[1]


def log_line(i):
    """One line in Docker's json-file format."""
    return (json.dumps({"log": f"line {i}\n", "stream": "stdout",
                        "time": "2026-10-30T20:00:00Z"}) + "\n").encode()


class LogRepairTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

        defaults = yaml.safe_load((ROOT / 'defaults/main.yml').read_text())['monitoring']
        defaults['textfile_dir'] = str(self.root / 'textfile')
        defaults['log_repair']['state_dir'] = str(self.root / 'state')

        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        rendered = env.from_string(
            (ROOT / 'templates/frey-log-repair.sh.j2').read_text()
        ).render(monitoring=defaults)

        # The script shells out to Docker for discovery; the byte-level repair
        # is the embedded Python, and that is what is under test. Extracting it
        # keeps these tests free of a Docker daemon while still testing the
        # code that actually ships, rather than a copy of it.
        self.core = self.root / 'core.py'
        self.core.write_text(
            re.search(r"<<'PY'\n(.*?)\nPY\n", rendered, re.S).group(1)
        )

    def run_core(self, path, mode):
        done = subprocess.run(
            ['python3', str(self.core), str(path), 'testctr', mode],
            capture_output=True, text=True, check=True)
        return done.stdout.strip()

    def damaged_log(self, intact=50, hole_at=20, hole=4096):
        """A json log with one run of NULs where lines used to be."""
        path = self.root / 'container-json.log'
        lines = [log_line(i) for i in range(intact)]
        path.write_bytes(b''.join(lines[:hole_at])
                         + b'\x00' * hole + b'\n'
                         + b''.join(lines[hole_at:]))
        return path

    # -- detection ------------------------------------------------------------

    def test_intact_log_is_left_alone(self):
        path = self.root / 'clean-json.log'
        path.write_bytes(b''.join(log_line(i) for i in range(10)))
        before = path.read_bytes()

        self.assertEqual(self.run_core(path, 'repair'), 'CLEAN|testctr')
        self.assertEqual(path.read_bytes(), before)

    def test_scan_reports_without_changing_anything(self):
        path = self.damaged_log()
        before = path.read_bytes()

        self.assertEqual(self.run_core(path, 'scan'), 'CORRUPT|testctr|1|4097')
        self.assertEqual(path.read_bytes(), before,
                         'scan mode must never modify the log')

    # -- repair ---------------------------------------------------------------

    def test_repair_removes_only_the_damaged_lines(self):
        path = self.damaged_log()

        self.assertEqual(self.run_core(path, 'repair'), 'REPAIRED|testctr|1|4097')

        lines = path.read_bytes().splitlines()
        self.assertEqual(len(lines), 50, 'every intact line must survive')
        self.assertEqual([json.loads(ln)['log'].strip() for ln in lines],
                         [f'line {i}' for i in range(50)],
                         'surviving lines must keep their content and order')
        self.assertNotIn(b'\x00', path.read_bytes())

    def test_repair_is_idempotent(self):
        path = self.damaged_log()
        self.run_core(path, 'repair')
        after_first = path.read_bytes()

        self.assertEqual(self.run_core(path, 'repair'), 'CLEAN|testctr')
        self.assertEqual(path.read_bytes(), after_first)

    def test_several_separate_holes_are_all_removed(self):
        path = self.root / 'container-json.log'
        lines = [log_line(i) for i in range(30)]
        path.write_bytes(b''.join(lines[:10]) + b'\x00' * 64 + b'\n'
                         + b''.join(lines[10:20]) + b'\x00' * 64 + b'\n'
                         + b''.join(lines[20:]))

        self.assertEqual(self.run_core(path, 'repair'), 'REPAIRED|testctr|2|130')
        self.assertEqual(len(path.read_bytes().splitlines()), 30)

    def test_damage_in_the_final_line_is_removed(self):
        """A hole at the tail is the common case: it is where the write was."""
        path = self.root / 'container-json.log'
        path.write_bytes(b''.join(log_line(i) for i in range(5)) + b'\x00' * 512)

        self.assertEqual(self.run_core(path, 'repair'), 'REPAIRED|testctr|1|512')
        self.assertEqual(len(path.read_bytes().splitlines()), 5)

    # -- the property that makes it safe on a live file -----------------------

    def test_inode_survives_and_an_open_appender_keeps_working(self):
        path = self.damaged_log()
        before = path.stat().st_ino

        # Exactly how Docker's json-file logger holds the file open.
        fd = os.open(path, os.O_WRONLY | os.O_APPEND)
        try:
            self.run_core(path, 'repair')
            os.write(fd, log_line(99))
        finally:
            os.close(fd)

        self.assertEqual(path.stat().st_ino, before,
                         'the daemon is holding this file open; the inode must '
                         'not change or it writes to an unlinked file')

        lines = path.read_bytes().splitlines()
        for line in lines:
            json.loads(line)
        self.assertEqual(json.loads(lines[-1])['log'].strip(), 'line 99',
                         'O_APPEND writes must land at the new end of file')


if __name__ == '__main__':
    unittest.main()
