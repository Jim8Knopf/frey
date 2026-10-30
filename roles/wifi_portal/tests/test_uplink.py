import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("uplink", Path(__file__).parents[1] / "files" / "uplink.py")
uplink = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uplink)

GOOD = "11111111-1111-4111-8111-111111111111"
AP = "22222222-2222-4222-8222-222222222222"


class UplinkTests(unittest.TestCase):
    def setUp(self):
        self.calls = []

    def run_nmcli(self, *args):
        self.calls.append(args)
        if args == ("-g", "UUID", "connection", "show"):
            return f"{GOOD}\n{AP}"
        if args[:2] == ("-g", "connection.type"):
            return "802-11-wireless"
        if args[:2] == ("-g", "connection.interface-name"):
            return "wlan1" if args[-1] == GOOD else "wlan0"
        if args[:2] == ("-g", "802-11-wireless.mode"):
            return "infrastructure" if args[-1] == GOOD else "ap"
        if args[:2] == ("-g", "802-11-wireless.ssid"):
            return "Camp"
        if args[:3] == ("--wait", "30", "connection"):
            return ""
        raise AssertionError(args)

    def test_excludes_access_point(self):
        self.assertEqual(uplink.saved_networks("wlan1", "wlan0", self.run_nmcli), [{"uuid": GOOD, "ssid": "Camp"}])

    def test_connection_is_scoped_to_uplink(self):
        uplink.connect_saved(GOOD, "wlan1", "wlan0", self.run_nmcli)
        self.assertEqual(self.calls[-1], ("--wait", "30", "connection", "up", "uuid", GOOD, "ifname", "wlan1"))

    def test_cannot_activate_access_point_or_inject_arguments(self):
        for bad in (AP, "--help", "a; reboot"):
            with self.assertRaises(uplink.UplinkError):
                uplink.connect_saved(bad, "wlan1", "wlan0", self.run_nmcli)
        self.assertFalse(any(call[:2] == ("--wait", "30") for call in self.calls))

    def test_same_interface_is_rejected(self):
        with self.assertRaises(uplink.UplinkError):
            uplink.connect_saved(GOOD, "wlan0", "wlan0", self.run_nmcli)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
