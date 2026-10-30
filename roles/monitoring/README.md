# monitoring

Metrics, logs, dashboards, and the part that finds you when something breaks.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags monitoring --vault-password-file .vault_pass
```

The first deploy after enabling this module needs the proxy tag too, because
Traefik has to be told to publish its own metrics and that is a `service_proxy`
change:

```bash
--tags proxy,monitoring
```

## What you edit

`inventory/group_vars/all/monitoring.yml` — thresholds, retention, which
services are core, what is muted, image versions. Every number any alert
compares against is in one block in that file; the rules are generated from it.

Everything in this role is structure.

## What runs

| Container | Why |
| --- | --- |
| `prometheus` | Metrics, one year of them, and the alert rules |
| `alertmanager` | Grouping, inhibition, waiting out flapping |
| `alert-relay` | Turns alerts into phone notifications, and holds them when the van has no uplink |
| `node-exporter` | The host, plus everything the host collectors write |
| `cadvisor` | Per-container CPU, memory and restarts |
| `blackbox` | Does the service actually answer, through Traefik, over HTTPS |
| `loki` | Logs, a fortnight of them |
| `alloy` | Ships container logs and the system journal into Loki |
| `grafana` | The dashboards |

Plus two systemd timers on the host: `frey-metrics` (the collectors) and
`frey-monitor-watchdog` (the layer that still speaks when Docker is down).

## Variables it reads from outside the role

- `frey.*` — `service_domain`, `proxy_network`, `base_dir`, `pki_public_dir`
- `network_gateway.downstream.*` / `upstream.*` — radios, AP connection name
- `service_proxy.traefik.*` — container name, metrics port
- `identity_services`, `identity_hosts`, `identity_protect` — what to probe,
  and which routers get the forward-auth middleware
- `monitoring_*` — from `inventory/group_vars/all/monitoring.yml`

It reads `identity_hosts` from group_vars rather than the identity role's own
`identity` dict, deliberately: a role's defaults are only in scope while that
role runs, so depending on them would break this module whenever identity is
not in `frey.modules.enabled` — which is a case it is meant to survive.

## Three things that are not the obvious choice

All three were measured on this Pi, not assumed. The long versions are in
`templates/docker-compose.yml.j2`.

**node-exporter is on the bridge, with its network collectors off.** Host
networking is the usual advice and cannot work here: ufw is default-deny on
INPUT with allow rules scoped to `on wlan0` / `on wlan1`, so Prometheus could
never scrape a host-networked exporter. Mounting the host `/proc` does not
rescue the network metrics either, because `/proc/net` resolves per network
namespace — a containerised exporter reads its own veth and never sees `wlan0`.
Everything else in `/proc` and `/sys` is not namespaced, so CPU, memory, load,
filesystems and disk I/O are all correct. Real interface counters come from the
gateway host collector instead.

**blackbox probes the Traefik container with a per-service `Host` header.**
Probing by name is impossible: `*.hub.frey` is NXDOMAIN inside a container (the
Pi's resolver points at whatever DNS the campground handed out) and pointing a
container at dnsmasq times out, because dnsmasq is bound to the AP radio and
ignores queries arriving over a Docker bridge. Reaching Traefik on
`10.20.0.1:443` is blocked by the same firewall rule as above. So there is one
generated blackbox module per service, carrying the name in the `Host` header
and the TLS SNI. It survives Traefik being recreated and changing IP, which a
generated `extra_hosts` list would not.

**Grafana's OIDC back-channel is plain HTTP to `authelia:9091`.** Same DNS
problem, plus the Grafana image runs as a non-root uid that cannot add the Frey
CA to its trust store. The browser still goes to `https://auth.hub.frey`; only
the server-to-server token call is internal, and it never leaves the host.

## Alerting

```
Prometheus  →  Alertmanager  →  alert-relay  →  ntfy  →  your phone
```

Two severities and only two, so the distinction stays meaningful. `critical`
buzzes; `warning` arrives silently.

