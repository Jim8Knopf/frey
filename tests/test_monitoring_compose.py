"""Render actual Ansible templates to protect Dockge data, access and switches."""
from pathlib import Path
import unittest

from ansible.template import Templar, trust_as_template
from ansible.utils.vars import combine_vars
import yaml

ROOT = Path(__file__).resolve().parents[1]


def trusted(value):
    if isinstance(value, str):
        return trust_as_template(value)
    if isinstance(value, dict):
        return {k: trusted(v) for k, v in value.items()}
    if isinstance(value, list):
        return [trusted(v) for v in value]
    return value


class MonitoringComposeTest(unittest.TestCase):
    def setUp(self):
        paths = [ROOT / f'roles/{role}/defaults/main.yml' for role in ('monitoring', 'dashy')]
        paths += sorted(p for p in (ROOT / 'inventory/group_vars/all').glob('*.yml') if p.name != 'secrets.yml')
        self.variables = {}
        for path in paths:
            self.variables = combine_vars(self.variables, yaml.safe_load(path.read_text()), merge=True)
        self.variables.update(monitoring_secrets={'ntfy_topic': 'test', 'grafana_admin_password': 'test'},
                              monitoring_grafana_oidc=True, monitoring_grafana_oidc_secret='test')

    def render(self, path):
        return Templar(variables=trusted(self.variables)).template(
            trust_as_template((ROOT / path).read_text()))

    def compose(self):
        return yaml.safe_load(self.render('roles/monitoring/templates/docker-compose.yml.j2'))

    def test_dockge_preserves_data_and_requires_authenticated_https(self):
        dockge = self.compose()['services']['dockge']
        self.assertEqual(dockge['image'], 'louislam/dockge:' + self.variables['monitoring_versions']['dockge'])
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
        probes = Templar(variables=trusted(self.variables)).template(trust_as_template('{{ monitoring_probe_hostnames }}'))
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
