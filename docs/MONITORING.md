# Monitoring

Frey watches itself, and tells you when something is wrong before you notice it
yourself. This document is about what it watches, how it reaches you, and the
handful of decisions that are not the obvious ones.

The day-to-day file is `inventory/group_vars/all/monitoring.yml`. Every number
any alert compares against is in one block in it.

---

## The shape of it

```
                 ┌─────────────┐
   the Pi  ──────│ node-       │
   /proc /sys    │ exporter    │──┐
                 └─────────────┘  │
                 ┌─────────────┐  │     ┌────────────┐     ┌──────────────┐
   containers ───│ cAdvisor    │──┼────▶│ Prometheus │────▶│ Alertmanager │
                 └─────────────┘  │     │  1 year    │     │ group, wait, │
                 ┌─────────────┐  │     └────────────┘     │ inhibit      │
   HTTPS     ────│ blackbox    │──┤            │            └──────────────┘
   through       └─────────────┘  │            │                    │
   Traefik       ┌─────────────┐  │            ▼                    ▼
                 │ host        │  │     ┌────────────┐     ┌──────────────┐
   vcgencmd ─────│ collectors  │──┘     │  Grafana   │     │ alert-relay  │
   nvme-cli      │ (textfile)  │        │ dashboards │     │ holds when   │
   nmcli / iw    └─────────────┘        └────────────┘     │ offline      │
   docker                                                   └──────────────┘
                 ┌─────────────┐        ┌────────────┐              │
   logs      ────│ Alloy       │───────▶│   Loki     │              ▼
   journal       └─────────────┘        │  14 days   │          ntfy.sh
                                        └────────────┘              │
                                                                     ▼
                                                                your phone
```

Nothing publishes a port. Grafana, Prometheus and Alertmanager are reached
through Traefik at `grafana.hub.frey`, `prometheus.hub.frey` and
`alertmanager.hub.frey`; the rest talk only to each other on a private Docker
network.

---

## What it watches

### The host and the hardware

CPU, memory, load, filesystems, disk I/O — the ordinary things — plus the
van-specific ones that no off-the-shelf exporter reports:

- **Under-voltage and throttling.** The Pi 5 reports both directly. In a vehicle
  they mean the supply is sagging or the cabin is too hot, and under-voltage
  corrupts filesystems. It is the single most useful alert on the list here, and
  it is critical after one minute rather than the usual grace period: by the time
  it is sustained, writes have already happened at a voltage the flash was never
  promised.
- **PMIC power rails.** Volts and amps per rail, summed into an estimate of board
  draw. The beginning of answering "what does the van's server cost in
  amp-hours", which is why it is collected now rather than when a battery monitor
  arrives.
- **NVMe SMART.** Wear, temperature, media errors, and *unsafe shutdowns* — the
  drive's own count of the times the power was cut rather than halted. That
  counter is the only durable evidence it happened.
- **A read-only root filesystem**, which is how a dying NVMe announces itself.

### The gateway

The failures that make the van feel broken while every container is healthy:
the AP being down, DNS not answering, clients associated but holding no DHCP
lease, a working uplink with no NAT rule, a radio that flaps.

FreyHub's alerts are short-fused and loud. The uplink's are slow and quiet,
because no uplink is a normal state in a van and treating it as a fault would
mean a notification every time you move.

Captive portals get their own alert. They are the nastiest uplink state because
they look online to an application: DNS resolves, TCP connects, and every
request comes back as a sign-in page. `media_acquisition` already treats that as
"not usable"; this is the part that tells you to go and sign in.

### Containers and services

Two different questions, catching different failures.

`probe_success` asks **does it answer** — a real HTTPS request through Traefik,
as a browser would make it. A 302 to the login page counts as healthy, because
it proves Traefik routed the request, TLS worked and Authelia answered. A 404
does not, and that is the point: 404 is what Traefik returns when it has dropped
a router, which container metrics call perfectly healthy.

`frey_container_*` asks **is it even there**, from `docker ps` on the host rather
than from cAdvisor — because cAdvisor stops reporting a container that has gone
away, so the metric you need to detect a missing one is the one that disappears
with it.

Certificate expiry comes free with the probes, from the TLS handshake. Since
`frey_pki` renews at 30 days remaining, a warning at 14 days does not mean
"renew the certificate", it means renewal itself has stopped working — which
would otherwise surface as every device in the van refusing to connect on the
same afternoon.

### Logs

Container logs and the system journal, both in Loki, filterable by Frey module.
The journal half is the one that matters when the network misbehaves: an AP radio
reset or a USB adapter browning out appears there and nowhere else.

Debug and trace lines are dropped before storage. On an NVMe that also holds the
*arr databases and the media library, log volume is a real cost.

