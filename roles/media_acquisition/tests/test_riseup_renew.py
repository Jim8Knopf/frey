import importlib.util
import pathlib
import tempfile
import types
import unittest
from unittest.mock import patch

from jinja2 import Template


class CertificateChecks(unittest.TestCase):
    def setUp(self):
        source = pathlib.Path(__file__).parents[1] / 'templates' / 'frey-riseup-renew.py.j2'
        services = {name: {'enabled': True} for name in ['qbittorrent', 'prowlarr', 'slskd', 'jackett', 'byparr']}
        rendered = Template(source.read_text()).render(media={'appdata_dir': '/tmp/frey-test'}, media_acquisition={'stack_dir': '/tmp/test-stack', 'services': services})
        self.module = types.ModuleType('riseup_renew')
        exec(compile(rendered, str(source), 'exec'), self.module.__dict__)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.module.PROFILE = str(pathlib.Path(self.temp.name) / 'profile')

    def test_expiry_checks_client_certificate_not_server_ca(self):
        pathlib.Path(self.module.PROFILE).write_text(
            '<ca>\n-----BEGIN CERTIFICATE-----\nSERVER_CA\n-----END CERTIFICATE-----\n</ca>\n'
            '<cert>\n-----BEGIN CERTIFICATE-----\nCLIENT_CERT\n-----END CERTIFICATE-----\n</cert>\n')
        with patch.object(self.module.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0)) as run:
            self.assertTrue(self.module.still_valid())
            self.assertIn('CLIENT_CERT', run.call_args.kwargs['input'])
            self.assertNotIn('SERVER_CA', run.call_args.kwargs['input'])

    def test_missing_client_certificate_requires_renewal(self):
        pathlib.Path(self.module.PROFILE).write_text('<ca>only</ca>')
        self.assertFalse(self.module.still_valid())

    def test_invalid_certificate_requires_renewal(self):
        pathlib.Path(self.module.PROFILE).write_text('<cert>-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----</cert>')
        with patch.object(self.module.subprocess, 'run', return_value=types.SimpleNamespace(returncode=1)):
            self.assertFalse(self.module.still_valid())

    def test_restart_recreates_all_clients_after_vpn_is_healthy(self):
        with patch.object(self.module.subprocess, 'run') as run, \
             patch.object(self.module.subprocess, 'check_output', return_value='healthy'), \
             patch.object(self.module.os, 'unlink') as unlink:
            self.module.restart_vpn_and_clients()
        self.assertEqual(run.call_args_list[0].args[0], ['docker', 'restart', 'gluetun'])
        self.assertIn('--force-recreate', run.call_args_list[1].args[0])
        self.assertEqual(run.call_args_list[1].args[0][-5:], self.module.CLIENTS)
        unlink.assert_called_once_with(self.module.PENDING)


if __name__ == '__main__':
    unittest.main()
