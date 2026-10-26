# Frey

Frey is a modular Raspberry Pi Ansible project that runs a self-contained
private network in a van.

**FreyHub** is the access point the Pi broadcasts on `wlan0`. It is the
critical always-on service: it is how you reach Immich, the media stack and
SSH, with or without internet. When a public Wi-Fi network is available, the
Pi joins it on `wlan1` and shares it through to FreyHub clients.

Services are reached by name as `service.frey`, for example `immich.frey`.

Legacy service stacks are archived under `archive/legacy-stack/`.

## Current Layout

```text
playbooks/site.yml                       # Thin module orchestrator
inventory/hosts.yml                      # Target Pi inventory
inventory/group_vars/all/main.yml        # Active module registry and config
inventory/group_vars/all/media.yml       # Media image versions, toggles, VPN switch
inventory/group_vars/all/secrets.yml     # Vault: AP passphrase, known networks
scripts/media-check-updates.sh           # What media images have newer versions
roles/network_gateway/                   # FreyHub AP + public Wi-Fi uplink + NAT/DNS
roles/service_proxy/                     # Docker + Traefik service entrypoint
roles/security_baseline/                 # Firewall, fail2ban, network hardening
roles/rpi_nvme/                          # Pi/NVMe runtime tuning
roles/media_acquisition/                 # *arrs + qBittorrent (needs uplink)
roles/media_library/                     # Jellyfin, Audiobookshelf, Seerr (offline-capable)
docs/                                    # Active architecture docs
archive/legacy-stack/                    # Previous service stack, docs, roles
```

`group_vars/` lives beside `inventory/`, not at the repo root. Ansible only
discovers `group_vars/` next to the inventory or next to the playbook, so a
root-level copy is silently ignored when running `playbooks/site.yml`.

## Hardware Assumptions

| Purpose | Interface | Hardware |
| --- | --- | --- |
| FreyHub access point | `wlan0` | Built-in Broadcom — the reliable radio runs the critical service |
| Public Wi-Fi uplink | `wlan1` | Realtek USB — expendable, external antenna |

There is no Ethernet and no console on this Pi. Both ways in are radios, which
is why changes to the AP radio arm a deadman rollback. See
[docs/GATEWAY.md](docs/GATEWAY.md).

## Secrets

```bash
ansible-vault edit inventory/group_vars/all/secrets.yml --vault-password-file .vault_pass
```

```yaml
vault_freyhub_ap_password: "the FreyHub passphrase"
vault_uplink_networks:
  - ssid: "Campground WiFi"
    password: ""        # empty = open or captive-portal network
    priority: 10
```

Known networks are declared here rather than configured on the device, so a
rebuild from scratch reproduces them. NetworkManager joins whichever is in
range; none in range is a normal state and FreyHub keeps running.

## Deploy

Everything:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --vault-password-file .vault_pass
```

Just the uplink, or just FreyHub:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags uplink --vault-password-file .vault_pass
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags hub --vault-password-file .vault_pass
```

Point at a different address without editing the inventory:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e frey_host=10.20.0.1 --vault-password-file .vault_pass
```

Dry run:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --check --diff --vault-password-file .vault_pass
```

**First-time setup on a Pi whose SSH arrives on `wlan0` needs the two-phase
migration in [docs/GATEWAY.md](docs/GATEWAY.md).** The role will refuse to
convert the radio carrying your session into an access point.

## Storage

The Pi boots from the SD card out of the box. To move the whole install to the
4TB NVMe so the card can be removed, see
[docs/NVME_MIGRATION.md](docs/NVME_MIGRATION.md). Do it **before** deploying
services: cloning a live root filesystem is safe on a fresh install, not once
databases are running.

`roles/rpi_nvme/` only *tunes* an NVMe-backed system; the migration is a
separate playbook.

## Local Services

FreyHub's DNS resolves `frey` and any `*.frey` name to the Pi, answered
locally so it works with no internet. Traefik then routes hostnames to Docker
containers by label — new services need no DNS change.

For a new service such as Immich:

- Join the Docker network `frey_proxy`.
- Add a router rule like ``Host(`immich.frey`)``.
- Set the container port with `traefik.http.services.<name>.loadbalancer.server.port`.

See [docs/SERVICE_MODULES.md](docs/SERVICE_MODULES.md).

## Media

The media stack is split in two along the line that matters in a van:

- `media_library` — Jellyfin (`jellyfin.frey`), Audiobookshelf
  (`audiobookshelf.frey`, also `books.frey`) and Seerr (`seerr.frey`, also
  `requests.frey`). Works with **no internet at all**.
- `media_acquisition` — Prowlarr, Sonarr, Radarr, Lidarr, Chaptarr, Bazarr and
  qBittorrent. Needs an uplink, and pauses itself when there isn't one.

Downloads and the library share a single `/opt/frey/data` tree so imports are
hardlinks rather than copies, and downloading pauses automatically when the
uplink is unusable — including behind a captive portal, which looks online to
an application but is not.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags media --vault-password-file .vault_pass
```

Everything you change day to day lives in one file,
`inventory/group_vars/all/media.yml`: image versions, which services run, and
the VPN toggle. To see what is out of date before editing it:

```bash
scripts/media-check-updates.sh
```

Setting `media_vpn.enabled: true` there (with credentials in the vault) moves
qBittorrent inside a Gluetun tunnel with a killswitch, and repoints the rest
of the stack at it automatically.

See [docs/MEDIA.md](docs/MEDIA.md). Note that the Pi 5 has no hardware video
encoder, so the quality profiles deliberately chase direct play rather than
relying on transcoding.

## Add A Module

1. Create `roles/<module_name>/`.
2. Put role defaults in `roles/<module_name>/defaults/main.yml`.
3. Add the module to `frey.modules.available` in `inventory/group_vars/all/main.yml`.
4. Add the module name to `frey.modules.enabled`.

See [docs/ADDING_MODULES.md](docs/ADDING_MODULES.md).
