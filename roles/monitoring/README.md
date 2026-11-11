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

## Dockge

Dockge requires Authelia protection because it holds the Docker socket. Its
stack mount is read-only by default; `monitoring.dockge.stacks_writable` allows
temporary UI edits, which Ansible overwrites on deployment.

Operations, migration and troubleshooting: [MONITORING](../../docs/MONITORING.md).
