#!/usr/bin/env python3
"""inventory/group_vars/all/images.yml is the only place an image is named.

Two earlier shapes of this test are worth remembering, because both failed in
the same direction - silently.

It first named the groups it checked ('media_versions', 'monitoring_versions',
'identity_versions', 'traefik_version', 'dashy_version'), so four pins added
later were never checked at all. It now DISCOVERS them.

Then it checked tags only, because tags were all images.yml held - the
registry path lived in whichever role ran the container, and Immich's database
and Redis images were not centralised at all. images.yml now holds the full
reference, and `test_no_image_is_named_outside_images_yml` is what keeps it
that way.
"""
import importlib.util
from pathlib import Path
import re
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / 'inventory/group_vars/all/images.yml'

# scripts/check-updates.py is not an importable module name (the hyphen), and
# testing it matters more than that inconvenience: the version-shape logic is
# what decides whether --apply writes a tag that can actually be pulled.
_spec = importlib.util.spec_from_file_location(
    'frey_check_updates', ROOT / 'scripts/check-updates.py')
cu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cu)

KNOWN_RESOLVERS = {'github', 'lsio', 'dockerhub', 'hold'}

# A `watch ` prefix on any of the above means "report a new version, never
# apply one". It is stripped before the resolver is read, so it needs no entry
# of its own here.


def images():
    """The one map: name -> full image reference."""
    return yaml.safe_load(IMAGES.read_text())['frey_images']


class OneFileTest(unittest.TestCase):
    def test_images_yml_defines_only_frey_images(self):
        """Nothing else may live in this file, or it stops being the one map."""
        self.assertEqual(['frey_images'], list(yaml.safe_load(IMAGES.read_text())))

    def test_line_parser_agrees_with_yaml(self):
        """The comment-aware parser must see exactly what Ansible sees.

        scripts/check-updates.py parses this file by line, because
        yaml.safe_load throws away the `# upstream:` comments and the line
        numbers --apply needs. That looser parse is only safe while it agrees
        with the real one, so this is the assertion that keeps it honest.
        """
        _, pins = cu.read_pins(IMAGES)
        self.assertEqual({p.name: p.image for p in pins}, images())

    def test_every_entry_is_a_usable_reference(self):
        for name, ref in sorted(images().items()):
            with self.subTest(image=name):
                self.assertIsInstance(ref, str)
                repo, tag, digest = cu.split_image(ref)
                self.assertTrue(repo, 'no repository')
                self.assertTrue(tag or digest, 'neither a tag nor a digest')
                self.assertNotEqual(tag, 'latest', 'must not track :latest')
                # A bare name with no registry is a Docker Hub library image,
                # which is fine - but it must still have a tag.
                self.assertNotIn(' ', ref)

    def test_no_image_is_named_outside_images_yml(self):
        """The point of the whole file: one place to look.

        Catches a registry path spelled out in a role again - the exact state
        this replaced, where the tag was central and `lscr.io/linuxserver/...`
        was repeated across ten role defaults.
        """
        registries = re.compile(
            r'\b('
            r'lscr\.io/|ghcr\.io/|gcr\.io/|quay\.io/|docker\.io/'
            r'|registry\.k8s\.io/'
            r')[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+')
        offenders = []
        for path in sorted(ROOT.glob('roles/**/*')):
            if not path.is_file() or path.suffix not in ('.yml', '.yaml', '.j2'):
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith('#') or stripped.startswith('{#'):
                    continue
                if registries.search(line):
                    offenders.append(
                        f'{path.relative_to(ROOT)}:{number}: {stripped}')
        self.assertEqual(
            [], offenders,
            'These name an image directly. Add it to frey_images in '
            'inventory/group_vars/all/images.yml and reference it:\n  '
            + '\n  '.join(offenders))

    def test_frey_images_is_not_redefined_elsewhere(self):
        for path in (ROOT / 'inventory/group_vars/all').glob('*.yml'):
            if path.name in ('images.yml', 'secrets.yml'):
                continue
            variables = yaml.safe_load(path.read_text()) or {}
            self.assertNotIn('frey_images', variables, str(path))


