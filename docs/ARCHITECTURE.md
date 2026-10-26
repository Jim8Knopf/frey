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

## Security

`security_baseline` applies a default-deny firewall, allows required downstream LAN ports, preserves the current Ansible SSH path, enables fail2ban for SSH, and keeps services bound to the private Frey address.

## Pi/NVMe Tuning

`rpi_nvme` enables trim, limits journal growth, and applies conservative VM tuning. Docker data is stored under `/opt/frey/docker` by `service_proxy`, which should live on the M.2/NVMe-backed filesystem.

## Archive

The previous Docker-heavy stack lives under `archive/legacy-stack/`. It is not in the active role path and will not deploy unless explicitly moved back or referenced.

The previous encrypted service vault is archived at `archive/legacy-stack/group_vars/all/secrets.yml`. The active tree intentionally has no default `inventory/group_vars/all/secrets.yml`; create one only for new gateway secrets.
