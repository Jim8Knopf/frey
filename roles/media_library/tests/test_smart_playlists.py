"""Check that a declared smart playlist lands somewhere Navidrome actually reads.

A .nsp file is imported silently or not at all: a wrong path, a wrong
extension or a body that is not strict JSON all produce the same symptom - a
playlist that never appears, with the reason at most a line in Navidrome's own
log. None of that fails a deploy, so it is asserted here instead.

The coupling worth pinning is between two files that have no reason to agree:
the task writes into `media.data_dir`/media/music, and the compose template
mounts some path at /music. If either moves, the playlists stop being found.
"""
from pathlib import Path
import json
import re
import sys
import unittest

import yaml

# CI runs `unittest discover -s roles/*/tests`, so only this directory is on
# the path - the shared harness has to be added explicitly.
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tests'))
from freyharness import (  # noqa: E402
    ROOT, inventory_vars, render_string, render_template,
)


class SmartPlaylistTest(unittest.TestCase):
    def setUp(self):
        self.variables = inventory_vars(
            'media_library',
            identity_secrets={},
            media_secrets={'jellystat_postgres_password': 'test',
                           'jellystat_jwt_secret': 'test'})

    def template(self, expression):
        return render_string(expression, self.variables)

    def playlists(self):
        return self.template('{{ media_library.navidrome.smart_playlists }}')

    def music_dir(self):
        return self.template('{{ media.data_dir }}/media/music')

    def test_at_least_one_playlist_is_declared(self):
        self.assertTrue(self.playlists())

    def test_the_music_directory_written_to_is_the_one_navidrome_mounts(self):
        compose = yaml.safe_load(render_template(
            'roles/media_library/templates/docker-compose.yml.j2',
            self.variables))
        navidrome = compose['services']['navidrome']
        mounts = [v.split(':') for v in navidrome['volumes']]
        music = [m for m in mounts if m[1] == '/music']
        self.assertEqual(len(music), 1, 'Navidrome must mount exactly one music path')
        self.assertEqual(music[0][0], self.music_dir())
        # Read-only is fine and deliberate - a smart playlist is never written
        # back - so assert it rather than letting a future change loosen it
        # on the assumption that playlists need write access.
        self.assertEqual(music[0][2], 'ro')
        # The directory has to be created before Docker can bind-mount it, or
        # Docker makes it as root and the scanner cannot read what is inside.
        tasks = (ROOT / 'roles/media_library/tasks/main.yml').read_text()
        self.assertIn('{{ media.data_dir }}/media/music', tasks)

    def test_every_playlist_body_is_strict_json(self):
        # The examples on navidrome.org carry `// comments`, which a .nsp file
        # does not accept. Declaring rules as YAML is what makes that
        # impossible; this asserts the result rather than trusting it.
        for playlist in self.playlists():
            body = json.dumps(playlist['rules'])
            self.assertEqual(json.loads(body), playlist['rules'])
            self.assertNotIn('//', body)

    def test_playlist_names_are_usable_as_filenames(self):
        names = [p['name'] for p in self.playlists()]
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertRegex(name, r'^[A-Za-z0-9][A-Za-z0-9 _.()-]*$')
            self.assertFalse(name.endswith('.nsp'), 'the task appends the extension')

    def test_auto_import_is_pinned_on_while_playlists_are_shipped(self):
        # Without this the .nsp files are inert, and nothing says why.
        compose = yaml.safe_load(render_template(
            'roles/media_library/templates/docker-compose.yml.j2',
            self.variables))
        self.assertIn('ND_AUTOIMPORTPLAYLISTS=true',
                      compose['services']['navidrome']['environment'])

    def test_the_shipped_shuffle_playlist_matches_every_track(self):
        shuffle = next(p for p in self.playlists() if p['name'] == 'random')
        self.assertEqual(shuffle['rules']['sort'], 'random')
        # playCount > -1 is upstream's idiom for "everything". A value of 0
        # would quietly mean "only tracks somebody has already played", which
        # on a fresh library is an empty playlist.
        self.assertEqual(shuffle['rules']['all'], [{'gt': {'playCount': -1}}])

    def test_every_limit_is_a_number_navidrome_will_honour(self):
        # The hand-written version of this playlist carried `limit: 500` as a
        # malformed JSON line; Navidrome dropped it in silence and the cap
        # never applied. A limit surviving as a STRING is the same class of
        # failure, so the type is the assertion.
        for playlist in self.playlists():
            for key in ('limit', 'limitPercent'):
                if key in playlist['rules']:
                    value = playlist['rules'][key]
                    self.assertIsInstance(value, int)
                    self.assertNotIsInstance(value, bool)
                    self.assertGreater(value, 0)

    def test_the_task_writes_a_dot_nsp_file_and_is_skippable(self):
        task = re.search(r'- name: Install the Navidrome smart playlists.*?(?=\n- name: )',
                         (ROOT / 'roles/media_library/tasks/main.yml').read_text(), re.S)
        self.assertIsNotNone(task)
        body = task.group(0)
        self.assertIn('.nsp', body)
        self.assertIn('to_nice_json', body)
        # Navidrome switched off must not leave a deploy writing into its
        # library, and the media_library tag must still reach this.
        self.assertIn('media_enable.navidrome', body)
        self.assertIn('media_library', body)


if __name__ == '__main__':
    unittest.main()
