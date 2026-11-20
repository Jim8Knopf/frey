#!/usr/bin/env python3
"""Guard the two duplications in this repo that can actually hurt.

78 keys are defined both in a role's defaults/main.yml and again in
inventory/group_vars/all. Most of that is deliberate and documented in
CLAUDE.md: a role's defaults are only in scope while that role runs, so
anything another module must read is declared in inventory as well.

A blanket "the two copies must agree" test was tried here and removed. It
fires on the nine keys where inventory deliberately chooses a different value
from the role default - the interfaces (eth0 -> wlan0), the captive-portal
switch, the autojoin thresholds, the NVMe boot order - which is exactly what
inventory is for. Overriding a default is normal, so a test that treats it as
drift just trains people to edit the test.

What is left are the two cases where the duplication is load-bearing.
"""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from freyharness import ROOT, role_defaults  # noqa: E402

import yaml  # noqa: E402

GROUP_VARS = ROOT / 'inventory/group_vars/all'


def flatten(data, prefix=''):
    out = {}
    for key, value in (data or {}).items():
        name = f'{prefix}{key}'
        if isinstance(value, dict):
            out.update(flatten(value, name + '.'))
        else:
            out[name] = value
    return out


def inventory_file(name):
    return yaml.safe_load((GROUP_VARS / name).read_text()) or {}


class SshIsSpelledOutInFullTest(unittest.TestCase):
    """inventory must define every sshd option the role default defines.

    CLAUDE.md: `security_baseline.ssh` is spelled out in full in inventory
    rather than relying on `hash_behaviour = merge`, because a half-rendered
    sshd drop-in is the one failure that cannot be fixed remotely - the Pi has
    no Ethernet port and no console, so both ways in are radios.

    That decision is only worth anything while the inventory copy stays
    complete. Add an option to the role default, forget inventory, and the
    merge silently supplies it from somewhere else - which is the exact
    dependency the duplication exists to avoid. This is the test that notices.
    """

    def test_inventory_covers_every_ssh_option_in_the_role_default(self):
        default_ssh = flatten(
            ((role_defaults('security_baseline') or {})
             .get('security_baseline') or {}).get('ssh') or {})
        inventory_ssh = flatten(
            (inventory_file('security.yml').get('security_baseline') or {})
            .get('ssh') or {})
        self.assertTrue(default_ssh, 'security_baseline.ssh has no role default')
        self.assertTrue(
            inventory_ssh,
            'security_baseline.ssh is not spelled out in '
            'inventory/group_vars/all/security.yml - see CLAUDE.md')
        missing = sorted(set(default_ssh) - set(inventory_ssh))
        self.assertEqual(
            [], missing,
            'These sshd options exist in roles/security_baseline/defaults/'
            'main.yml but not in inventory/group_vars/all/security.yml, so the '
            'rendered sshd config now depends on hash_behaviour = merge - the '
            'one thing CLAUDE.md says it must not:\n  '
            + '\n  '.join(missing))


class ApAddressIsWrittenOnceTest(unittest.TestCase):
    """The AP address is the one literal worth policing.

    10.20.0.1 is the only address that never changes and the only reliable way
    back into the Pi. It had four hardcoded copies; swapping the two radios is
    meant to be a two-line change in network.yml, so everything else should
    DERIVE it from frey.service_address or
    network_gateway.downstream.address.

    roles/network_gateway is exempt: it is the role that OWNS the address, and
    inventory/group_vars/all/network.yml mirrors it so other modules can read
    it. Addresses that merely start with the same digits - the trusted-device
    lease 10.20.0.10, the DHCP range ending 10.20.0.150 - are different
    addresses, hence the word boundary.
    """

    OWNER = 'network_gateway'

    def test_no_role_default_hardcodes_the_ap_address(self):
        offenders = []
        for path in sorted(ROOT.glob('roles/*/defaults/main.yml')):
            if path.parent.parent.name == self.OWNER:
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith('#'):
                    continue
                if re.search(r'\b10\.20\.0\.1(?!\d)', stripped):
                    offenders.append(
                        f'{path.relative_to(ROOT)}:{number}: {stripped}')
        self.assertEqual(
            [], offenders,
            'Use frey.service_address instead of writing the AP address out '
            'again:\n  ' + '\n  '.join(offenders))

    def test_the_address_is_defined_exactly_once(self):
        """And it is still defined, in the file that owns it."""
        downstream = (
            inventory_file('network.yml').get('network_gateway') or {}
        ).get('downstream') or {}
        self.assertEqual('10.20.0.1', downstream.get('address'))


if __name__ == '__main__':
    unittest.main()
