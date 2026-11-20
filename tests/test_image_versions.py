#!/usr/bin/env python3
"""Every image pin is defined centrally, is used, and says where upstream is.

This test used to name the pin groups it checked - 'media_versions',
'monitoring_versions', 'identity_versions', 'traefik_version', 'dashy_version'.
Four pins added later (immich, silverbullet and the two local_ai ones) were
therefore never checked by it at all, because adding a pin and adding it to
that list are two separate acts and the second is easy to forget. It now
DISCOVERS the pins instead, so a new one is covered by writing it down.
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


def flatten(data, prefix=''):
    out = {}
    for key, value in (data or {}).items():
        if isinstance(value, dict):
            out.update(flatten(value, prefix + key + '.'))
        else:
            out[prefix + key] = value
    return out


def central_pins():
    """Every pin as Ansible reads it: dotted name -> tag."""
    return flatten(yaml.safe_load(IMAGES.read_text()))


class ImagePinsTest(unittest.TestCase):
    def test_line_parser_agrees_with_yaml(self):
        """The comment-aware parser must see exactly what Ansible sees.

        scripts/check-updates.py parses this file by line, because
        yaml.safe_load throws away the `# upstream:` comments and the line
        numbers --apply needs. That looser parse is only safe while it agrees
        with the real one, so this is the assertion that keeps it honest.
        """
        _, pins = cu.read_pins(IMAGES)
        self.assertEqual(
            {p.name: p.value for p in pins}, central_pins(),
            'the line parser and yaml.safe_load disagree about images.yml')

    def test_every_pin_is_a_non_empty_string(self):
        for name, value in sorted(central_pins().items()):
            self.assertIsInstance(value, str, name)
            self.assertTrue(value.strip(), name)
            self.assertNotEqual(value, 'latest', f'{name} must not track :latest')

    def test_every_pin_declares_where_upstream_is(self):
        """A pin with no `# upstream:` marker is a pin nothing checks."""
        _, pins = cu.read_pins(IMAGES)
        missing = [p.name for p in pins if not p.marker]
        self.assertEqual(
            [], missing,
            'add an `# upstream:` marker on the pin line for: '
            + ', '.join(missing))
        for pin in pins:
            self.assertIn(
                pin.resolver, KNOWN_RESOLVERS,
                f'{pin.name}: unknown resolver {pin.resolver!r}')
            if pin.resolver in ('github', 'dockerhub'):
                self.assertRegex(
                    pin.locator, r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$',
                    f'{pin.name}: expected owner/repo, got {pin.locator!r}')
            elif pin.resolver == 'lsio':
                self.assertRegex(pin.locator, r'^[a-z0-9-]+$', pin.name)
            else:
                self.assertTrue(
                    pin.marker.partition('-')[2].strip(),
                    f'{pin.name}: a hold must say why')

    def test_pins_are_not_redefined_outside_the_central_file(self):
        top_level = set(yaml.safe_load(IMAGES.read_text()))
        for path in (ROOT / 'inventory/group_vars/all').glob('*.yml'):
            if path.name in ('images.yml', 'secrets.yml'):
                continue
            variables = yaml.safe_load(path.read_text()) or {}
            for name in top_level:
                self.assertNotIn(name, variables, str(path))

    def test_role_references_resolve_and_nothing_central_is_unused(self):
        central = central_pins()
        groups = {
            name for name, value in
            (yaml.safe_load(IMAGES.read_text()) or {}).items()
            if isinstance(value, dict)
        }
        grouped = re.compile(r'\b(%s)\.([a-z0-9_]+)' % '|'.join(sorted(groups)))
        flat = {name for name in central if '.' not in name}
        used = set()
        for path in (ROOT / 'roles').rglob('*'):
            if not path.is_file() or path.suffix not in ('.yml', '.yaml', '.j2'):
                continue
            text = path.read_text()
            for group, leaf in grouped.findall(text):
                dotted = f'{group}.{leaf}'
                self.assertIn(dotted, central, f'{path}: {dotted} is not pinned')
                used.add(dotted)
            for name in flat:
                if re.search(r'\b%s\b' % re.escape(name), text):
                    used.add(name)
        for name in central:
            self.assertIn(name, used, f'{name} is pinned but nothing reads it')


class VersionShapeTest(unittest.TestCase):
    """The logic that decides what --apply writes into images.yml.

    An upstream version has to be respelled in the pin's own convention, and
    the convention differs per image: linuxserver's "v1.6.2-ls123" becomes
    "version-v1.6.2" for bazarr but "version-5.3.0_v2.1.2" for qbittorrent,
    and jellyfin keeps the -lsNN suffix that the others must not grow.
    Getting this wrong writes a tag that cannot be pulled - on a Pi that may
    have no uplink left to fix it.
    """

    def test_respell_keeps_the_pins_own_convention(self):
        cases = [
            # (pinned, upstream, expected)
            ('v3.7.16', 'v3.7.17', 'v3.7.17'),            # traefik
            ('4.7.0', 'v4.7.1', '4.7.1'),                 # dashy: upstream has v
            ('3.7.9', 'v3.8.0', '3.8.0'),                 # loki
            ('v1.12.1', 'v1.13.0', 'v1.13.0'),            # node_exporter
            ('0.64.2', 'v0.65.0', '0.65.0'),              # navidrome
            ('version-2.7.0.5723', '2.8.0.1-ls7',
             'version-2.8.0.1'),                          # prowlarr: no -ls
            ('version-v1.6.2', 'v1.7.0-ls9',
             'version-v1.7.0'),                           # bazarr: keeps its v
            ('version-5.3.0_v2.1.2', '5.4.0_v2.2.0-ls3',
             'version-5.4.0_v2.2.0'),                     # qbittorrent
            ('12.3ubu2604-ls56', '12.4ubu2604-ls57',
             '12.4ubu2604-ls57'),                         # jellyfin keeps -ls
            ('0.24.3014', '0.25.1-ls4', '0.25.1'),        # jackett
        ]
        for pinned, upstream, expected in cases:
            with self.subTest(pinned=pinned, upstream=upstream):
                self.assertEqual(expected, cu.respell(pinned, upstream))

    def test_respell_output_can_be_pulled_back_apart(self):
        """Respelling is stable: respelling an already-correct pin is a no-op."""
        for pinned, upstream in (
            ('v3.7.16', 'v3.7.16'),
            ('version-2.7.0.5723', '2.7.0.5723-ls1'),
            ('12.3ubu2604-ls56', '12.3ubu2604-ls56'),
        ):
            self.assertEqual(
                cu.respell(pinned, upstream),
                cu.respell(cu.respell(pinned, upstream), upstream))

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

    def test_apply_rewrites_only_the_value_and_keeps_the_marker(self):
        lines = [
            '---',
            'traefik_version: "v3.7.16"  # upstream: github:traefik/traefik',
            'media_versions:',
            '  # a comment that must survive',
            '  jellyfin: "12.3ubu2604-ls56"  # upstream: lsio:jellyfin',
        ]
        pin = cu.Pin('traefik_version', 'v3.7.16', 'github:traefik/traefik', 1, '')
        pin.state, pin.proposed = 'behind', 'v3.7.17'
        held = cu.Pin('media_versions.jellyfin', '12.3ubu2604-ls56',
                      'lsio:jellyfin', 4, 'media_versions')
        held.state = 'current'
        changed = cu.apply_changes(lines, [pin, held], allow_major=False)
        self.assertEqual(['traefik_version'], [p.name for p in changed])
        self.assertEqual(
            'traefik_version: "v3.7.17"  # upstream: github:traefik/traefik',
            lines[1])
        self.assertEqual('  # a comment that must survive', lines[3])
        self.assertEqual(
            '  jellyfin: "12.3ubu2604-ls56"  # upstream: lsio:jellyfin',
            lines[4])

    def test_watch_pins_are_reported_but_never_applied(self):
        """`watch` means the version number cannot decide the upgrade.

        Open WebUI is the case this exists for: a silent minor bump can break
        WEBUI_AUTH_TRUSTED_EMAIL_HEADER, and Frey has no second login, so the
        failure is a lockout from the window you would use to diagnose it.
        """
        marker = 'watch github:open-webui/open-webui'
        pin = cu.Pin('local_ai_openwebui_version', 'v0.13.3', marker, 0, '')
        self.assertTrue(pin.no_apply)
        # The resolver and locator must still parse, or it would not be
        # checked at all - which is `hold`, not `watch`.
        self.assertEqual('github', pin.resolver)
        self.assertEqual('open-webui/open-webui', pin.locator)

        lines = ['local_ai_openwebui_version: "v0.13.3"  # upstream: ' + marker]
        pin.state, pin.proposed = 'behind', 'v0.14.0'
        self.assertEqual([], cu.apply_changes(lines, [pin], allow_major=False))
        self.assertEqual(
            'local_ai_openwebui_version: "v0.13.3"  # upstream: ' + marker,
            lines[0], 'a watch pin must survive --apply untouched')
        # Not even --allow-major may move it.
        pin.state = 'major'
        self.assertEqual([], cu.apply_changes(lines, [pin], allow_major=True))
        self.assertIn('v0.13.3', lines[0])

    def test_a_plain_pin_is_not_treated_as_watched(self):
        pin = cu.Pin('traefik_version', 'v3.7.16', 'github:traefik/traefik', 0, '')
        self.assertFalse(pin.no_apply)
        self.assertEqual('github', pin.resolver)
        self.assertEqual('traefik/traefik', pin.locator)

    def test_apply_refuses_a_major_unless_told(self):
        lines = ['jellystat_db: "18.1"  # upstream: github:x/y']
        def pin():
            p = cu.Pin('jellystat_db', '18.1', 'github:x/y', 0, '')
            p.state, p.proposed = 'major', '19.0'
            return p
        self.assertEqual([], cu.apply_changes(lines, [pin()], allow_major=False))
        self.assertEqual('jellystat_db: "18.1"  # upstream: github:x/y', lines[0])
        self.assertEqual(
            ['jellystat_db'],
            [p.name for p in cu.apply_changes(lines, [pin()], allow_major=True)])
        self.assertEqual('jellystat_db: "19.0"  # upstream: github:x/y', lines[0])


if __name__ == '__main__':
    unittest.main()
