# monitoring

Owns metrics, logs, alert delivery, Grafana and Dockge in one Compose project.
Settings: `inventory/group_vars/all/monitoring.yml`; image pins: `images.yml`.

```bash
ansible-playbook playbooks/site.yml --tags monitoring
scripts/monitoring-check.sh
```

First installation also needs `proxy,pki,identity`. `--tags dockge` runs the
monitoring module; `monitoring_enable.dockge` controls the service.

## Code layout

| Task file | Responsibility |
| --- | --- |
| `prepare.yml`, `secrets.yml` | Validate settings; create directories, user and network; resolve secrets |
| `images.yml` | Pull missing images serially with retries |
| `configure.yml`, `validate.yml` | Render and check service configuration and dashboards |
| `collectors.yml` | Install host collectors, watchdog and log-repair timers |
| `compose.yml`, `migrate_dockge.yml` | Validate Compose, migrate Dockge, deploy and check readiness |
| `report.yml` | Print service access information |

Static imports preserve task order and focused tags (`monitoring_config`,
`monitoring_collectors`). Images precede validators; collectors precede startup.

## Dockge migration

The first deployment transfers Dockge from its standalone project into
monitoring. Its name, URL and `/opt/frey/appdata/dockge` data stay the same.
The old Compose file is removed only after the new service answers. A failed
migration restores the standalone project. Data directories are never removed.

Dockge keeps its stacks mount read-only and requires Authelia protection because
it holds the Docker socket. Set `monitoring.dockge.stacks_writable` only if you
intend to permit temporary UI edits; Ansible overwrites them on deployment.

Operations and troubleshooting: [MONITORING](../../docs/MONITORING.md).
