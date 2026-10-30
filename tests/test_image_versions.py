#!/usr/bin/env python3
"""Ensure every role's version reference is defined centrally."""
from pathlib import Path
import re
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


class ImageVersionsTest(unittest.TestCase):
    def test_tags_are_strings_and_only_defined_in_central_file(self):
        central = yaml.safe_load((ROOT / 'inventory/group_vars/all/images.yml').read_text())
        for group in ('media_versions', 'monitoring_versions', 'identity_versions'):
            self.assertTrue(central[group])
            self.assertTrue(all(isinstance(value, str) and value for value in central[group].values()), group)
        for group in ('traefik_version', 'dockge_version'):
            self.assertTrue(isinstance(central[group], str) and central[group])
        for path in (ROOT / 'inventory/group_vars/all').glob('*.yml'):
            if path.name in ('images.yml', 'secrets.yml'):
                continue
            variables = yaml.safe_load(path.read_text()) or {}
            for group in ('media_versions', 'monitoring_versions', 'identity_versions', 'traefik_version', 'dockge_version'):
                self.assertNotIn(group, variables, str(path))

    def test_role_references_have_a_tag(self):
        central = yaml.safe_load((ROOT / 'inventory/group_vars/all/images.yml').read_text())
        pattern = re.compile(r'\b(media_versions|monitoring_versions|identity_versions)\.([a-z_]+)')
        found = set()
        for path in (ROOT / 'roles').rglob('*'):
            if not path.is_file() or path.suffix not in ('.yml', '.j2'):
                continue
            for group, name in pattern.findall(path.read_text()):
                self.assertIn(name, central[group], f'{path}: {group}.{name}')
                found.add((group, name))
        for group in ('media_versions', 'monitoring_versions', 'identity_versions'):
            for name in central[group]:
                self.assertIn((group, name), found, f'unused {group}.{name}')


if __name__ == '__main__':
    unittest.main()