class MarkerTest(unittest.TestCase):
    def test_every_entry_declares_where_upstream_is(self):
        """An entry with no `# upstream:` marker is one nothing checks."""
        _, pins = cu.read_pins(IMAGES)
        missing = [p.name for p in pins if not p.marker]
        self.assertEqual(
            [], missing,
            'add an `# upstream:` marker on the line for: ' + ', '.join(missing))
        for pin in pins:
            with self.subTest(image=pin.name):
                self.assertIn(pin.resolver, KNOWN_RESOLVERS,
                              f'unknown resolver {pin.resolver!r}')
                if pin.resolver in ('github', 'dockerhub'):
                    self.assertRegex(
                        pin.locator, r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$',
                        f'expected owner/repo, got {pin.locator!r}')
                elif pin.resolver == 'lsio':
                    self.assertRegex(pin.locator, r'^[a-z0-9-]+$')
                else:
                    self.assertTrue(pin.marker.partition('-')[2].strip(),
                                    'a hold must say why')

    def test_every_entry_is_read_by_some_role(self):
        """An image nothing deploys is one somebody forgot to delete."""
        blob = []
        for path in sorted(ROOT.glob('roles/**/*')):
            if path.is_file() and path.suffix in ('.yml', '.yaml', '.j2'):
                blob.append(path.read_text())
        for path in sorted((ROOT / 'inventory/group_vars/all').glob('*.yml')):
            if path.name != 'images.yml':
                blob.append(path.read_text())
        text = '\n'.join(blob)
        unused = [name for name in images()
                  if f'frey_images.{name}' not in text]
        self.assertEqual([], unused,
                         'pinned but nothing reads it: ' + ', '.join(unused))

    def test_every_reference_resolves_to_a_real_entry(self):
        known = set(images())
        pattern = re.compile(r'frey_images\.([a-z0-9_]+)')
        for path in sorted(ROOT.glob('roles/**/*')):
            if not path.is_file() or path.suffix not in ('.yml', '.yaml', '.j2'):
                continue
            for name in pattern.findall(path.read_text()):
                self.assertIn(name, known,
                              f'{path.relative_to(ROOT)} references '
                              f'frey_images.{name}, which is not defined')


class CoupledEntriesTest(unittest.TestCase):
    """Entries that are not independent, asserted so they cannot drift."""

    def test_the_two_immich_images_share_a_version(self):
        """They are one application; a split version is a broken Immich."""
        server = cu.split_image(images()['immich_server'])[1]
        ml = cu.split_image(images()['immich_ml'])[1]
        self.assertEqual(server, ml,
                         'immich_server and immich_ml must be the same version')

    def test_the_local_readmeabook_build_tracks_its_upstream(self):
        """readmeabook_bilingual is built FROM readmeabook, in this repo.

        Its tag embeds the upstream version plus a `-bilingualN` suffix, so
        bumping readmeabook without bumping this builds the new upstream and
        labels it with the old version.
        """
        upstream = cu.split_image(images()['readmeabook'])[1]
        local = cu.split_image(images()['readmeabook_bilingual'])[1]
        self.assertTrue(
            local.startswith(upstream + '-'),
            f'readmeabook_bilingual is {local!r}, which does not start with '
            f'the upstream version {upstream!r}-')
        self.assertRegex(local, r'-bilingual\d+$')


