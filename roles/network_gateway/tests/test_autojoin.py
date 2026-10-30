#!/usr/bin/env python3
"""Exercise autojoin decisions with a fake NetworkManager, without radios."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[1]


class AutojoinTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        defaults = yaml.safe_load((ROOT / 'defaults/main.yml').read_text())['network_gateway']
        options = defaults['upstream']['autojoin_open']
        options.update(state_dir=str(self.root / 'state'), scan_settle_seconds=0,
                       ssid_denylist=['Blocked'], unusable_grace_seconds=1)
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        env.filters['quote'] = shlex.quote
        template = env.from_string((ROOT / 'templates/frey-uplink-autojoin.sh.j2').read_text())
        self.script = self.root / 'autojoin'
        self.script.write_text(template.render(network_gateway=defaults))
        self.stub('ip', '#!/bin/sh\nexit 0\n')
        self.stub('logger', '#!/bin/sh\nexit 0\n')
        self.stub('nmcli', '''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f: f.write(' '.join(args) + '\\n')
if args[:4] == ['-g', 'GENERAL.STATE', 'device', 'show']: print(os.environ.get('STATE', '30 (disconnected)'))
elif args[:4] == ['-g', 'GENERAL.CONNECTION', 'device', 'show']: print(os.environ.get('PROFILE', 'frey-open-current'))
elif args[:3] == ['networking', 'connectivity', 'check']: print(os.environ.get('CONNECTIVITY', 'full'))
elif args[:4] == ['-g', 'SIGNAL,SECURITY,SSID', 'device', 'wifi']: print(os.environ.get('SCAN', ''))
elif args[:4] == ['-g', 'NAME', 'connection', 'show']: print(os.environ.get('PROFILES', ''))
elif args[:4] == ['-g', 'connection.autoconnect', 'connection', 'show']: print(os.environ.get('AUTO', 'yes'))
elif args[:4] == ['-g', 'connection.uuid', 'connection', 'show']: print(os.environ.get('UUID', '11111111-1111-1111-1111-111111111111'))
elif args[:4] == ['-g', '802-11-wireless.ssid', 'connection', 'show']: print(os.environ.get('SSID', 'Current'))
elif args[:4] == ['-g', 'NAME,TIMESTAMP', 'connection', 'show']: pass
elif args[:2] == ['connection', 'modify'] and os.environ.get('FAIL_MODIFY'): sys.exit(1)
''')
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'], CALLS=str(self.root / 'calls'))

    def stub(self, name, data):
        path = self.bin / name
        path.write_text(data)
        path.chmod(0o755)

    def run_script(self, **kwargs):
        subprocess.run(['bash', str(self.script)], env={**self.env, **kwargs}, check=True, capture_output=True, text=True)
        return (self.root / 'calls').read_text()

    def test_selection_skips_denied_secure_and_weak(self):
        calls = self.run_script(SCAN='95:--:Blocked\n90:WPA2:Secure\n20:--:Weak\n70:--:Good WiFi')
        self.assertIn('ssid Good WiFi autoconnect no', calls)
        self.assertNotIn('ssid Blocked', calls)
        self.assertNotIn('ssid Secure', calls)

    def test_slug_collision_has_distinct_keys(self):
        a = self.run_script(SCAN='70:--:A B')
        (self.root / 'calls').unlink()
        b = self.run_script(SCAN='70:--:A-B')
        self.assertNotEqual(next(x for x in a.splitlines() if x.startswith('connection add')), next(x for x in b.splitlines() if x.startswith('connection add')))

    def test_remembered_profiles_are_not_auto_connected(self):
        calls = self.run_script(STATE='100 (connected)', PROFILE='known', PROFILES='frey-open-old\nfrey-uplink-known')
        self.assertIn('connection modify frey-open-old connection.autoconnect no', calls)
        self.assertNotIn('connection modify frey-uplink-known', calls)

    def test_portal_is_not_disconnected(self):
        calls = self.run_script(STATE='100 (connected)', CONNECTIVITY='portal')
        self.assertNotIn('connection down', calls)
        self.assertFalse((self.root / 'state/unusable').exists())

    def test_disabled_connectivity_recovery_keeps_slow_saved_network(self):
        self.script.write_text(self.script.read_text().replace('UNUSABLE_GRACE="1"', 'UNUSABLE_GRACE="0"'))
        state = self.root / 'state'
        state.mkdir()
        (state / 'unusable').write_text('old 1\n')
        calls = self.run_script(STATE='100 (connected)', CONNECTIVITY='limited', PROFILE='frey-uplink-known')
        self.assertNotIn('networking connectivity check', calls)
        self.assertNotIn('connection down', calls)
        self.assertFalse((state / 'unusable').exists())

    def test_weak_open_network_can_be_selected(self):
        self.script.write_text(self.script.read_text().replace('MIN_SIGNAL="35"', 'MIN_SIGNAL="0"'))
        calls = self.run_script(SCAN='10:--:Weak')
        self.assertIn('ssid Weak autoconnect no', calls)

    def test_failed_open_connection_recovers_after_grace(self):
        self.run_script(STATE='100 (connected)', CONNECTIVITY='limited')
        health = self.root / 'state/unusable'
        key = health.read_text().split()[0]
        health.write_text(key + ' 1\n')
        calls = self.run_script(STATE='100 (connected)', CONNECTIVITY='limited')
        self.assertIn('connection down frey-open-current', calls)
        self.assertTrue((self.root / 'state/failed' / key).exists())

    def test_saved_connection_recovers_and_is_restored_after_backoff(self):
        self.run_script(STATE='100 (connected)', CONNECTIVITY='none', PROFILE='frey-uplink-known')
        health = self.root / 'state/unusable'
        health.write_text(health.read_text().split()[0] + ' 1\n')
        calls = self.run_script(STATE='100 (connected)', CONNECTIVITY='none', PROFILE='frey-uplink-known')
        uuid = '11111111-1111-1111-1111-111111111111'
        self.assertIn(f'connection modify uuid {uuid} connection.autoconnect no', calls)
        self.assertIn('connection down frey-uplink-known', calls)
        pause = self.root / 'state/paused' / uuid
        self.assertTrue(pause.exists())
        pause.write_text('1\n')
        (self.root / 'calls').unlink()
        calls = self.run_script(AUTO='no')
        self.assertIn(f'connection modify uuid {uuid} connection.autoconnect yes', calls)
        self.assertFalse(pause.exists())

    def test_saved_portal_is_left_connected(self):
        calls = self.run_script(STATE='100 (connected)', CONNECTIVITY='portal', PROFILE='frey-uplink-known')
        self.assertNotIn('connection down', calls)
        self.assertFalse((self.root / 'state/unusable').exists())

    def test_saved_profile_not_paused_without_valid_uuid(self):
        self.run_script(STATE='100 (connected)', CONNECTIVITY='none', PROFILE='frey-uplink-known', UUID='')
        health = self.root / 'state/unusable'
        health.write_text(health.read_text().split()[0] + ' 1\n')
        calls = self.run_script(STATE='100 (connected)', CONNECTIVITY='none', PROFILE='frey-uplink-known', UUID='')
        self.assertNotIn('connection down', calls)

    def test_restore_when_feature_disabled(self):
        self.run_script()
        uuid = '11111111-1111-1111-1111-111111111111'
        pause = self.root / 'state/paused' / uuid
        pause.write_text('9999999999\n')
        subprocess.run(['bash', str(self.script), '--restore'], env={**self.env, 'AUTO': 'no'}, check=True, capture_output=True, text=True)
        self.assertIn(f'connection modify uuid {uuid} connection.autoconnect yes', (self.root / 'calls').read_text())
        self.assertFalse(pause.exists())

    def test_restore_failure_preserves_pause_and_reports_failure(self):
        self.run_script()
        uuid = '11111111-1111-1111-1111-111111111111'
        pause = self.root / 'state/paused' / uuid
        pause.write_text('9999999999\n')
        result = subprocess.run(['bash', str(self.script), '--restore'], env={**self.env, 'AUTO': 'no', 'FAIL_MODIFY': '1'}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(pause.exists())

    def test_backoff_skips_network(self):
        self.run_script(STATE='100 (connected)', CONNECTIVITY='limited')
        health = self.root / 'state/unusable'
        health.write_text(health.read_text().split()[0] + ' 1\n')
        self.run_script(STATE='100 (connected)', CONNECTIVITY='limited')
        (self.root / 'calls').unlink()
        calls = self.run_script(SCAN='80:--:Current\n70:--:Other')
        self.assertIn('ssid Other autoconnect no', calls)
        self.assertNotIn('ssid Current autoconnect no', calls)


if __name__ == '__main__':
    unittest.main()