---

## How it reaches you

Two severities, and only two, so the distinction stays meaningful:

- **critical** — the van is degraded now, or is about to be. Buzzes your phone
  (ntfy priority 5, which bypasses Do Not Disturb on Android).
- **warning** — worth doing something about this week. Arrives silently.

If you find yourself wanting to mute a critical, it was the wrong severity.
Change it in `monitoring_thresholds` rather than training yourself to ignore the
loud ones. `monitoring_alerting.muted` exists for things you have consciously
decided to live with — they stay visible in Grafana, they just never notify.

### ntfy

The Pi POSTs out to a topic on ntfy.sh and your phone subscribes. Nothing
listens on an inbound port, nothing needs a domain, and it works from behind
campground NAT and through a captive portal the moment sign-in completes.

**The topic name is the password.** Anyone who knows it can read your alerts and
send you fake ones, so it is generated long and random on the Pi and printed
once, at the end of the first deploy. Subscribe to it on your phone and you are
done. Pin it in the vault as `vault_ntfy_topic` if you want a rebuild to keep
the topic your phone already has.

A self-hosted ntfy would only be reachable from FreyHub — which is the one
situation where you do not need a notification, because you are standing next to
the van. Hence the public relay.

### Being offline

This is the part the van makes necessary.

Alertmanager can POST to a webhook, and a POST that fails for want of an uplink
is simply lost. Parked off-grid for two days is precisely when you most want to
know that the NVMe started throwing errors on the first night.

So alerts go to `alert-relay`, which:

- sends immediately when it can;
- otherwise writes the alert to disk **with the time it really fired**;
- retries every minute, and when it gets through, leads with a short
  *while you were offline* report before the alerts themselves;
- names the alerts that **broke and recovered on their own** while you were
  offline. Nothing else records those — Alertmanager has forgotten them and the
  dashboard shows green — and they are usually the most interesting kind;
- drops anything older than 72 hours unread, because a three-day-old warning is
  history rather than news;
- caps a flush at 15 individual messages and summarises the rest, so a crash
  loop that ran for two days offline cannot burn a day's ntfy quota in one go.

The queue is on disk, written `tmp`-then-`rename`, so it survives a restart, an
image change and a power cut. In a van, power cuts are a normal event.

### When the monitoring itself breaks

Monitoring that dies quietly is worse than none, because you believe you are
covered. Three layers, each catching what the one above cannot:

1. **`up == 0` and the collector metrics.** A dead exporter, a stalled collector,
   a config that failed to reload. Needs Prometheus to be alive.
2. **The `Watchdog` alert.** Fires every minute, forever, and is never notified
   about — the relay just records that it arrived. If it *stops* arriving,
   something in the chain is broken and the relay says so. This is what catches a
   dead Prometheus or Alertmanager.
3. **`frey-monitor-watchdog.timer` on the host.** Checks the containers and the
   relay's heartbeat and curls ntfy directly. Needs no Docker and no Prometheus,
   so it still speaks when the whole stack is down — including when the relay
   itself is what died.

A stalled host collector deserves special mention, because it is the nastiest
failure mode here: it does not zero its metrics, it *freezes* them. The
dashboards keep showing the last value they saw and look perfectly healthy.
`FreyCollectorStale` exists for exactly that, using the timestamp node-exporter
puts on each textfile.

---

## Three things that are not the obvious choice

All three are forced by how this Pi is actually wired, and all three were
measured on the device rather than assumed.

### node-exporter is on the bridge, with its network collectors off

Host networking is the usual advice. It cannot work here: ufw runs default-deny
on INPUT with its allow rules scoped to `on wlan0` / `on wlan1`, so a packet from
a Docker bridge to the host is dropped and Prometheus could never scrape it.
(Tested: a container reaching `172.18.0.1:22` times out.)

Mounting the host `/proc` does not rescue the network metrics either, which is
the counter-intuitive half: `/proc/net` resolves **per network namespace**, so a
containerised exporter reading a mounted `/proc` still reports its own `eth0` and
never sees `wlan0`. (Tested: it listed `eth0` only.)

Everything else in `/proc` and `/sys` is not namespaced, so CPU, memory, load,
filesystems and disk I/O are all correct through the mounts. Real interface
counters come from the gateway host collector instead — which already reports
uplink state and AP clients, so network metrics end up in one coherent place
rather than split between a half-blind exporter and a script.

### blackbox probes the Traefik container with a per-service Host header

