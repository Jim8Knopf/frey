#!/usr/bin/env python3
"""Every template that imports the shared macros must still render.

This is the highest-blast-radius import in the repo. The macros in
playbooks/templates/frey_proxy.j2 emit the Traefik labels for most of Frey's
web services, so if the import stops resolving, or stops being given context,
the symptom is not a clear error - it is every service 404ing at once with
perfectly healthy containers.

Two things can break it, and both are silent:

  * Moving the file. playbooks/templates/ is the only directory on the
    template search path of EVERY role: Ansible resolves a template name
    against the running role's own templates/ and then the playbook's. A role
    cannot import from another role's templates/.

  * Dropping `with context`. Without it the macro body cannot see `frey` or
    `identity_protect`, so the hostnames come out as ".", nothing is
    recognised as protected, and the labels are malformed rather than absent.
"""
from pathlib import Path
import re
import sys
import unittest

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from freyharness import (  # noqa: E402
    ROOT, SHARED_TEMPLATES, inventory_vars, render_template,
)

SHARED_FILE = SHARED_TEMPLATES / 'frey_proxy.j2'

# Secrets and run-time facts the roles are handed by tasks, not by inventory.
STUBS = {
    'identity_secrets': {
        'lldap_admin_password': 'x', 'lldap_jwt_secret': 'x',
        'lldap_key_seed': 'x', 'authelia_ldap_password': 'x',
        'audiobookshelf_admin_password': 'x',
    },
    'monitoring_secrets': {'ntfy_topic': 'x', 'grafana_admin_password': 'x'},
    'monitoring_grafana_oidc': True,
    'monitoring_grafana_oidc_secret': 'x',
    'qbittorrent_password_hash': 'hash',
    'media_vpn_endpoint_lookup': {'stdout_lines': ['198.51.100.10 ep']},
    'media_vpn_proxy_network': {
        'network': {'IPAM': {'Config': [{'Subnet': '172.18.0.0/16'}]}}},
}


def importers():
    """Role templates that import the shared macro file, and their role."""
    found = []
    for path in sorted(ROOT.glob('roles/*/templates/**/*.j2')):
        text = path.read_text()
        if 'frey_proxy.j2' in text:
            found.append((path.parent.parent.name, path))
    return found


def media_secret_stubs(variables):
    keys = (((variables.get('media_acquisition') or {}).get('configure') or {})
            .get('secret_keys') or [])
    secrets = {key: 'secret' for key in keys}
    secrets.update({
        'jellyfin_admin_password': 'x', 'qbittorrent_password': 'x',
        'jellystat_postgres_password': 'x', 'jellystat_jwt_secret': 'x',
    })
    return secrets


class SharedMacroFileTest(unittest.TestCase):
    def test_the_shared_file_is_where_every_role_can_import_it(self):
        self.assertTrue(
            SHARED_FILE.is_file(),
            f'{SHARED_FILE} is missing. It must live in playbooks/templates/ - '
            'the only directory on every role\'s template search path.')

    def test_something_actually_imports_it(self):
        """If nothing does, this whole mechanism is dead weight."""
        self.assertTrue(importers(), 'no role template imports frey_proxy.j2')

    def test_every_import_passes_context(self):
        offenders = []
        for role, path in importers():
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if 'frey_proxy.j2' not in line:
                    continue
                if not re.search(r'\{%-?\s*(import|from)\b', line):
                    continue  # a mention in a comment, not an import
                if 'with context' not in line:
                    offenders.append(
                        f'{path.relative_to(ROOT)}:{number}: {line.strip()}')
        self.assertEqual(
            [], offenders,
            'These imports omit `with context`, so the macros cannot see '
            '`frey` or `identity_protect` and will emit malformed labels '
            'rather than failing:\n  ' + '\n  '.join(offenders))


class ImportingTemplatesStillRenderTest(unittest.TestCase):
    """Render each importer for real, and sanity-check what came out."""

    def rendered(self, role, path):
        variables = inventory_vars(role, **STUBS)
        variables['media_secrets'] = media_secret_stubs(variables)
        return render_template(str(path.relative_to(ROOT)), variables)

    def test_each_importing_template_renders(self):
        for role, path in importers():
            with self.subTest(template=str(path.relative_to(ROOT))):
                text = self.rendered(role, path)
                self.assertTrue(text.strip(), 'rendered to nothing')

    def test_compose_output_is_still_valid_yaml_with_labels_intact(self):
        for role, path in importers():
            if path.name != 'docker-compose.yml.j2':
                continue
            with self.subTest(template=str(path.relative_to(ROOT))):
                compose = yaml.safe_load(self.rendered(role, path))
                self.assertIn('services', compose)
                # The failure mode this exists for: an import that resolves
                # but is given no context renders hostnames as a bare "." and
                # protects nothing. Assert at least one real router rule.
                labels = [
                    label
                    for service in compose['services'].values()
                    for label in (service.get('labels') or [])
                    if isinstance(label, str)
                ]
                rules = [x for x in labels if '.rule=' in x]
                if not rules:
                    continue  # a stack whose routers live on another container
                for rule in rules:
                    self.assertNotIn(
                        'Host(`.', rule,
                        'a hostname rendered empty - the macro was imported '
                        'without context')
                self.assertTrue(
                    any('hub.frey' in rule for rule in rules),
                    f'{role}: no canonical hub.frey router was emitted')

    def test_the_logging_macro_still_caps_every_log_it_is_used_for(self):
        """The only limit between a chatty container and a full NVMe."""
        for role, path in importers():
            if path.name != 'docker-compose.yml.j2':
                continue
            with self.subTest(template=str(path.relative_to(ROOT))):
                compose = yaml.safe_load(self.rendered(role, path))
                for name, service in compose['services'].items():
                    logging = service.get('logging')
                    if not logging:
                        continue
                    self.assertEqual('json-file', logging['driver'], name)
                    self.assertEqual('10m', logging['options']['max-size'], name)
                    self.assertEqual('3', str(logging['options']['max-file']), name)


if __name__ == '__main__':
    unittest.main()
