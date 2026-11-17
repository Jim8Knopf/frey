import contextlib
import io
import pathlib
import tempfile
import types
import unittest
from unittest.mock import patch

from jinja2 import Template


def load():
    source = pathlib.Path(__file__).parents[1] / 'templates' / 'frey-riseup-renew.py.j2'
    services = {name: {'enabled': True} for name in ['qbittorrent', 'prowlarr', 'slskd', 'jackett', 'byparr']}
    rendered = Template(source.read_text()).render(media={'appdata_dir': '/tmp/frey-test'}, media_acquisition={'stack_dir': '/tmp/test-stack', 'services': services})
    module = types.ModuleType('riseup_renew')
    exec(compile(rendered, str(source), 'exec'), module.__dict__)
    return module


class CertificateChecks(unittest.TestCase):
    def setUp(self):
        self.module = load()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.module.PROFILE = str(pathlib.Path(self.temp.name) / 'profile')
        # PENDING is derived from PROFILE at import, so it must be redirected too.
        self.module.PENDING = self.module.PROFILE + '.restart-pending'

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


class GatewaySelection(unittest.TestCase):
    """A gateway dies far more often than the certificate expires.

    Measured 2026-11-17, five of Riseup's sixteen gateways refused TCP/80 --
    including the one the helper used to hardcode, which the API still
    advertised. The tunnel stayed down and every client sharing its network
    namespace stayed in `Created`, so nothing downloaded at all.
    """

    def setUp(self):
        self.module = load()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.module.PROFILE = str(pathlib.Path(self.temp.name) / 'profile')
        # PENDING is derived from PROFILE at import, so it must be redirected too.
        self.module.PENDING = self.module.PROFILE + '.restart-pending'

    def select(self, current, advertised, latencies):
        """Run main() with the probe results a parked van would see."""
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=current), \
             patch.object(self.module, 'candidates', return_value=advertised), \
             patch.object(self.module, 'latency', side_effect=lambda address: latencies.get(address)), \
             patch.object(self.module, 'obtain') as obtain, \
             patch.object(self.module, 'write') as write, \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        self.obtain = obtain
        self.write = write
        self.stdout = out.getvalue().strip()
        return write.call_args.args[0] if write.call_args else None

    def test_dead_gateway_is_replaced_even_while_the_certificate_is_valid(self):
        profile = self.select(['203.0.113.9'], ['198.51.100.1', '198.51.100.2'],
                              {'198.51.100.1': 0.4, '198.51.100.2': 0.1})
        self.assertEqual(self.stdout, 'updated')
        self.assertNotIn('203.0.113.9', profile)
        self.assertIn('remote 198.51.100.2 80', profile)
        # A valid certificate is reused rather than needlessly re-fetched.
        self.obtain.assert_not_called()

    def test_a_reachable_gateway_is_left_alone(self):
        profile = self.select(['203.0.113.9'], ['198.51.100.1'], {'203.0.113.9': 0.2})
        self.assertEqual(self.stdout, 'unchanged')
        self.assertIsNone(profile)
        self.write.assert_not_called()

    def test_every_live_gateway_is_written_nearest_first(self):
        profile = self.select(['203.0.113.9'], ['198.51.100.1', '198.51.100.2', '198.51.100.3'],
                              {'198.51.100.1': 0.4, '198.51.100.2': 0.1, '198.51.100.3': 0.2})
        remotes = [line.split()[1] for line in profile.splitlines() if line.startswith('remote ')]
        # Several remotes are what let OpenVPN ride out a dead gateway on its
        # own, with no timer run and nobody in the van to notice.
        self.assertEqual(remotes, ['198.51.100.2', '198.51.100.3', '198.51.100.1'])

    def test_dead_gateways_are_never_written(self):
        profile = self.select(['203.0.113.9'], ['198.51.100.1', '198.51.100.2'],
                              {'198.51.100.2': 0.1})
        remotes = [line.split()[1] for line in profile.splitlines() if line.startswith('remote ')]
        self.assertEqual(remotes, ['198.51.100.2'])

    def test_the_remote_list_is_capped(self):
        advertised = ['198.51.100.%d' % n for n in range(1, 16)]
        profile = self.select(['203.0.113.9'], advertised, {a: 0.1 for a in advertised})
        remotes = [line for line in profile.splitlines() if line.startswith('remote ')]
        self.assertEqual(len(remotes), self.module.REMOTES_MAX)

    def test_a_blocked_port_keeps_the_advertised_gateways(self):
        """Every probe failing means the venue blocks 80, not that Riseup is gone."""
        profile = self.select(['203.0.113.9'], ['198.51.100.1', '198.51.100.2'], {})
        remotes = [line.split()[1] for line in profile.splitlines() if line.startswith('remote ')]
        self.assertEqual(remotes, ['198.51.100.1', '198.51.100.2'])

    def test_the_gateway_name_is_not_pinned_to_one_host(self):
        profile = self.select(['203.0.113.9'], ['198.51.100.1'], {'198.51.100.1': 0.1})
        # Pinning a single CN is what stopped failover; the prefix still
        # rejects a certificate that is not a Riseup gateway's.
        self.assertIn('verify-x509-name vpn name-prefix', profile)
        self.assertNotIn('vpn02-par', profile)

    def test_a_silent_gateway_is_abandoned_quickly(self):
        profile = self.select(['203.0.113.9'], ['198.51.100.1'], {'198.51.100.1': 0.1})
        # OpenVPN's 120s default per remote made a dead gateway stall the
        # tunnel for minutes, which is most of what "it is not downloading"
        # looked like from inside the van.
        self.assertIn('connect-timeout %d' % self.module.CONNECT_TIMEOUT, profile)

    def test_no_uplink_leaves_a_valid_profile_untouched(self):
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['203.0.113.9']), \
             patch.object(self.module, 'latency', return_value=None), \
             patch.object(self.module, 'candidates', side_effect=OSError('no route')), \
             patch.object(self.module, 'write') as write, \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        # Parked off-grid every probe fails. Rewriting or failing here would
        # throw away a profile that is still the best one available.
        self.assertEqual(out.getvalue().strip(), 'unchanged')
        write.assert_not_called()

    def test_a_rewritten_profile_always_leaves_a_restart_marker(self):
        """Gluetun keeps serving the profile it started with.

        The deploy rewrites the profile before the container exists, so the
        marker is what carries "the tunnel is stale" across to the step that
        can actually rebuild it.
        """
        self.select(['203.0.113.9'], ['198.51.100.1'], {'198.51.100.1': 0.1})
        self.assertTrue(pathlib.Path(self.module.PENDING).exists())

    def test_a_current_tunnel_with_no_marker_does_not_restart(self):
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['198.51.100.1']), \
             patch.object(self.module, 'latency', return_value=0.1), \
             patch.object(self.module, 'restart_vpn_and_clients') as restart, \
             patch.object(self.module.sys, 'argv', ['frey-riseup-renew', '--restart']), \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        # The second deploy must report 0 changed and leave the tunnel alone.
        restart.assert_not_called()
        self.assertEqual(out.getvalue().strip(), 'unchanged')

    def restart_run(self, exists=True, current=False):
        """A --restart run against a profile whose gateways are reachable."""
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['198.51.100.1']), \
             patch.object(self.module, 'latency', return_value=0.1), \
             patch.object(self.module, 'container_exists', return_value=exists), \
             patch.object(self.module, 'tunnel_is_current', return_value=current), \
             patch.object(self.module, 'restart_vpn_and_clients') as restart, \
             patch.object(self.module.sys, 'argv', ['frey-riseup-renew', '--restart']), \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        return restart, out.getvalue().strip()

    def test_a_missing_tunnel_is_not_an_error_mid_first_install(self):
        """The profile is written before Compose creates the container."""
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run(exists=False)
        restart.assert_not_called()
        self.assertEqual(printed, 'unchanged')
        # Nothing to reconnect yet, so the marker has to survive for later.
        self.assertTrue(pathlib.Path(self.module.PENDING).exists())

    def test_a_tunnel_already_holding_the_profile_clears_the_stale_marker(self):
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run(current=True)
        restart.assert_not_called()
        self.assertEqual(printed, 'unchanged')
        self.assertFalse(pathlib.Path(self.module.PENDING).exists())

    def test_a_stale_tunnel_is_reconnected(self):
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run(current=False)
        restart.assert_called_once_with()
        self.assertEqual(printed, 'reconnected')

    def test_a_rewritten_profile_does_not_restart_a_tunnel_that_does_not_exist(self):
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['203.0.113.9']), \
             patch.object(self.module, 'candidates', return_value=['198.51.100.1']), \
             patch.object(self.module, 'latency', side_effect=lambda a: None if a == '203.0.113.9' else 0.1), \
             patch.object(self.module, 'container_exists', return_value=False), \
             patch.object(self.module, 'restart_vpn_and_clients') as restart, \
             patch.object(self.module, 'write'), \
             patch.object(self.module.sys, 'argv', ['frey-riseup-renew', '--restart']), \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        restart.assert_not_called()
        self.assertEqual(out.getvalue().strip(), 'updated')

    def test_current_remotes_reads_every_remote_line(self):
        pathlib.Path(self.module.PROFILE).write_text(
            'client\nproto tcp-client\nremote 198.51.100.1 80\nremote 198.51.100.2 80\nnobind\n')
        self.assertEqual(self.module.current_remotes(), ['198.51.100.1', '198.51.100.2'])

    def test_only_gateways_offering_openvpn_over_tcp_80_are_candidates(self):
        service = {'gateways': [
            {'ip_address': '198.51.100.1', 'host': 'vpn01-par.riseup.net',
             'capabilities': {'transport': [{'type': 'openvpn', 'protocols': ['tcp', 'udp'], 'ports': ['53', '80', '1194']}]}},
            {'ip_address': '198.51.100.2', 'host': 'vpn02-par.riseup.net',
             'capabilities': {'transport': [{'type': 'openvpn', 'protocols': ['udp'], 'ports': ['1194']}]}},
            {'ip_address': '198.51.100.3', 'host': 'vpn03-par.riseup.net',
             'capabilities': {'transport': [{'type': 'obfs4', 'protocols': ['tcp'], 'ports': ['80']}]}},
        ]}
        with patch.object(self.module, 'fetch', return_value=__import__('json').dumps(service).encode()):
            self.assertEqual(self.module.candidates(), ['198.51.100.1'])


if __name__ == '__main__':
    unittest.main()
