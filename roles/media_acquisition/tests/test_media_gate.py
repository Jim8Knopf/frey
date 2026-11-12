#!/usr/bin/env python3
"""Exercise indexer recovery with simulated uplink and Servarr responses."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from jinja2 import Environment, FileSystemLoader


class MediaGateRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.state = root / "state"
        self.calls = root / "calls"
        self.valid = root / "valid"
        self.connectivity = root / "connectivity"
        self.metered = root / "metered"
        self.metered.write_text("no")
        self.docker_calls = root / "docker_calls"
        self.connectivity.write_text("full")
        self.valid.write_text("false")
        bin_dir = root / "bin"
        bin_dir.mkdir()
        commands = {
            "nmcli": f'#!/bin/sh\ncase "$*" in *GENERAL.METERED*) printf "GENERAL.METERED:"; cat "{self.metered}" ;; *) cat "{self.connectivity}" ;; esac\n',
            "logger": "#!/bin/sh\nexit 0\n",
            # qBittorrent is deliberately unavailable throughout this test.
            "curl": "#!/bin/sh\nexit 1\n",
            "docker": f'''#!/bin/sh
case "$*" in
  inspect*) printf true ;;
  stop*|start*) echo "$*" >> "{self.docker_calls}" ;;
  *API_ENDPOINT=health*) printf '%s' '[{{"source":"IndexerSearchCheck"}}]' ;;
  *API_ENDPOINT=indexer/testall*)
    echo test >> "{self.calls}"
    printf '[{{"isValid":%s}}]' "$(cat "{self.valid}")" ;;
esac
''',
        }
        for name, body in commands.items():
            path = bin_dir / name
            path.write_text(body)
            path.chmod(0o755)
        template_dir = Path(__file__).resolve().parents[1] / "templates"
        services = {
            "prowlarr": {"enabled": True, "port": 9696, "api_version": "v1"},
            "sonarr": {"enabled": False},
            "radarr": {"enabled": False},
            "lidarr": {"enabled": True, "port": 8686, "api_version": "v1"},
            "slskd": {"enabled": True},
        }
        environment = Environment(loader=FileSystemLoader(template_dir))
        environment.filters["bool"] = bool
        script = environment.get_template(
            "frey-media-gate.sh.j2"
        ).render(
            media_acquisition={"uplink_gating": {"mode": "pause", "grace_seconds": 300,
                               "metered_down_limit_kib": 256, "metered_up_limit_kib": 64},
                               "services": services},
            network_gateway={"upstream": {"interface": "wlan1"}},
            frey={"service_address": "127.0.0.1", "local_domain": "frey"},
        ).replace("STATE_DIR=/run/frey-media-gate", f"STATE_DIR={self.state}")
        self.script = root / "gate"
        self.script.write_text(script)
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")

    def apply(self):
        subprocess.run(["bash", str(self.script), "apply"], env=self.env, check=True)

    def test_failed_result_is_retried_and_outage_resets_cooldown(self):
        self.apply()
        self.assertFalse((self.state / "prowlarr-validated").exists())
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)
        self.assertFalse((self.state / "lidarr-validated").exists())
        self.apply()
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)
        self.connectivity.write_text("none")
        self.apply()
        self.valid.write_text("true")
        self.connectivity.write_text("full")
        self.apply()
        self.assertTrue((self.state / "prowlarr-validated").exists())
        self.assertTrue((self.state / "lidarr-validated").exists())
        self.assertEqual(len(self.calls.read_text().splitlines()), 4)

    def test_metered_soulseek_is_stopped_and_resumed(self):
        self.metered.write_text("yes")
        self.apply()
        self.assertTrue((self.state / "slskd-gated").exists())
        self.assertTrue((self.state / "soularr-gated").exists())
        self.metered.write_text("no")
        self.apply()
        self.assertFalse((self.state / "slskd-gated").exists())
        self.assertFalse((self.state / "soularr-gated").exists())
        self.assertEqual(self.docker_calls.read_text().splitlines(),
                         ["stop soularr", "stop slskd", "start slskd", "start soularr"])


if __name__ == "__main__":
    unittest.main()
