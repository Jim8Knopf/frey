# media_acquisition

Indexer search, downloading and import: Prowlarr, Sonarr, Radarr, Lidarr,
Chaptarr, Bazarr, qBittorrent, Byparr, Recyclarr, Cleanuparr and Unpackerr.

This is the half of the media stack that needs internet. It is a separate
module from [`media_library`](../media_library/README.md) so it can be paused,
stopped or disabled without touching playback — which is what you want when
the van is parked somewhere with no uplink.

## What It Does

- Creates the single `/data` tree that makes imports hardlinks rather than copies.
- Deploys the stack with no published host ports; every UI is reached through Traefik.
- Seeds each app's API key *before* first start, then wires the services to
  each other over their REST APIs.
- Keeps TRaSH-guide quality profiles in sync through Recyclarr.
- Pauses downloading when the uplink is unusable, including behind a captive portal.

## Required Variables

Day-to-day knobs live in **`inventory/group_vars/all/media.yml`**:
`media_versions` (image tags), `media_enable` (which services run) and
`media_vpn` (the tunnel). You should not need to edit this role to run the
stack.

Shared values come from `media` in `inventory/group_vars/all/main.yml`:
`data_dir`, `appdata_dir`, `user.{name,uid,gid}`, `umask`, `languages`,
`network.{name,subnet}`. Structure lives in `defaults/main.yml`.

Nothing has to be put in the vault. API keys and the qBittorrent password are
generated on first deploy and persisted at `/opt/frey/appdata/.media-keys.json`
(mode 0600). Define `vault_media_api_keys` if you would rather pin them so a
rebuild reproduces the same values:

```yaml
vault_media_api_keys:
  sonarr: "32 hex characters"
  radarr: "32 hex characters"
  qbittorrent_password: "something you choose"
```

## Service Hostnames

| Service | URL | Purpose |
| --- | --- | --- |
| Prowlarr | `http://prowlarr.frey` | Indexers — add them here only |
| Sonarr | `http://sonarr.frey` | TV |
| Radarr | `http://radarr.frey` | Movies |
| Lidarr | `http://lidarr.frey` | Music |
| Chaptarr | `http://chaptarr.frey` | Audiobooks and ebooks |
| Bazarr | `http://bazarr.frey` | Subtitles |
| qBittorrent | `http://qbittorrent.frey` | Torrent client |
| Cleanuparr | `http://cleanuparr.frey` | Stuck-download cleanup |

Byparr, Recyclarr and Unpackerr have no web UI and are not routed.

## How The Wiring Works

Ansible reaches the containers **through Traefik with an explicit `Host`
header**, not by hostname:

```bash
curl -H "Host: sonarr.frey" http://10.20.0.1/api/v3/system/status
```

That is the only path that works regardless of how the Pi's own resolver is
configured: dnsmasq answers `*.frey` for FreyHub clients, but the Pi itself is
a separate question, container IPs change, and nothing here publishes a host
port.

Every wiring step reads the current state before writing, so re-running is a
no-op:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags media_config --vault-password-file .vault_pass
```

Prowlarr is registered *with* each *arr as an "application" at `fullSync`, so
indexers added in Prowlarr propagate everywhere. Add an indexer once.

## Download Gating

`/usr/local/bin/frey-media-gate` matches downloading to the uplink's real
state. A NetworkManager dispatcher hook fires it on interface events, and a
10-minute timer catches transitions that produce no event — notably a captive
portal you sign into from a phone, which flips the Pi's connectivity verdict
without any interface changing.

```bash
frey-media-gate status     # what it thinks right now
frey-media-gate pause      # force a pause
frey-media-gate resume     # force a resume
```

`nmcli` reporting `portal` counts as **not** usable. That is the point: a
captive portal looks online to an application, and left alone the *arrs will
burn through search attempts against a sign-in page and collect indexer bans.

Modes are set by `media_acquisition.uplink_gating.mode`: `pause` (default),
`stop` (also stops the *arr containers after a grace period, to save power
off-grid), or `off`.

## Validation

```bash
# Containers up and healthy
docker compose -f /opt/frey/stacks/media_acquisition/docker-compose.yml ps

# The hardlink contract: these must be the same filesystem
findmnt --target /opt/frey/data/torrents
findmnt --target /opt/frey/data/media

# Prove a hardlink actually happened after an import (link count > 1)
find /opt/frey/data/media -type f -links +1 | head

# Gating
frey-media-gate status
systemctl status frey-media-gate.timer

# Reach a UI the same way Ansible does
curl -sS -H "Host: prowlarr.frey" http://10.20.0.1/api/v1/health \
  -H "X-Api-Key: $(jq -r .prowlarr /opt/frey/appdata/.media-keys.json)"
```

## Deliberate Choices

**VPN off by default, one switch to change it.** Torrent traffic goes out over
whatever network the van is parked on and is attributable to it. That was an
explicit decision, not an oversight.

To change it, set `media_vpn.enabled: true` in
`inventory/group_vars/all/media.yml` and put the credentials in the vault.
qBittorrent then runs inside Gluetun's network namespace
(`network_mode: service:gluetun`), so if the tunnel drops its firewall stops
traffic rather than falling back to the venue's network — a SOCKS proxy would
fail open instead. Ansible repoints the *arrs at `gluetun`, Traefik serves the
UI from there, and `qbittorrent.frey` is unchanged.

Enabling it with no credentials fails the deploy immediately with
instructions, rather than starting an unconfigured tunnel that looks like a
broken stack.

**No published ports, including the torrent listen port.** Behind a venue's
NAT there is no inbound path to forward, so publishing it would open the
uplink side for nothing. Outbound peer connections work regardless.

**Auth is `External`.** Servarr local users cannot be seeded without writing
the app's database, so the *arr UIs are open to anyone on the FreyHub LAN and
the AP passphrase is today's boundary. `External` is also exactly the right
setting for the planned auth module: put Traefik forward-auth in front and
nothing here changes.

**Images are pinned to concrete versions**, all of them in
`inventory/group_vars/all/media.yml`. An unattended pull on a campground Wi-Fi
must not be able to hand you a broken stack with no internet left to fix it
with. `scripts/media-check-updates.sh` reports what has moved upstream. Bump
deliberately:

```bash
# Re-pull the pinned tags and recreate what moved, while you still have a
# connection. Needs the explicit flag: a plain deploy never pulls.
ansible-playbook ... --tags media_update -e media_update=true
```

## Known Gaps

- **German release scoring** is not configured. The language *profiles* are
  set, but boosting German releases needs TRaSH custom formats referenced by
  `trash_id`, and those IDs are not guessed at in
  `templates/recyclarr.yml.j2`. Instructions are in that file.
- **Bazarr subtitle providers and language profiles** live in its database,
  not its config file, so they are a one-time UI step.
- **Indexers** need your own tracker credentials and are added in Prowlarr.
- **Lidarr** depends on an upstream metadata server that has been unreliable
  through 2026; adding artists and imports break periodically. Not a
  configuration problem.
