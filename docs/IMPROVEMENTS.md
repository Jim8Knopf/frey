# Improvement Suggestions

## Done

- FreyHub access point on the built-in radio, with the uplink on USB.
- Deadman rollback for AP-radio changes (no Ethernet, no console on this Pi).
- Captive-portal-safe DNS, and an AP that serves clients with no uplink at all.
- Media stack, split into `media_library` (offline-capable) and
  `media_acquisition` (needs uplink), with downloads gated on real uplink
  state. See [MEDIA.md](MEDIA.md).

- Single sign-on: LLDAP + Authelia, replacing the archived Authentik stack.
  One templated YAML file instead of 947 lines of blueprint-reapply machinery
  and five Django ORM scripts. Validated with `authelia validate-config` before
  anything restarts, and a second run reports zero changes.
- A private CA with a self-renewing certificate, replacing step-ca and ACME.
  No extra container and nothing that needs an uplink.

- Monitoring that can actually warn you: Prometheus, Loki, Grafana, and a
  notification relay that holds alerts on disk while the van has no uplink and
  delivers them with a "while you were offline" report. The archived monitoring
  role had the dashboards and thirty alert rules but no Alertmanager and no
  receiver, so every rule fired into a void. See [MONITORING.md](MONITORING.md).

  It also covers the things no off-the-shelf exporter does: under-voltage and
  throttling, PMIC power rails, NVMe wear and unsafe shutdowns, AP clients,
  DHCP leases, DNS actually answering, NAT rules present - and a blackbox probe
  of every service through Traefik, which is what catches a healthy container
  behind a dropped router.

## Near Term

- Template the Jellyfin SSO plugin's configuration XML, once the plugin has
  proven itself on Jellyfin 12.3 and its schema can be read off an installed
  copy rather than guessed. Until then it stays a documented manual step.
- Configure Audiobookshelf OIDC automatically if upstream ever grows an API or
  environment variable for it. Today the web UI is the only way.
- Force HTTPS everywhere (`service_proxy.traefik.redirect_http_to_https`) once
  every client device trusts the Frey CA. Blocked on televisions, which cannot
  install a private root certificate.
- Add a `base_system` module for hostname, timezone, package updates, SSH hardening, and common users.
- ~~Add a `healthcheck` module that verifies upstream Wi-Fi, DHCP leases, DNS
  resolution, and NAT.~~ Done, as part of `monitoring` rather than as a module
  of its own: the gateway host collector reports all four continuously as
  metrics, with alerts, instead of as a one-shot check. `scripts/monitoring-check.sh`
  is the on-demand form.
- **Add a `backup` module.** Now overdue rather than merely desirable: the
  media stack has put *arr SQLite databases and Jellyfin metadata on the Pi,
  and those need a consistent dump, not a tar of a live file. Immich will make
  this worse.
- Add a `service_template` scaffold script for quickly creating new Docker/Traefik modules.
- **An MQTT broker, when the first sensor that is not wired to the Pi arrives.**
  Cabin temperature on the Pi's own 1-Wire bus needs nothing new - it drops a
  `.prom` file into `/opt/frey/metrics/textfile/` and is monitored on the same
  terms as CPU temperature. A battery monitor, a Zigbee thermometer or an ESP32
  node is the point at which a broker plus an MQTT-to-Prometheus bridge beats a
  script per device. Nothing in `monitoring` has to change to allow it.
- Remote access to the dashboards, if being told by ntfy ever stops being
  enough. Tailscale is the one to reach for: it works through campground NAT
  with no ports opened, and it would also be a second way into the Pi - which
  matters on a machine with no Ethernet and no console. Deliberately not done
  now; today nothing but an outbound notification leaves the van.
- **Add forward authentication** in front of the *arr UIs. They currently have
  no authentication on the FreyHub LAN, with the AP passphrase as the only
  boundary. Servarr auth is already set to `External`, which is exactly what a
  Traefik forward-auth middleware needs, so this is additive.
- Seed Seerr's first run once its settings schema is pinned to a known
  version. Left manual today because a malformed settings file stops the
  container from starting outright.

## Service Module Pattern

- Use one role per service or tightly coupled stack.
- Put Docker Compose services under a service module, not in the global playbook.
- Use module-owned variables in `roles/<module>/defaults/main.yml`.
- Expose only high-level toggles in `inventory/group_vars/all/main.yml`.

## Network Enhancements

- Add a captive-portal helper that surfaces the portal URL. `nmcli networking connectivity`
  already reports `portal`; sign-in itself is done from a FreyHub client, whose
  traffic is NATed behind the Pi, so authenticating there authorises the whole hub.
- Add optional Ethernet uplink mode (`downstream.mode: ethernet` already exists as a hook)
  for places where wired internet is available.
- Add local HTTPS with a Frey root CA once client trust installation is planned.

## Validation

- Add Molecule or lightweight Ansible check-mode tests for each module.
- Add a gateway verification script for `nmcli`, `dnsmasq`, DHCP leases, routes, and NAT rules.
- Add a preflight command that fails fast if `wlan0` or `wlan1` are missing.