The relay exists because of the van. Alertmanager can POST to a webhook, but a
POST that fails for want of an uplink is simply lost — and parked off-grid is
precisely when you most want to know what happened. So the relay writes
undelivered alerts to disk with the time they really fired, and when an uplink
appears it sends a short report of what was missed and then the alerts
themselves. Alerts that broke *and fixed themselves* while you were offline are
still named in that report, which is usually the most interesting kind and
invisible everywhere else.

It is about 700 lines of Python standard library. No pip, no requirements file,
no build step: the component whose whole purpose is working when there is no
internet must not need internet in order to start.

### The dead man's switch

Monitoring that dies quietly is worse than none, because you believe you are
covered. Three layers:

1. `up == 0` and the collector metrics. Catches a dead exporter or a stalled
   collector. Needs Prometheus alive.
2. A `Watchdog` alert that fires every minute forever and is never notified
   about. The relay records each arrival; if they stop, the relay says so.
   Catches a dead Prometheus or Alertmanager, which layer 1 cannot.
3. `frey-monitor-watchdog.timer` on the host, which curls ntfy directly. Needs
   no Docker and no Prometheus, so it still speaks when the stack is down —
   including when the relay itself is what died.

## Every config is validated before anything restarts

`promtool check config`, `amtool check-config`, `loki -verify-config`,
`alloy validate`, `docker compose config`, `python -m py_compile` on the relay,
and a JSON parse of every dashboard. Same principle as `authelia
validate-config` in `roles/identity/`: a mistake is a failed deploy, not
monitoring that comes up looking healthy and evaluates nothing.

Alloy earns it most. A bad `config.alloy` does not stop Alloy from starting, it
stops it from *shipping*, and the only symptom is Grafana quietly showing no
logs.

## Checking it

```bash
scripts/monitoring-check.sh              # is it actually monitoring
scripts/monitoring-check.sh --test       # ...and send a test notification
scripts/monitoring-check.sh --updates    # ...and compare pinned versions
```

## Updating images

```bash
scripts/monitoring-check.sh --updates
# edit monitoring_versions in inventory/group_vars/all/images.yml
ansible-playbook ... --tags monitoring -e monitoring_update=true
```

cAdvisor is the one to be careful with: it is not on Docker Hub, and `v0.53.0`
and `v0.54.0` were never published at all, so "bump to the next number" is not
safe. Check the tag exists first.

## Adding a van sensor

node-exporter reads every `*.prom` file in `/opt/frey/metrics/textfile/`.
Anything that writes one is a monitored metric on the same terms as CPU
temperature — scraped, kept for a year, graphable, alertable. No broker, no
exporter, no container.

Add a `collect_<name>()` function to `templates/frey-metrics.sh.j2` and the name
to `monitoring_host_collectors`. There is a worked DS18B20 example at the bottom
of that file. Write `tmp`-then-`rename` or node-exporter will read a
half-written file and report nonsense.

Once a sensor is not physically wired to the Pi — a battery monitor, a Zigbee
thermometer, an ESP32 node — stop writing scripts and add MQTT. See
[docs/MONITORING.md](../../docs/MONITORING.md).

## What it deliberately does not do

**No remote access.** No tunnel, no exposed port, no third party holding a
dashboard. Grafana is reachable on FreyHub and nowhere else; the only thing that
leaves the van is an outbound notification. That was a decision, not an
omission.

**No log-based alerting.** Everything worth alerting on is already a metric, and
a second alerting path with its own Alertmanager connection is a second thing to
keep correct.

## Why this is not the archived monitoring role

`archive/legacy-stack/roles/monitoring/` had Prometheus, Grafana, Loki and 30
alert rules, and it could not have warned anyone about anything: there was no
Alertmanager and no receiver, so every one of those rules fired into a void. It
also downloaded its ten dashboards from grafana.com during the deploy, which on
a van with no uplink produces a working metrics database and an empty Grafana.
Both are fixed here rather than carried over.
