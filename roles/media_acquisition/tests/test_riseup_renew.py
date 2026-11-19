import contextlib
import fcntl
import io
import ipaddress
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
        pathlib.Path(self.module.PENDING).write_text('')
        with patch.object(self.module.subprocess, 'run') as run, \
             patch.object(self.module.subprocess, 'check_output', return_value='healthy'):
            self.module.restart_vpn_and_clients()
        self.assertEqual(run.call_args_list[0].args[0], ['docker', 'restart', 'gluetun'])
        self.assertIn('--force-recreate', run.call_args_list[1].args[0])
        self.assertEqual(run.call_args_list[1].args[0][-5:], self.module.CLIENTS)
        # The marker is cleared once the rebuild has actually succeeded.
        self.assertFalse(pathlib.Path(self.module.PENDING).exists())

    def test_clearing_an_already_gone_marker_is_not_an_error(self):
        # Dying here would undo a rebuild that already worked.
        with patch.object(self.module.subprocess, 'run'), \
             patch.object(self.module.subprocess, 'check_output', return_value='healthy'):
            self.module.restart_vpn_and_clients()


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
             patch.object(self.module, 'latency', side_effect=lambda address, port=None: latencies.get(address)), \
             patch.object(self.module, 'have_internet', return_value=True), \
             patch.object(self.module, 'restarted_recently', return_value=False), \
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


class ComingBackOnline(unittest.TestCase):
    """Returning from a long stretch with no uplink.

    Two things go stale off-grid and neither repairs itself: the certificate
    expires (Riseup issues them for ~35 days) and the gateways in the profile
    can all be retired. OpenVPN then retries forever against a profile that
    cannot work, so the download clients stay down.
    """

    def setUp(self):
        self.module = load()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.module.PROFILE = str(pathlib.Path(self.temp.name) / 'profile')
        self.module.PENDING = self.module.PROFILE + '.restart-pending'

    def offline_run(self, material):
        with patch.object(self.module, 'still_valid', return_value=material is not None), \
             patch.object(self.module, 'existing_material', return_value=material), \
             patch.object(self.module, 'current_remotes', return_value=['203.0.113.9']), \
             patch.object(self.module, 'latency', return_value=None), \
             patch.object(self.module, 'candidates', side_effect=OSError('no route to host')), \
             patch.object(self.module, 'write') as write, \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        return write, out.getvalue().strip()

    def test_no_uplink_is_not_a_failure_even_once_the_certificate_expired(self):
        write, printed = self.offline_run(material=None)
        # Exiting non-zero would leave a failed unit on the monitoring for as
        # long as the van is parked, which is when a false alert is worst.
        self.assertEqual(printed, 'offline')
        write.assert_not_called()

    def test_no_uplink_leaves_a_still_valid_profile_alone(self):
        write, printed = self.offline_run(material=('CA', 'CERT', 'KEY'))
        self.assertEqual(printed, 'offline')
        write.assert_not_called()

    def test_a_captive_portal_answering_with_html_counts_as_offline(self):
        import json as _json
        with patch.object(self.module, 'still_valid', return_value=False), \
             patch.object(self.module, 'current_remotes', return_value=[]), \
             patch.object(self.module, 'candidates', side_effect=_json.JSONDecodeError('x', '<html>', 0)), \
             patch.object(self.module, 'write') as write, \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        self.assertEqual(out.getvalue().strip(), 'offline')
        write.assert_not_called()

    def test_a_changed_api_is_still_reported_loudly(self):
        """Parsed fine but held no usable gateway: somebody needs to know."""
        with patch.object(self.module, 'still_valid', return_value=False), \
             patch.object(self.module, 'current_remotes', return_value=[]), \
             patch.object(self.module, 'candidates', side_effect=ValueError('no gateway advertises OpenVPN over TCP')), \
             patch.object(self.module, 'write') as write:
            with self.assertRaises(ValueError):
                self.module.main()
        write.assert_not_called()

    def test_the_certificate_is_renewed_with_a_long_offline_margin(self):
        pathlib.Path(self.module.PROFILE).write_text(
            '<cert>\n-----BEGIN CERTIFICATE-----\nC\n-----END CERTIFICATE-----\n</cert>\n')
        with patch.object(self.module.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0)) as run:
            self.module.still_valid()
        argv = run.call_args.args[0]
        self.assertEqual(argv[argv.index('-checkend') + 1], str(self.module.RENEW_WITHIN))
        # The margin IS the off-grid tolerance, so it must stay generous.
        self.assertGreaterEqual(self.module.RENEW_WITHIN, 20 * 24 * 3600)


