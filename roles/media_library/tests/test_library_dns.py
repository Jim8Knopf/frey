#!/usr/bin/env python3
"""Every library container that talks to the internet must follow the uplink.

Docker bakes a container's upstream resolver in at CREATION time, so a
container made on one network cannot resolve anything after the van moves to
another until it is recreated. The stack's own resolver exists to paper over
that, and `dns:` is what points a container at it.

This had been applied to three of nine services. The other six -- Jellyfin
among them -- silently kept the resolver of whatever network they were born
on, which is why newly added films and shows arrived with no artwork: the
metadata providers were simply unresolvable. Verified on the Pi 2026-11-10:
jellyfin, audiobookshelf, navidrome and jellystat could not resolve
google.com at all, while seerr could.

The block is guarded on media_acquisition being enabled, because the resolver
belongs to that module and the library half must still come up without it.
"""
from pathlib import Path
import sys
import unittest

import yaml

# CI runs `unittest discover -s roles/*/tests`, so only this directory is on
# the path - the shared harness has to be added explicitly.
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tests'))
from freyharness import ROOT, inventory_vars, render_template  # noqa: E402

# Services that reach the internet: metadata, artwork, requests, update checks.
# jellystat-db is deliberately absent - it is PostgreSQL and never leaves the
# bridge, so giving it a resolver would be noise rather than coverage.
NEEDS_DNS = {
    'jellyfin', 'navidrome', 'audiobookshelf', 'seerr',
    'audiobookrequest', 'readmeabook', 'maintainerr', 'jellystat',
}


class LibraryResolverTest(unittest.TestCase):
    def setUp(self):
        self.variables = inventory_vars(
            'media_library',
            media_secrets={
                'jellyfin_admin_password': 'x',
                'qbittorrent_password': 'x',
                'jellystat_postgres_password': 'x',
                'jellystat_jwt_secret': 'x',
            },
        )

    def compose(self):
        rendered = render_template(
            'roles/media_library/templates/docker-compose.yml.j2', self.variables)
        return rendered, yaml.safe_load(rendered)

    def test_every_internet_facing_service_follows_the_uplink(self):
        rendered, compose = self.compose()
        services = compose['services']
        resolver = self.variables['media']['network']['resolver_address']

        missing = sorted(
            name for name in NEEDS_DNS
            if name in services and resolver not in (services[name].get('dns') or [])
        )
        self.assertEqual(
            missing, [],
            'these library services would keep their creation-time resolver '
            'and lose DNS when the uplink changes: %s' % missing)

    def test_the_resolver_is_not_given_to_the_database(self):
        _, compose = self.compose()
        if 'jellystat-db' in compose['services']:
            self.assertNotIn('dns', compose['services']['jellystat-db'])

    def test_the_library_still_renders_without_media_acquisition(self):
        """The resolver belongs to media_acquisition, so the guard must drop
        the dns: block rather than point at a container that is not there."""
        self.variables['frey']['modules']['enabled'] = [
            m for m in self.variables['frey']['modules']['enabled']
            if m != 'media_acquisition'
        ]
        rendered, compose = self.compose()
        resolver = self.variables['media']['network']['resolver_address']
        self.assertNotIn(resolver, rendered)
        for name, svc in compose['services'].items():
            self.assertNotIn('dns', svc, '%s still names a resolver' % name)
        # And the library itself is still there to serve media offline.
        self.assertIn('jellyfin', compose['services'])

    def test_no_dns_entry_swallowed_a_following_key(self):
        """trim_blocks guard: the block sits above `volumes:`, so a folded
        newline would turn the next key into part of the dns list."""
        rendered, compose = self.compose()
        for name, svc in compose['services'].items():
            for entry in (svc.get('dns') or []):
                self.assertNotIn('\n', str(entry))
                self.assertRegex(str(entry), r'^\d+\.\d+\.\d+\.\d+$')
            self.assertIn('volumes', svc, '%s lost its volumes key' % name)
        self.assertNotRegex(rendered, r'(?m)^\s+dns:\s*$\n\s+volumes:')


if __name__ == '__main__':
    unittest.main()
