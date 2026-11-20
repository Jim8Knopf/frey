"""Render actual Ansible templates to protect Dockge data, access and switches."""
from pathlib import Path
import sys
import unittest

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from freyharness import inventory_vars, render_string, render_template  # noqa: E402


class MonitoringComposeTest(unittest.TestCase):
    def setUp(self):
        self.variables = inventory_vars(
            'monitoring', 'dashy',
            monitoring_secrets={'ntfy_topic': 'test',
                                'grafana_admin_password': 'test'},
            monitoring_grafana_oidc=True,
            monitoring_grafana_oidc_secret='test')

    def render(self, path):
        return render_template(path, self.variables)

    def compose(self):
        return yaml.safe_load(self.render('roles/monitoring/templates/docker-compose.yml.j2'))

    def test_dockge_preserves_data_and_requires_authenticated_https(self):
        dockge = self.compose()['services']['dockge']
        self.assertEqual(dockge['image'], self.variables['frey_images']['dockge'])
        self.assertIn('/opt/frey/appdata/dockge:/app/data', dockge['volumes'])
        self.assertIn('/opt/frey/stacks:/opt/frey/stacks:ro', dockge['volumes'])
        self.assertIn('DOCKGE_STACKS_DIR=/opt/frey/stacks', dockge['environment'])
        self.assertNotIn('ports', dockge)
        self.assertEqual(dockge['networks'], ['frey_proxy'])
        labels = dict(label.split('=', 1) for label in dockge['labels'])
        self.assertEqual(labels['frey.module'], 'monitoring')
        self.assertIn('authelia@file', labels['traefik.http.routers.dockge.middlewares'])
        self.assertEqual(labels['traefik.http.routers.dockge-http.middlewares'], 'to-canonical@file')

    def test_disabling_dockge_removes_service_probe_and_dashboard_link(self):
        self.variables['monitoring_enable']['dockge'] = False
        self.assertNotIn('dockge', self.compose()['services'])
        probes = render_string('{{ monitoring_probe_hostnames }}', self.variables)
        self.assertNotIn('dockge', probes)
        dashboard = self.render('roles/dashy/templates/conf.yml.j2')
        self.assertNotIn('dockge.hub.frey', dashboard)
        self.assertIn('grafana.hub.frey', dashboard)

    def test_dockge_can_run_without_metrics_logs_or_grafana(self):
        for key in ('metrics', 'alerting', 'logs', 'grafana'):
            self.variables['monitoring_enable'][key] = False
        self.assertEqual(set(self.compose()['services']), {'dockge'})

    def test_other_services_do_not_change_when_dockge_is_disabled(self):
        enabled = self.compose()
        enabled['services'].pop('dockge')
        self.variables['monitoring_enable']['dockge'] = False
        self.assertEqual(enabled, self.compose())


if __name__ == '__main__':
    unittest.main()
