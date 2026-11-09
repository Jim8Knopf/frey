#!/usr/bin/env python3
"""Render the real templates to prove the forwarded port opens and lands.

A forwarded port is worthless unless BOTH halves agree: Gluetun has to open
it on the tunnel, and qBittorrent has to be listening on that exact number.
These tests render the actual templates so the two cannot drift apart, and
so the YAML-folding trap documented in docker-compose.yml.j2 cannot come back
-- Ansible renders with trim_blocks, so a Jinja comment block above a "- "
list entry silently folds that entry into the previous value.
"""
from pathlib import Path
import unittest

from ansible.template import Templar, trust_as_template
from ansible.utils.vars import combine_vars
import yaml

ROOT = Path(__file__).resolve().parents[3]


def trusted(value):
    if isinstance(value, str):
        return trust_as_template(value)
    if isinstance(value, dict):
        return {k: trusted(v) for k, v in value.items()}
    if isinstance(value, list):
        return [trusted(v) for v in value]
    return value


class QbittorrentPortTest(unittest.TestCase):
    def setUp(self):
        paths = [ROOT / 'roles/media_acquisition/defaults/main.yml']
        paths += sorted(p for p in (ROOT / 'inventory/group_vars/all').glob('*.yml')
                        if p.name != 'secrets.yml')
        self.variables = {}
        for path in paths:
            self.variables = combine_vars(
                self.variables, yaml.safe_load(path.read_text()), merge=True)
        # Supplied at run time by the role rather than by inventory.
        self.variables.update(
            qbittorrent_password_hash='hash',
            media_secrets={key: 'secret' for key in
                           self.variables['media_acquisition']['configure']['secret_keys']},
            media_vpn_endpoint_lookup={'stdout_lines': ['198.51.100.10 endpoint']},
            media_vpn_proxy_network={'network': {'IPAM': {'Config': [{'Subnet': '172.18.0.0/16'}]}}},
        )

    def templar(self):
        return Templar(variables=trusted(self.variables))

    def render(self, path):
        return self.templar().template(trust_as_template((ROOT / path).read_text()))

    def gluetun(self):
        return yaml.safe_load(
            self.render('roles/media_acquisition/templates/docker-compose.yml.j2')
        )['services']['gluetun']

    def seed_conf(self):
        rendered = self.render('roles/media_acquisition/templates/qBittorrent.conf.j2')
        return dict(line.split('=', 1) for line in rendered.splitlines()
                    if '=' in line and not line.startswith('#'))

    def test_no_forwarded_port_leaves_the_tunnel_closed(self):
        """The default. Nothing is opened, and the role's own port is used."""
        self.variables['media_vpn']['forwarded_port'] = ''
        environment = self.gluetun()['environment']
        self.assertFalse([entry for entry in environment
                          if entry.startswith('FIREWALL_VPN_INPUT_PORTS')])
        self.assertEqual(self.seed_conf()['Session\\Port'], '51234')

    def test_forwarded_port_is_opened_and_listened_on(self):
        self.variables['media_vpn']['forwarded_port'] = 49152
        self.assertIn('FIREWALL_VPN_INPUT_PORTS=49152', self.gluetun()['environment'])
        self.assertEqual(self.seed_conf()['Session\\Port'], '49152')
        self.assertEqual(
            self.templar().template(trust_as_template(
                '{{ media_acquisition.vpn.qbittorrent_listen_port }}')), 49152)

    def test_the_forwarded_port_entry_does_not_swallow_the_next_one(self):
        """The trim_blocks trap: FIREWALL_* must not absorb the line below it."""
        self.variables['media_vpn']['forwarded_port'] = 49152
        environment = self.gluetun()['environment']
        opened = [entry for entry in environment
                  if entry.startswith('FIREWALL_VPN_INPUT_PORTS')]
        self.assertEqual(opened, ['FIREWALL_VPN_INPUT_PORTS=49152'])
        # Every entry stays a single KEY=VALUE, with no folded newline.
        for entry in environment:
            self.assertNotIn('\n', entry, f'{entry!r} folded a following entry')
        self.assertIn('DOT=on', environment)

    def test_the_tunnel_is_disabled_without_a_vpn(self):
        """With no tunnel there is nothing to forward, so the role port stands."""
        self.variables['media_vpn']['enabled'] = False
        self.variables['media_vpn']['forwarded_port'] = 49152
        self.assertNotIn(
            'gluetun',
            yaml.safe_load(self.render(
                'roles/media_acquisition/templates/docker-compose.yml.j2'))['services'])
        self.assertEqual(self.seed_conf()['Session\\Port'], '51234')


class QbittorrentBudgetTest(QbittorrentPortTest):
    def test_the_connection_budget_suits_a_venue_radio(self):
        """Guard the tuning: home-fibre defaults collapse a 0.6 Mbit/s uplink."""
        self.assertLessEqual(self.variables['media_qbittorrent_max_active_downloads'], 6)
        self.assertLessEqual(self.variables['media_qbittorrent_max_connections'], 200)
        self.assertLessEqual(
            self.variables['media_qbittorrent_max_connections_per_torrent'],
            self.variables['media_qbittorrent_max_connections'])
        self.assertLessEqual(
            self.variables['media_qbittorrent_max_active_downloads'],
            self.variables['media_qbittorrent_max_active_torrents'])


if __name__ == '__main__':
    unittest.main()