class VersionShapeTest(unittest.TestCase):
    """The logic that decides what --apply writes into images.yml.

    An upstream version has to be respelled in the entry's own convention,
    and the convention differs per image: linuxserver's "v1.6.2-ls123" becomes
    "version-v1.6.2" for bazarr but "version-5.4.0_v2.2.0" for qbittorrent,
    while jellyfin keeps the -lsNN suffix the others must not grow. Getting
    this wrong writes a tag that cannot be pulled - on a Pi that may have no
    uplink left to fix it.
    """

    def test_split_image_handles_every_shape_in_use(self):
        cases = [
            ('traefik:v3.7.16', ('traefik', 'v3.7.16', '')),
            ('lscr.io/linuxserver/jellyfin:12.3ubu2604-ls56',
             ('lscr.io/linuxserver/jellyfin', '12.3ubu2604-ls56', '')),
            ('prom/prometheus:v3.15.1', ('prom/prometheus', 'v3.15.1', '')),
            ('gcr.io/cadvisor/cadvisor:v0.55.1',
             ('gcr.io/cadvisor/cadvisor', 'v0.55.1', '')),
            ('docker.io/valkey/valkey:9@sha256:abc',
             ('docker.io/valkey/valkey', '9', 'sha256:abc')),
            # A registry with a port must not be mistaken for a tag.
            ('registry.local:5000/thing', ('registry.local:5000/thing', '', '')),
            ('registry.local:5000/thing:1.2', ('registry.local:5000/thing', '1.2', '')),
        ]
        for ref, expected in cases:
            with self.subTest(reference=ref):
                self.assertEqual(expected, cu.split_image(ref))

    def test_join_image_round_trips(self):
        for ref in sorted(images().values()):
            with self.subTest(reference=ref):
                self.assertEqual(ref, cu.join_image(*cu.split_image(ref)))

    def test_respell_keeps_the_entrys_own_convention(self):
        cases = [
            ('v3.7.16', 'v3.7.17', 'v3.7.17'),            # traefik
            ('4.7.0', 'v4.7.1', '4.7.1'),                 # dashy
            ('3.7.9', 'v3.8.0', '3.8.0'),                 # loki
            ('v1.12.1', 'v1.13.0', 'v1.13.0'),            # node_exporter
            ('0.64.2', 'v0.65.0', '0.65.0'),              # navidrome
            ('version-2.7.0.5723', '2.8.0.1-ls7',
             'version-2.8.0.1'),                          # prowlarr: no -ls
            ('version-v1.6.2', 'v1.7.0-ls9',
             'version-v1.7.0'),                           # bazarr keeps its v
            ('version-5.3.0_v2.1.2', '5.4.0_v2.2.0-ls3',
             'version-5.4.0_v2.2.0'),                     # qbittorrent
            ('12.3ubu2604-ls56', '12.4ubu2604-ls57',
             '12.4ubu2604-ls57'),                         # jellyfin keeps -ls
            ('0.24.3014', '0.25.1-ls4', '0.25.1'),        # jackett
        ]
        for pinned, upstream, expected in cases:
            with self.subTest(pinned=pinned, upstream=upstream):
                self.assertEqual(expected, cu.respell(pinned, upstream))

    def test_compare_classifies_the_cases_that_matter(self):
        cases = [
            ('v3.7.16', 'v3.7.16', 'current'),
            ('v3.7.16', 'v3.7.17', 'behind'),
            ('3.7.9', 'v3.8.0', 'behind'),
            # A major is a migration, not a bump: jellyfin 10 -> 12 is one-way
            # and postgres refuses to start on an old cluster.
            ('2.19.0', 'v3.31.0', 'major'),
            ('18.1', '19.0', 'major'),
            # linuxserver's build suffix is not an upstream change.
            ('version-2.7.0.5723', '2.7.0.5723-ls9', 'current'),
            ('12.3ubu2604-ls56', '12.3ubu2604-ls56', 'current'),
            # A deliberately short pin tracks a line that moves on its own.
            ('1', '1.10.8', 'current'),
            ('3.14', '3.14.2', 'current'),
            # Pinned ahead of the latest release (prerelease, or images
            # published without a release) is not "behind".
            ('v3.42.0', 'v3.41.3', 'current'),
            ('', 'v1.0.0', 'unknown'),
            ('v1.0.0', '', 'unknown'),
        ]
        for pinned, upstream, expected in cases:
            with self.subTest(pinned=pinned, upstream=upstream):
                self.assertEqual(expected, cu.compare(pinned, upstream))


