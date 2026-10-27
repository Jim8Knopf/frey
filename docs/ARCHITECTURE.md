# Architecture

The new Frey layout separates the active deployment from archived services.

## Active Deployment

`playbooks/site.yml` is a thin orchestrator. It does not know service details. It reads `frey.modules.enabled` and includes the registered role for each module.

```yaml
frey:
  modules:
    enabled:
      - network_gateway
    available:
      network_gateway:
        role: network_gateway
        tags: [network, gateway]
      service_proxy:
        role: service_proxy
        tags: [services, proxy, docker]
```

## Baseline Network

The first module is `network_gateway`:

- FreyHub: `wlan0` runs the access point on `10.20.0.1/24`. Built-in Broadcom
  radio, because clients depend on this and it is the critical always-on service.
- Uplink: `wlan1` joins public Wi-Fi opportunistically via NetworkManager.
  USB Realtek radio, because losing it costs internet and never FreyHub.
- DHCP/DNS: `dnsmasq` listens only on the AP interface, using `bind-dynamic` so
  it survives the radio appearing late.
- Local service DNS: `frey` and `*.frey` resolve to `10.20.0.1`, answered
  locally and therefore offline-safe.
- NAT: `iptables` masquerades `10.20.0.0/24` through the uplink when one exists.

The AP must serve clients fully with no uplink present. Nothing below the Pi
depends on internet being available.

## Service Access

`service_proxy` runs Traefik on `10.20.0.1:80` and `10.20.0.1:443`. Docker services are discovered through labels. DNS does not need one record per service because `*.frey` is a local wildcard.

This means adding `immich.frey` is a service-module concern, not a DNS-module concern.

## Identity

`frey_pki` issues the Frey CA and the certificate Traefik serves. `identity`
runs LLDAP (the directory) and Authelia (the login page and OIDC provider).

Services live at `<name>.hub.frey`, not `<name>.frey`. That extra label is
load-bearing: Authelia's session cookie must be scoped to a domain containing a
period, and under the Public Suffix List's default rule a bare unknown TLD is
itself a public suffix, so no cookie can span `*.frey`. The old names still
resolve and redirect.

A service gets single sign-on one of two ways:

- `forward_auth` — a Traefik middleware. Nothing in the service changes.
- `oidc` — the service logs in against Authelia itself.

Both are chosen per service in `inventory/group_vars/all/identity.yml`, and the
media modules read one derived list (`identity_protect`) rather than reaching
into the identity role. That keeps them deployable with identity switched off.

Module order matters: `frey_pki` before `identity` before the service modules.
Traefik drops a router that names a middleware it does not know about, so a
service whose labels reference `authelia@file` before the identity module has
installed it 404s with a perfectly healthy container.

## Security

`security_baseline` applies a default-deny firewall, allows required downstream LAN ports, preserves the current Ansible SSH path, enables fail2ban for SSH, and keeps services bound to the private Frey address.

Worth knowing, because it shapes the monitoring module: the firewall's allow
rules are scoped to an interface (`on wlan0`, `on wlan1`), and INPUT is
default-deny. A packet from a Docker bridge to the host therefore does not match
any allow rule and is dropped. That is why nothing in `monitoring` reaches the
host by address - no host-networked exporter, and no probe of
`https://10.20.0.1`. Everything is container-to-container.

## Monitoring

`monitoring` runs last, and the order is load-bearing: it reads the Grafana OIDC
client secret that `identity` generates, and it derives what to probe from
`identity_services`, so a service added to the auth matrix is monitored with no
second edit.

Four layers, independently switchable: metrics (Prometheus, node-exporter,
cAdvisor, blackbox), alerting (Alertmanager plus a notification relay), logs
(Loki and Alloy), and Grafana - which is purely a viewer, so turning it off
loses no data and stops no alert.

The relay is the part the van makes necessary. Alertmanager drops a notification
it cannot deliver, so the relay holds undelivered alerts on disk with the time
they really fired and flushes them with a summary when an uplink appears.

Everything the Pi knows about itself but no exporter reports - throttling,
under-voltage, PMIC power, NVMe SMART, AP clients, DHCP leases, DNS, NAT,
container state - arrives through node-exporter's textfile directory, written by
a systemd timer on the host. That directory is also the seam for the van's
future sensors.

See [MONITORING.md](MONITORING.md).

## Pi/NVMe Tuning

`rpi_nvme` enables trim, limits journal growth, and applies conservative VM tuning. Docker data is stored under `/opt/frey/docker` by `service_proxy`, which should live on the M.2/NVMe-backed filesystem.

## Archive

The previous Docker-heavy stack lives under `archive/legacy-stack/`. It is not in the active role path and will not deploy unless explicitly moved back or referenced.

The previous encrypted service vault is archived at `archive/legacy-stack/group_vars/all/secrets.yml`. The active tree intentionally has no default `inventory/group_vars/all/secrets.yml`; create one only for new gateway secrets.
