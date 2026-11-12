#!/usr/bin/env python3
"""Check the Lidarr music profile's quality floor and ordering."""
import json
from pathlib import Path
import unittest

from jinja2 import Environment, FileSystemLoader


class LidarrQualityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        env = Environment(loader=FileSystemLoader(Path(__file__).resolve().parents[1] / "templates"))
        env.filters["to_json"] = json.dumps
        source = env.get_template("frey-lidarr-quality.py.j2").render(
            media_acquisition={"configure": {"key_file": "/tmp/keys"}},
            frey={"service_address": "127.0.0.1", "local_domain": "frey"})
        module = {"__name__": "quality_test"}
        exec(compile(source, "frey-lidarr-quality", "exec"), module)
        cls.policy = staticmethod(module["desired_profile"])

    def test_lossless_is_fallback_and_low_bitrate_is_disallowed(self):
        names = ["Trash Quality Lossy", "Poor Quality Lossy", "Low Quality Lossy",
                 "Mid Quality Lossy", "High Quality Lossy", "Lossless"]
        original = {"id": 3, "name": "Standard", "upgradeAllowed": True,
                    "items": [{"id": i, "name": name, "allowed": False,
                               "items": [{"quality": {"id": i}, "allowed": False}]}
                              for i, name in enumerate(names)]}
        policy = self.policy(original)
        self.assertFalse(policy["upgradeAllowed"])
        groups = {x["name"]: x for x in policy["items"]}
        self.assertFalse(groups["Poor Quality Lossy"]["allowed"])
        for name in names[2:]:
            self.assertTrue(groups[name]["allowed"])
            self.assertTrue(groups[name]["items"][0]["allowed"])
        order = [x["name"] for x in policy["items"]]
        self.assertLess(order.index("Lossless"), order.index("Low Quality Lossy"))
        self.assertFalse(original["items"][-1]["allowed"])


if __name__ == "__main__":
    unittest.main()
