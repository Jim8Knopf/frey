# Improvement Suggestions

## Done

- FreyHub access point on the built-in radio, with the uplink on USB.
- Deadman rollback for AP-radio changes (no Ethernet, no console on this Pi).
- Captive-portal-safe DNS, and an AP that serves clients with no uplink at all.
- Media stack, split into `media_library` (offline-capable) and
  `media_acquisition` (needs uplink), with downloads gated on real uplink
  state. See [MEDIA.md](MEDIA.md).

## Near Term

- Add a `base_system` module for hostname, timezone, package updates, SSH hardening, and common users.
- Add a `healthcheck` module that verifies upstream Wi-Fi, DHCP leases, DNS resolution, and NAT.
- **Add a `backup` module.** Now overdue rather than merely desirable: the
  media stack has put *arr SQLite databases and Jellyfin metadata on the Pi,
  and those need a consistent dump, not a tar of a live file. Immich will make
  this worse.
- Add a `service_template` scaffold script for quickly creating new Docker/Traefik modules.
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
