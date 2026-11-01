# Monitoring

`roles/monitoring` owns one Compose stack for metrics, logs, alerts, Grafana and
Dockge. Edit switches, thresholds and retention in
`inventory/group_vars/all/monitoring.yml`; image pins are in `images.yml`.

## Components

| Component | Purpose |
| --- | --- |
| Prometheus | Metrics and alert rules |
| node-exporter, cAdvisor | Host and container metrics |
| blackbox | HTTPS probes through Traefik |
| Alertmanager | Group, inhibit and route alerts |
| alert-relay | Queue notifications offline and deliver them to ntfy |
| Loki, Alloy | Store and collect container logs and the system journal |
| Grafana | Dashboards at `grafana.hub.frey` |
| Dockge | Stack status, logs and restarts at `dockge.hub.frey` |

Services publish no host ports. Web access goes through Traefik. Grafana uses
OIDC; Prometheus, Alertmanager and Dockge require admin forward authentication.
Grafana retains a local admin login for identity outages.

## Deploy and verify

```bash
ansible-playbook playbooks/site.yml --tags monitoring --check --diff > /tmp/monitoring-check.log 2>&1
ansible-playbook playbooks/site.yml --tags monitoring
ansible-playbook playbooks/site.yml --tags monitoring
scripts/monitoring-check.sh
scripts/monitoring-check.sh --test     # send a test notification
scripts/monitoring-check.sh --updates  # compare pinned image versions
```

First installation requires `proxy,pki,identity,monitoring`, or a full run.
Configuration is checked with promtool, amtool, Loki, Alloy, Compose and JSON
parsing before stack deployment. Image pulls are serial and reuse cached pins.

## Switches and overhead

`monitoring_enable` controls metrics, alerting, logs, Grafana, Dockge and host
collectors. Alerting requires metrics. Turning off Grafana leaves collection
and alerts running. Turning off logs removes Loki/Alloy and reduces disk writes.
Retention defaults to one year/20 GB for metrics and two weeks for logs.
Keep memory limits based on measured use; they are ceilings, not reservations.

`--tags dockge` runs the monitoring module. To disable Dockge, change
`monitoring_enable.dockge`; its probe and dashboard link follow that switch.
Deploy `monitoring,dashy` when changing dashboard visibility.

The first monitoring deployment migrates a standalone Dockge installation,
preserving its data and URL. It validates the replacement before removing the
old Compose file and restores the old service if startup fails.

## Alerts and offline operation

`critical` alerts notify loudly; `warning` alerts are quiet. Set thresholds in
`monitoring_thresholds`, core service probes in `monitoring_probe_core`, and
muted alert names in `monitoring_alerting.muted`.

The relay stores undelivered alerts on disk and reports what happened when the
uplink returns, including incidents that already recovered. A periodic Watchdog
alert detects a broken Prometheus/Alertmanager chain. The host's
`frey-monitor-watchdog.timer` can notify independently of Docker.

Host collectors cover Pi throttling and power, NVMe SMART/unsafe shutdowns,
AP clients, DHCP, DNS, NAT, network counters, containers and indexer status.
An HTTPS probe reaching the login redirect verifies routing/authentication,
not the protected application's own backend; container and application checks
provide the additional evidence.

## Troubleshooting

- **No host network metrics:** node-exporter uses a bridge because the firewall
  blocks container-to-host INPUT. Host scripts collect the actual radio counters.
- **HTTPS probes fail:** blackbox reaches the Traefik container and sets each
  service's Host header and TLS SNI. Check the route and mounted Frey CA.
- **Grafana login fails:** all OIDC endpoints use HTTPS through Traefik, including
  the back channel. Grafana mounts the Frey CA; Traefik provides Docker DNS aliases.
- **A container stops shipping logs after power loss:** `frey-log-repair scan`
  reports damaged JSON logs. The repair timer removes corrupt lines in place,
  preserves the inode, and restarts Alloy when needed. It exposes repair metrics.
- **Alerts do not arrive:** run the check script, inspect relay queue/heartbeat
  freshness and verify ntfy settings. Queued alerts during an outage are expected.

Host metrics are written atomically into `/opt/frey/metrics/textfile/*.prom`.
A new wired sensor can use that interface without another container. Add its
collector to `monitoring_host_collectors`; use a separate transport only when
sensors require one.
