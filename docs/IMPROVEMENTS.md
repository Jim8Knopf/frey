# Improvement Suggestions

## Done

- FreyHub access point on the built-in radio, with the uplink on USB.
- Deadman rollback for AP-radio changes (no Ethernet, no console on this Pi).
- Captive-portal-safe DNS, and an AP that serves clients with no uplink at all.

## Near Term

- Add a `base_system` module for hostname, timezone, package updates, SSH hardening, and common users.
- Add a `healthcheck` module that verifies upstream Wi-Fi, DHCP leases, DNS resolution, and NAT.
- Add a `backup` module before reintroducing data-heavy services such as Immich.
- Add a `service_template` scaffold script for quickly creating new Docker/Traefik modules.

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