Probing `https://jellyfin.hub.frey/` by name is impossible from a container
here. The Pi's `/etc/resolv.conf` points at whatever DNS the campground handed
out, so `*.hub.frey` is NXDOMAIN; and pointing the container at dnsmasq on
`10.20.0.1` times out, because dnsmasq runs `bind-dynamic` with
`interface=wlan0` and only answers queries arriving on the AP radio. Reaching
Traefik on `10.20.0.1:443` is blocked by the same firewall rule as above.

So there is one generated blackbox module per service, carrying the service name
in the `Host` header and the TLS SNI, pointed at the Traefik container over the
shared proxy network. That exercises the real path — routing, certificate,
forward auth — and it keeps working when Traefik is recreated and changes IP,
which a generated `extra_hosts` list would not.

`roles/media_acquisition/` reached the same conclusion for the same reason; see
the Host-header note in `frey-media-gate.sh`.

### Grafana's OIDC back-channel is plain HTTP to `authelia:9091`

Grafana's backend has to call the token endpoint itself. Same DNS problem as
above, and even with a name it would have to trust the Frey CA — which the
Grafana image cannot do, because it runs as a non-root uid that cannot update its
trust store.

Talking to `authelia:9091` over the private Docker network sidesteps both. The
traffic never leaves the host, and OIDC does not care which URL the back-channel
used: tokens are validated against the issuer string, which stays
`https://auth.hub.frey` either way. Your browser still goes to the HTTPS name.

---

## What it deliberately does not do

**No remote access.** No tunnel, no exposed port, no third party holding a
dashboard. Grafana is reachable on FreyHub and nowhere else; the only thing that
leaves the van is an outbound notification. If you later want to *look* at the
dashboards from away rather than only be told, Tailscale is the thing to add —
it would also give a second way into the Pi, which matters on a machine with no
Ethernet and no console.

**No log-based alerting.** Everything worth alerting on is already a metric, and
a second alerting path with its own Alertmanager connection is a second thing to
keep correct.

**No dashboards downloaded at deploy time.** The archived stack fetched ten from
grafana.com during the run, which on a van with no uplink produces a working
metrics database and an empty Grafana. These five are files in the role. The
trade is that they are hand-built for this Pi rather than community dashboards
with a thousand panels — mostly an advantage, since no community dashboard knows
this machine lives in a van.

---

## Retention, and why it is asymmetric

A year of metrics, two weeks of logs.

Metrics are tiny and get more valuable with age. A year is what lets you answer
"is the NVMe running hotter than it did last summer", "is disk growth
accelerating", "how much power does the van draw overnight" — none of which a
fortnight can tell you. At this scrape volume it is a few GB against 3.4 TB free.

Logs are the opposite: bulky, write-heavy, and almost only ever read about
something recent.

Both have a **size** cap as well as a time cap, and the size cap is the one that
actually protects the Pi: it is what stops a log loop or a metrics explosion from
filling the disk that the databases and the media library share. Whichever limit
is hit first wins.

If the NVMe ever becomes a concern, `monitoring_enable.logs: false` is the
biggest single lever — Loki and Alloy are the heaviest writers here. Metrics and
alerting carry on untouched, and you lose searchable history rather than the
ability to be warned.

---

## Adding the van's sensors

This is built but not yet used, so that adding the first real sensor is a small
job rather than a redesign.

node-exporter reads every `*.prom` file in:

```
/opt/frey/metrics/textfile/
```

Anything that drops a file there is a monitored metric: scraped, stored for a
year, graphable in Grafana and alertable on exactly the same terms as CPU
temperature. No broker, no exporter, no container.

### A cabin thermometer wired to the Pi

A DS18B20 on the 1-Wire bus is about six lines. Add a function to
`roles/monitoring/templates/frey-metrics.sh.j2`:

```bash
collect_van() {
  local started temp
  started=$(date +%s.%N)
  temp=$(num "$(awk '{print $1/1000}' /sys/bus/w1/devices/28-*/temperature)")
  {
    echo "# HELP van_temp_celsius Cabin temperature."
    echo "# TYPE van_temp_celsius gauge"
    [[ -n "${temp}" ]] && echo "van_temp_celsius{location=\"cabin\"} ${temp}"
    collector_meta van "$([[ -n "${temp}" ]] && echo 1 || echo 0)" "${started}"
  } | emit van
}
```

Then add `van` to `monitoring_host_collectors` in `monitoring.yml`. The existing
timer runs it on the same clock as everything else, and `collector_meta` means a
broken sensor shows up as a failing collector rather than as a frozen graph.

**Write `tmp`-then-`rename`.** `emit` does this for you, and it is not optional:
node-exporter will happily read a half-written file and either report nonsense or
fail the entire scrape.

### When to add MQTT instead

The moment a sensor is **not physically wired to the Pi**. Battery monitors,
Zigbee thermometers and ESP32 nodes all speak MQTT, and at that point a broker
plus an MQTT-to-Prometheus bridge is the right answer rather than a script per
device.