class UplinkDispatcherHook(unittest.TestCase):
    """The hook is what turns "internet came back" into a reconnect at once.

    Without it, recovery waits for the timer even though everything needed to
    fix the tunnel is already available.
    """

    def setUp(self):
        source = pathlib.Path(__file__).parents[1] / 'templates' / '88-frey-riseup-renew.j2'
        rendered = Template(source.read_text()).render(network_gateway={'upstream': {'interface': 'wlan1'}})
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        self.hook = root / 'hook'
        self.hook.write_text(rendered)
        self.calls = root / 'calls'
        stub = root / 'bin'
        stub.mkdir()
        systemd_run = stub / 'systemd-run'
        systemd_run.write_text('#!/bin/sh\nprintf "%%s\\n" "$*" >> %s\n' % self.calls)
        systemd_run.chmod(0o755)
        import os as _os
        self.env = dict(_os.environ, PATH='%s:%s' % (stub, _os.environ['PATH']))

    def dispatch(self, iface, action):
        import subprocess as _subprocess
        _subprocess.run(['sh', str(self.hook), iface, action], env=self.env, check=True)
        return self.calls.read_text() if self.calls.exists() else ''

    def test_the_uplink_coming_up_reconnects_the_tunnel(self):
        self.assertIn('frey-riseup-renew --restart', self.dispatch('wlan1', 'up'))

    def test_a_connectivity_verdict_change_reconnects_on_any_interface(self):
        # How a captive portal sign-in, or a dead backhaul behind an
        # already-associated AP, finally announces itself.
        self.assertIn('--restart', self.dispatch('eth0', 'connectivity-change'))

    def test_a_new_lease_reconnects(self):
        self.assertIn('--restart', self.dispatch('wlan1', 'dhcp4-change'))

    def test_the_ap_radio_is_ignored(self):
        # wlan0 is FreyHub itself; a client joining it says nothing about
        # internet, and reacting would probe gateways for nothing.
        self.assertEqual(self.dispatch('wlan0', 'up'), '')

    def test_losing_the_uplink_does_nothing(self):
        self.assertEqual(self.dispatch('wlan1', 'down'), '')

    def test_unrelated_actions_do_nothing(self):
        self.assertEqual(self.dispatch('wlan1', 'pre-up'), '')

    def test_the_work_is_handed_off_without_blocking(self):
        # Dispatcher scripts run serially; blocking here delays every other
        # hook and NetworkManager's own event handling.
        self.assertIn('--no-block', self.dispatch('wlan1', 'up'))


