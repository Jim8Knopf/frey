#!/usr/bin/env python3
"""Exercise the uplink watchdog's verdicts against a fixture bus, without radios.

The case that matters here is the one the watchdog used to miss: a radio that
is present, has a netdev, and sits in NetworkManager state 30 while its scan
engine has stopped finishing scans. That is indistinguishable from "parked
somewhere with nothing in range" by every signal except NetworkManager's
LastScan clock, so these tests pin both halves of that distinction.
"""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[1]

USB_ID = '0bda:c811'
VENDOR, PRODUCT = USB_ID.split(':')
DEVICE_PATH = '/org/freedesktop/NetworkManager/Devices/3'

# Uptime the fixture reports, in seconds. Comfortably past any stall
# threshold so "never scanned" is unambiguous rather than just-booted.
UPTIME_S = 36000
UPTIME_MS = UPTIME_S * 1000


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()

        defaults = yaml.safe_load((ROOT / 'defaults/main.yml').read_text())['network_gateway']
        watchdog = defaults['upstream']['usb_resilience']['watchdog']
        self.stall = int(watchdog['scan_stall_seconds'])
        watchdog.update(state_dir=str(self.root / 'state'), usb_id=USB_ID,
                        failures_before_action=1, cooldown_seconds=0)

        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        env.filters['quote'] = shlex.quote
        template = env.from_string((ROOT / 'templates/frey-uplink-usb-watchdog.sh.j2').read_text())
        self.script = self.root / 'watchdog'
        self.script.write_text(template.render(network_gateway=defaults))

        # Fixture bus: the adapter is present with a driver-bound interface,
        # and the uplink netdev exists. Individual tests take pieces away.
        self.usb = self.root / 'sys/bus/usb/devices/1-1'
        (self.usb / '1-1:1.0').mkdir(parents=True)
        (self.usb / 'idVendor').write_text(VENDOR + '\n')
        (self.usb / 'idProduct').write_text(PRODUCT + '\n')
        self.drivers = self.root / 'sys/bus/usb/drivers/rtw88_8821cu'
        self.drivers.mkdir(parents=True)
        (self.drivers / 'unbind').write_text('')
        (self.drivers / 'bind').write_text('')
        self.net = self.root / 'sys/class/net'
        (self.net / 'wlan1').mkdir(parents=True)
        self.uptime = self.root / 'uptime'
        self.uptime.write_text(f'{UPTIME_S}.00 {UPTIME_S}.00\n')

        self.stub('logger', '#!/bin/sh\nexit 0\n')
        self.stub('sleep', '#!/bin/sh\nexit 0\n')
        for tool in ('ip', 'usbreset', 'modprobe'):
            self.stub(tool, '#!/bin/sh\n'
                            f'echo "{tool} $*" >> "$CALLS"\n'
                            'exit 0\n')
        self.stub('nmcli', '#!/bin/sh\n'
                           'echo "nmcli $*" >> "$CALLS"\n'
                           'printf "%s\\n" "${NM_STATE:-30 (disconnected)}"\n')
        # busctl speaks two calls: resolve the device object, then read
        # LastScan off it. LAST_SCAN unset means the property is unreadable,
        # which is how a host without the D-Bus property is simulated.
        self.stub('busctl', '#!/bin/sh\n'
                            'echo "busctl $*" >> "$CALLS"\n'
                            'case "$*" in\n'
                            f'  *GetDeviceByIpIface*) [ -n "${{DEV_PATH-x}}" ] && printf \'o "%s"\\n\' "${{DEV_PATH:-{DEVICE_PATH}}}"; exit 0 ;;\n'
                            '  *LastScan*) [ -n "${LAST_SCAN:-}" ] && printf "x       %s\\n" "$LAST_SCAN"; exit 0 ;;\n'
                            'esac\n'
                            'exit 1\n')

        self.env = dict(
            os.environ,
            PATH=f'{self.bin}:' + os.environ['PATH'],
            CALLS=str(self.root / 'calls'),
            SYSFS_USB_DEVICES=str(self.root / 'sys/bus/usb/devices'),
            SYSFS_USB_DRIVERS=str(self.root / 'sys/bus/usb/drivers'),
            SYSFS_NET=str(self.net),
            PROC_UPTIME=str(self.uptime),
        )
        (self.root / 'calls').write_text('')

    def stub(self, name, data):
        path = self.bin / name
        path.write_text(data)
        path.chmod(0o755)

    def run_script(self, **kwargs):
        proc = subprocess.run(['bash', str(self.script)], env={**self.env, **kwargs},
                              check=True, capture_output=True, text=True)
        return proc.stdout

    def scan_finished_ago(self, seconds):
        """LastScan value for a scan that completed `seconds` ago."""
        return str(UPTIME_MS - seconds * 1000)

    # -- the fault this fix exists for ---------------------------------

    def test_frozen_scan_clock_while_disconnected_is_a_fault(self):
        out = self.run_script(LAST_SCAN=self.scan_finished_ago(self.stall + 60))
        self.assertIn('scan-stalled', out)
        self.assertIn('ip link set wlan1 down', (self.root / 'calls').read_text())

    def test_never_scanned_this_boot_is_a_fault(self):
        # -1 is NetworkManager's "no scan has ever finished"; uptime is then
        # the age, which catches an adapter that came up wedged.
        out = self.run_script(LAST_SCAN='-1')
        self.assertIn('scan-stalled', out)

    # -- and the states it must NOT touch ------------------------------

    def test_disconnected_but_still_scanning_is_healthy(self):
        """Parked in the wilderness: scans complete, they just find nothing."""
        out = self.run_script(LAST_SCAN=self.scan_finished_ago(5))
        self.assertNotIn('scan-stalled', out)
        # Reading state is fine; touching the radio is not.
        actions = [line for line in (self.root / 'calls').read_text().splitlines()
                   if not line.startswith(('nmcli', 'busctl'))]
        self.assertEqual([], actions)

    def test_connected_is_healthy_even_with_a_stale_clock(self):
        """Above state 30 the radio is plainly working; do not read the clock."""
        out = self.run_script(NM_STATE='100 (connected)',
                              LAST_SCAN=self.scan_finished_ago(self.stall * 10))
        self.assertNotIn('scan-stalled', out)

    def test_unreadable_scan_clock_falls_back_to_hardware_only(self):
        """No D-Bus property, no verdict - the old behaviour, not a reset loop."""
        out = self.run_script()
        self.assertNotIn('scan-stalled', out)
        self.assertNotIn('ip link set', (self.root / 'calls').read_text())

    def test_stall_check_can_be_disabled(self):
        defaults = yaml.safe_load((ROOT / 'defaults/main.yml').read_text())['network_gateway']
        watchdog = defaults['upstream']['usb_resilience']['watchdog']
        watchdog.update(state_dir=str(self.root / 'state2'), usb_id=USB_ID,
                        failures_before_action=1, cooldown_seconds=0,
                        scan_stall_seconds=0)
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        template = env.from_string((ROOT / 'templates/frey-uplink-usb-watchdog.sh.j2').read_text())
        self.script.write_text(template.render(network_gateway=defaults))
        out = self.run_script(LAST_SCAN='-1')
        self.assertNotIn('scan-stalled', out)

    # -- the hardware verdicts must still work -------------------------

    def test_missing_netdev_is_still_a_fault(self):
        (self.net / 'wlan1').rmdir()
        out = self.run_script(LAST_SCAN=self.scan_finished_ago(5))
        self.assertIn('no-netdev', out)

    def test_absent_usb_device_is_still_a_fault(self):
        (self.usb / 'idVendor').unlink()
        out = self.run_script(LAST_SCAN=self.scan_finished_ago(5))
        self.assertIn('usb-gone', out)

    def test_unavailable_state_is_still_a_fault(self):
        out = self.run_script(NM_STATE='20 (unavailable)',
                              LAST_SCAN=self.scan_finished_ago(5))
        self.assertIn('unavailable', out)

    # -- escalation --------------------------------------------------

    def test_scan_stall_escalates_instead_of_pinning_at_level_one(self):
        """The post-action check must not clear the ladder on a scan stall.

        Eight seconds cannot produce a scan, so declaring victory there would
        restart every recovery at level 1 and never reach the driver rebind
        that actually re-initialises the scanner.
        """
        stale = self.scan_finished_ago(self.stall + 60)
        levels = []
        for _ in range(4):
            self.run_script(LAST_SCAN=stale)
            levels.append((self.root / 'state/escalation_level').read_text().strip())
        self.assertEqual(['1', '2', '3', '4'], levels)
        calls = (self.root / 'calls').read_text()
        self.assertIn('ip link set wlan1 down', calls)
        self.assertIn(f'usbreset {USB_ID}', calls)
        self.assertIn('modprobe -r rtw88_8821cu', calls)

    def test_recovered_scan_clock_clears_the_ladder(self):
        self.run_script(LAST_SCAN=self.scan_finished_ago(self.stall + 60))
        self.assertEqual('1', (self.root / 'state/escalation_level').read_text().strip())
        self.run_script(LAST_SCAN=self.scan_finished_ago(5))
        self.assertEqual('0', (self.root / 'state/escalation_level').read_text().strip())
        self.assertEqual('0', (self.root / 'state/consecutive_failures').read_text().strip())


if __name__ == '__main__':
    unittest.main()