Nothing in this stack has to change to allow it — that is what makes the textfile
directory a seam and not a workaround. Add Mosquitto and a bridge as a new
module, point the bridge at Prometheus, and the dashboards and alert rules work
the same way.

If van automation ever becomes the point — thermostats, switches, schedules —
Home Assistant becomes the better sensor hub, with Prometheus scraping it. There
is an archived `homeassistant` role to draw on. That is a bigger decision than a
sensor, which is why it is not pre-empted here.

---

## Day to day

```bash
# Is it actually monitoring?
scripts/monitoring-check.sh

# ...and prove a notification reaches your phone
scripts/monitoring-check.sh --test

# ...and see what has moved upstream
scripts/monitoring-check.sh --updates
```

The check script asserts the things that break silently: every container up,
every scrape target up, the rules actually loaded and not erroring, the host
collectors still *writing* (not merely present), the relay able to reach ntfy or
deliberately holding a queue, and logs still arriving.

Everything goes over SSH and through the containers, because nothing publishes a
host port and ufw blocks a Docker bridge from reaching the host anyway.

### Changing a threshold

Edit `monitoring_thresholds` in `inventory/group_vars/all/monitoring.yml`, then:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags monitoring --vault-password-file .vault_pass
```

Prometheus is reloaded rather than restarted, so there is no gap in the data and
— more importantly — no gap in the alerting at the moment you have just changed
the alerting.

The reload is `kill -HUP <host pid>` and **must not** become
`docker kill -s HUP`. dockerd sets `HasBeenManuallyStopped` on a container for
*any* signal sent through its API, not just a terminating one. The reload still
works and the container keeps running, so nothing looks wrong — but the
container is now flagged as stopped by the operator, and `unless-stopped`
honours that flag at the next daemon start. Prometheus then runs until the Pi
reboots and silently does not come back, alone among the containers.

That failure already happened once: a rules change HUPed Prometheus, the Pi
rebooted nine hours later, and FreyHub came up with no metrics and no alerting.
Nothing raised an alert, because **Prometheus is the thing that raises alerts** —
and that blind spot is structural. Alertmanager was unaffected only because its
own config had not changed in that run, so its handler never fired.

If you ever find Prometheus stopped with the rest of the stack healthy, check
the flag before blaming the TSDB:

```bash
docker inspect prometheus --format '{{.State.ExitCode}}'   # 255, logs empty
sudo python3 -c "import json;print(json.load(open('/opt/frey/docker/containers/'+\
'$(docker inspect prometheus -f {{.Id}})/config.v2.json'))['HasBeenManuallyStopped'])"
docker start prometheus     # clears the flag as well as starting it
```

### Updating images

`scripts/monitoring-check.sh --updates`, edit `monitoring_versions`, then deploy
with `-e monitoring_update=true`.

cAdvisor is the one to be careful with: it is not on Docker Hub, and `v0.53.0`
and `v0.54.0` were never published at all, so "bump to the next number" is not
safe there. Check the tag exists first.

---

## Logging in

`https://grafana.hub.frey`, with your Frey account. Members of `frey_admins` get
Grafana admin; everyone else is read-only.

Grafana also keeps a **local administrator**, deliberately. If Authelia is down —
one of the things this stack exists to tell you about — OIDC login is down with
it, and that is the worst possible moment for the dashboards showing you why to
be unreachable. The password is generated on the Pi and printed once, on the
first deploy.

Prometheus and Alertmanager have no login of their own at all, so they sit behind
Authelia forward auth, admins only. Alertmanager in particular can silence
alerts — which is to say it can switch off the thing that would tell you
something is wrong.

---

## The dashboards

Five, in the **Frey** folder:

| Dashboard | For |
| --- | --- |
| **Frey Overview** | The one screen. Is the van served, is the Pi healthy, what is shouting |
| **Frey Host & Hardware** | CPU, memory, thermals, power rails, NVMe health, disk trend |
| **Frey Containers & Services** | Per-container state and resources, plus what Traefik sees |
| **Frey Gateway & Network** | Uplink state over time, AP clients, DNS, NAT, throughput |
| **Frey Logs** | Volume by level first, then the log river |

Start at Overview, and on the log dashboard start at the **volume histogram**
rather than the log river — "something started erroring at 03:12" is a shape, not
a line you scroll to.

---

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the modules fit together
- [IDENTITY.md](IDENTITY.md) — why services live at `*.hub.frey`, and how SSO works
- [GATEWAY.md](GATEWAY.md) — the radios, and the deadman rollback
- `roles/monitoring/README.md` — the role's own variables and internals