class ReconnectGuards(unittest.TestCase):
    """What stops a rebuild from happening when it should not.

    A rebuild is never free: every download client restarts, and while Gluetun
    is unhealthy Traefik drops the routers whose labels live on it, so
    qBittorrent and Prowlarr 404 for the duration.
    """

    def setUp(self):
        self.module = load()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        self.module.PROFILE = str(root / 'profile')
        self.module.PENDING = self.module.PROFILE + '.restart-pending'
        self.module.LOCK = str(root / 'lock')
        self.module.STAMP = str(root / 'stamp')

    def restart_run(self, exists=True, current=False, recent=False):
        """A --restart run against a profile whose gateways are reachable."""
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['198.51.100.1']), \
             patch.object(self.module, 'latency', return_value=0.1), \
             patch.object(self.module, 'container_exists', return_value=exists), \
             patch.object(self.module, 'tunnel_is_current', return_value=current), \
             patch.object(self.module, 'restarted_recently', return_value=recent), \
             patch.object(self.module, 'restart_vpn_and_clients') as restart, \
             patch.object(self.module.sys, 'argv', ['frey-riseup-renew', '--restart']), \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        return restart, out.getvalue().strip()

    def test_a_missing_tunnel_is_not_an_error_mid_first_install(self):
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run(exists=False)
        restart.assert_not_called()
        self.assertEqual(printed, 'unchanged')
        # Nothing to reconnect yet, so the marker must survive for later.
        self.assertTrue(pathlib.Path(self.module.PENDING).exists())

    def test_a_tunnel_already_holding_the_profile_clears_the_stale_marker(self):
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run(current=True)
        restart.assert_not_called()
        self.assertEqual(printed, 'unchanged')
        self.assertFalse(pathlib.Path(self.module.PENDING).exists())

    def test_a_stale_tunnel_is_reconnected(self):
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run()
        restart.assert_called_once_with()
        self.assertEqual(printed, 'reconnected')

    def test_a_current_tunnel_with_no_marker_does_not_restart(self):
        restart, printed = self.restart_run()
        # The second deploy must report 0 changed and leave the tunnel alone.
        restart.assert_not_called()
        self.assertEqual(printed, 'unchanged')

    def test_a_rebuild_just_done_defers_instead_of_repeating(self):
        pathlib.Path(self.module.PENDING).write_text('')
        restart, printed = self.restart_run(recent=True)
        restart.assert_not_called()
        self.assertEqual(printed, 'deferred')
        # Deferred, not dropped: the marker is what makes the next run do it.
        self.assertTrue(pathlib.Path(self.module.PENDING).exists())

    def test_a_flapping_uplink_does_not_look_like_dead_gateways(self):
        """The fix for 2026-11-18: 47 lease losses, 8 healthy gateways.

        The hook fires the instant the uplink returns, so the gateway probe
        can fail while the API fetch a moment later succeeds. Believing the
        probe rewrote the profile and rebuilt the tunnel for nothing.
        """
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['198.51.100.1']), \
             patch.object(self.module, 'latency', return_value=None), \
             patch.object(self.module, 'have_internet', return_value=False), \
             patch.object(self.module, 'candidates') as candidates, \
             patch.object(self.module, 'write') as write, \
             patch.object(self.module, 'restart_vpn_and_clients') as restart, \
             patch.object(self.module.sys, 'argv', ['frey-riseup-renew', '--restart']), \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        self.assertEqual(out.getvalue().strip(), 'offline')
        candidates.assert_not_called()
        write.assert_not_called()
        restart.assert_not_called()

    def test_unreachable_gateways_with_a_working_uplink_are_really_dead(self):
        """The other side of that judgement, which must still work."""
        with patch.object(self.module, 'still_valid', return_value=True), \
             patch.object(self.module, 'existing_material', return_value=('CA', 'CERT', 'KEY')), \
             patch.object(self.module, 'current_remotes', return_value=['203.0.113.9']), \
             patch.object(self.module, 'latency', side_effect=lambda a, port=None: None if a == '203.0.113.9' else 0.1), \
             patch.object(self.module, 'have_internet', return_value=True), \
             patch.object(self.module, 'candidates', return_value=['198.51.100.1']), \
             patch.object(self.module, 'restarted_recently', return_value=False), \
             patch.object(self.module, 'write') as write, \
             patch.object(self.module, 'container_exists', return_value=True), \
             patch.object(self.module, 'restart_vpn_and_clients') as restart, \
             patch.object(self.module.sys, 'argv', ['frey-riseup-renew', '--restart']), \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.main()
        self.assertEqual(out.getvalue().strip(), 'updated')
        self.assertIn('remote 198.51.100.1 80', write.call_args.args[0])
        restart.assert_called_once_with()

    def test_internet_is_probed_by_ip_not_hostname(self):
        # A hostname would make "do we have internet" depend on DNS, which is
        # one of the things that breaks when the uplink moves.
        for address in self.module.INTERNET_PROBES:
            ipaddress.ip_address(address)
        self.assertNotIn('9.9.9.9', self.module.INTERNET_PROBES)

    def test_only_one_instance_runs_at_a_time(self):
        """Several invocations land within seconds on a flapping uplink."""
        holder = open(self.module.LOCK, 'w', encoding='utf-8')
        self.addCleanup(holder.close)
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with patch.object(self.module, 'main') as inner, \
             contextlib.redirect_stdout(io.StringIO()) as out:
            self.module.locked_main()
        # A duplicate trigger is not a fault, so it says so and exits 0.
        inner.assert_not_called()
        self.assertEqual(out.getvalue().strip(), 'busy')

    def test_the_lock_is_released_for_the_next_run(self):
        with patch.object(self.module, 'main') as inner, contextlib.redirect_stdout(io.StringIO()):
            self.module.locked_main()
            self.module.locked_main()
        self.assertEqual(inner.call_count, 2)

    def test_a_restart_is_stamped_so_the_cooldown_can_see_it(self):
        self.assertFalse(self.module.restarted_recently())
        self.module.stamp()
        self.assertTrue(self.module.restarted_recently())


if __name__ == '__main__':
    unittest.main()