class ApplyTest(unittest.TestCase):
    def line(self, name, ref, marker):
        return f'  {name}: "{ref}"  # upstream: {marker}'

    def pin(self, name, ref, marker, lineno=0):
        return cu.Pin(name, ref, marker, lineno, 'frey_images')

    def test_apply_rewrites_only_the_tag_and_keeps_everything_else(self):
        lines = [
            'frey_images:',
            self.line('traefik', 'traefik:v3.7.16', 'github:traefik/traefik'),
            '  # a comment that must survive',
            self.line('jellyfin', 'lscr.io/linuxserver/jellyfin:12.3ubu2604-ls56',
                      'lsio:jellyfin'),
        ]
        moving = self.pin('traefik', 'traefik:v3.7.16',
                          'github:traefik/traefik', 1)
        moving.state, moving.proposed = 'behind', 'v3.7.17'
        staying = self.pin('jellyfin',
                           'lscr.io/linuxserver/jellyfin:12.3ubu2604-ls56',
                           'lsio:jellyfin', 3)
        staying.state = 'current'

        changed = cu.apply_changes(lines, [moving, staying], allow_major=False)
        self.assertEqual(['traefik'], [p.name for p in changed])
        self.assertEqual(
            self.line('traefik', 'traefik:v3.7.17', 'github:traefik/traefik'),
            lines[1], 'the registry path or the marker was disturbed')
        self.assertEqual('  # a comment that must survive', lines[2])
        self.assertEqual(
            self.line('jellyfin', 'lscr.io/linuxserver/jellyfin:12.3ubu2604-ls56',
                      'lsio:jellyfin'),
            lines[3], 'an up-to-date entry was touched')

    def test_apply_preserves_a_long_registry_path(self):
        ref = 'lscr.io/linuxserver/prowlarr:version-2.7.0.5723'
        lines = [self.line('prowlarr', ref, 'lsio:prowlarr')]
        pin = self.pin('prowlarr', ref, 'lsio:prowlarr')
        pin.state, pin.proposed = 'behind', 'version-2.8.0.1'
        cu.apply_changes(lines, [pin], allow_major=False)
        self.assertEqual(
            self.line('prowlarr',
                      'lscr.io/linuxserver/prowlarr:version-2.8.0.1',
                      'lsio:prowlarr'),
            lines[0])

    def test_watch_entries_are_reported_but_never_applied(self):
        """Open WebUI is the case this exists for.

        A silent minor bump can break WEBUI_AUTH_TRUSTED_EMAIL_HEADER, and
        Frey has no second login, so the failure is a lockout from the window
        you would use to diagnose it.
        """
        marker = 'watch github:open-webui/open-webui'
        ref = 'ghcr.io/open-webui/open-webui:v0.13.3'
        pin = self.pin('open_webui', ref, marker)
        self.assertTrue(pin.no_apply)
        # It must still be CHECKED - that is the difference from `hold`.
        self.assertEqual('github', pin.resolver)
        self.assertEqual('open-webui/open-webui', pin.locator)

        lines = [self.line('open_webui', ref, marker)]
        pin.state, pin.proposed = 'behind', 'v0.14.0'
        self.assertEqual([], cu.apply_changes(lines, [pin], allow_major=False))
        self.assertEqual(self.line('open_webui', ref, marker), lines[0])
        pin.state = 'major'
        self.assertEqual([], cu.apply_changes(lines, [pin], allow_major=True))
        self.assertIn('v0.13.3', lines[0])

    def test_a_plain_entry_is_not_treated_as_watched(self):
        pin = self.pin('traefik', 'traefik:v3.7.16', 'github:traefik/traefik')
        self.assertFalse(pin.no_apply)
        self.assertEqual('github', pin.resolver)
        self.assertEqual('traefik/traefik', pin.locator)

    def test_apply_refuses_a_major_unless_told(self):
        marker = 'github:x/y'
        def pin():
            p = self.pin('jellystat_db', 'postgres:18.1', marker)
            p.state, p.proposed = 'major', '19.0'
            return p
        lines = [self.line('jellystat_db', 'postgres:18.1', marker)]
        self.assertEqual([], cu.apply_changes(lines, [pin()], allow_major=False))
        self.assertIn('postgres:18.1', lines[0])
        self.assertEqual(
            ['jellystat_db'],
            [p.name for p in cu.apply_changes(lines, [pin()], allow_major=True)])
        self.assertIn('postgres:19.0', lines[0])


if __name__ == '__main__':
    unittest.main()
