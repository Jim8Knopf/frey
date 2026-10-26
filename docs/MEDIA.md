# Media Stack

Two modules, split along the line that actually matters in a van: whether a
service needs the internet.

| Module | Services | Needs uplink |
| --- | --- | --- |
| `media_library` | Jellyfin, Audiobookshelf, Seerr, AudioBookRequest, Maintainerr, Jellystat | No |
| `media_acquisition` | Prowlarr, Sonarr, Radarr, Lidarr, Chaptarr, Bazarr, qBittorrent, Byparr, Recyclarr, Cleanuparr, Unpackerr | Yes |

Parked off-grid, `media_library` alone gives a working library. Disable
`media_acquisition` in `frey.modules.enabled` and nothing about playback
changes.

`media_acquisition` is ordered **before** `media_library` in the module list,
because it generates the *arr API keys the library module needs to wire Seerr
in the same run.

## Deploy

```bash
# Everything
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags media --vault-password-file .vault_pass

# One half
ansible-playbook ... --tags media_library
ansible-playbook ... --tags media_acquisition

# Just re-apply the wiring between services (idempotent, safe any time)
ansible-playbook ... --tags media_config

# Just the download gating
ansible-playbook ... --tags media_gating
```

## Storage: One Tree

```text
/opt/frey/data/
├── torrents/          # qBittorrent save paths, by category
│   ├── movies/        # category: radarr
│   ├── tv/            # category: tv-sonarr
│   ├── music/         # category: lidarr
│   ├── audiobooks/    # category: chaptarr
│   └── ebooks/
└── media/             # the library
    ├── movies/
    ├── tv/
    ├── music/
    ├── audiobooks/
    ├── podcasts/
    └── ebooks/
```

Every *arr and qBittorrent mount this whole tree at `/data`. One mount point,
one filesystem, so an import is a **hardlink**: the torrent keeps seeding from
`/data/torrents` while the library points at the same bytes under
`/data/media`. One copy on disk.

The archived role mounted `/downloads`, `/tv` and `/movies` separately. Across
mount boundaries Docker cannot hardlink, so every import was a full copy —
double the disk, and a lot of pointless writes on the NVMe that also holds the
databases.

Verify it is working:

```bash
# Same source device for both — required
findmnt --target /opt/frey/data/torrents
findmnt --target /opt/frey/data/media

# After an import, link count > 1 proves a hardlink
find /opt/frey/data/media -type f -links +1 | head
```

## Networking

```text
FreyHub client ──► 10.20.0.1:80 ──► Traefik ──► container (frey_proxy)
                                                     │
                                                     └── frey_media
                                                         app-to-app only
```

- **No published host ports.** The firewall opens only 22/53/80/443
  downstream, so the archived stack's dozen port mappings were unreachable
  from FreyHub anyway, while still being exposed on the uplink side.
- **`frey_media` is pinned to `172.28.0.0/16`.** It must never overlap
  FreyHub's `10.20.0.0/24`. The archived role put this network on exactly that
  subnet, which would have taken down the one service that must always
  survive. Both roles now assert against it.
- **No DNS changes.** `*.frey` is already a local wildcard, so a new service
  only needs Traefik labels.

## How Ansible Talks To The Containers

Through Traefik, with an explicit `Host` header:

```bash
curl -H "Host: sonarr.frey" http://10.20.0.1/api/v3/system/status
```

Not by hostname — dnsmasq answers `*.frey` for FreyHub clients, but the Pi's
own resolver is a separate matter. Not by container IP — those change. Not by
published port — there are none. The `Host` header works regardless.

## Secrets

Generated on first deploy and persisted at `/opt/frey/appdata/.media-keys.json`
(mode 0600). Nothing needs to be put in the vault for the stack to come up
fully wired.

```bash
sudo jq . /opt/frey/appdata/.media-keys.json
```

A rebuild from scratch generates fresh keys, which is harmless because the
same run re-applies every connection that uses them. To make them reproducible
from the repo instead, set `vault_media_api_keys` in
`inventory/group_vars/all/secrets.yml`; vault values always win.

## What Is Wired Automatically

| From | To | What |
| --- | --- | --- |
| Prowlarr | Sonarr, Radarr, Lidarr, Chaptarr | Registered as applications at `fullSync` — indexers propagate |
| Prowlarr | Byparr | Cloudflare solver, applied to `cloudflare`-tagged indexers |
| Sonarr, Radarr, Lidarr, Chaptarr | qBittorrent | Download client with the right category |
| Sonarr, Radarr, Lidarr, Chaptarr | — | Root folders under `/data/media` |
| Bazarr | Sonarr, Radarr | Templated `config.yaml` |
| Recyclarr | Sonarr, Radarr | TRaSH quality profiles and custom formats, nightly |
| Unpackerr | Sonarr, Radarr, Lidarr | Archive extraction |
| Jellyfin | — | First-run wizard and three libraries (best effort — see below) |

## First-Run Steps That Are Not Automated

Four things, by design rather than omission. The deploy prints the values you
need for each.

1. **Prowlarr indexers.** They need your own tracker credentials. Add them at
   `http://prowlarr.frey` and they propagate to every *arr automatically.
2. **Seerr setup** at `http://requests.frey`. Point it at
   `http://jellyfin:8096`, then add Sonarr (`http://sonarr:8989`) and Radarr
   (`http://radarr:7878`) with the API keys from the secret file. Not
   automated because Seerr's settings JSON changes schema between versions and
   a malformed seed stops the container from starting outright.
3. **Bazarr providers and language profiles** at `http://bazarr.frey`. These
   live in Bazarr's database, not its config file, so Ansible cannot seed
   them. Attach a `de`/`en` profile.
4. **German release scoring.** Language profiles are set, but boosting German
   releases needs TRaSH custom formats referenced by `trash_id`. Those IDs are
   not guessed at — see the instructions in
   `roles/media_acquisition/templates/recyclarr.yml.j2`.

`tasks/configure.yml` in `media_library` also completes Jellyfin's wizard, but
best-effort: Jellyfin 12 reworked authentication and that path is not verified
against a live 12.x server. If it does not take, finish it in a browser.

## Download Gating

Public Wi-Fi comes and goes, and captive portals are worse than being offline:
they answer every request with a sign-in page, which to an application looks
like a working connection. Left alone the *arrs burn through search attempts
against that and collect indexer rate-limit bans.

`frey-media-gate` watches the uplink and reacts. `nmcli` reporting `portal`
counts as **not** usable — that distinction is the whole point.

```bash
frey-media-gate status
```

A NetworkManager dispatcher hook fires on interface events; a 10-minute timer
catches transitions that produce no event, such as signing into a portal from
a phone on FreyHub, which flips the Pi's verdict without any interface
changing state.

Modes (`media_acquisition.uplink_gating.mode`):

| Mode | Behaviour |
| --- | --- |
| `pause` | Pause qBittorrent; throttle on metered links. Default. |
| `stop` | Also stop the *arr containers after a grace period, to save power. |
| `off` | No gating. |

## Why These Images

The archived stack used `latest` for everything, which on a campground Wi-Fi
means an unattended pull can hand you a broken stack with no internet left to
fix it. Every image is now pinned, and bumped deliberately with
`--tags media_update -e media_update=true`.

Three replacements since that stack was written:

| Was | Now | Why |
| --- | --- | --- |
| Jellyseerr | **Seerr** `v3.5.1` | Jellyseerr is discontinued; Overseerr and Jellyseerr merged upstream into Seerr. Its Jellyfin auth also breaks on Jellyfin 12. |
| FlareSolverr | **Byparr** `2.0.1` | FlareSolverr is archived upstream and no longer clears the Cloudflare challenges trackers use. Byparr is a drop-in for its API. |
| Jellyfin 10.x | **Jellyfin 12.3** | Major version jump. See `roles/media_library/README.md` for the breaking changes. |

Also added: **Chaptarr** for audiobooks and ebooks, the maintained successor
to Readarr, which was retired in June 2025 when its metadata sources became
unusable.

Dropped: Mopidy (no arm64 image), NZBGet and SABnzbd (no Usenet), the custom
`audiobook_bridge` container (it ran `apt-get install mpv` as its start
command, so it needed internet on every container start — exactly what a van
does not have).

## Resource Budget

16 GB Pi 5. Limits, not reservations:

| Group | Cap |
| --- | --- |
| `media_library` | ~5 GB (Jellyfin 2 GB, the rest 0.5 GB each) |
| `media_acquisition` | ~7 GB (qBittorrent and Byparr 1 GB each, *arrs 0.75 GB) |

Every container is capped and most have a `pids_limit`. FreyHub and SSH are
the only ways into this machine, so nothing in the media stack may OOM the Pi
or starve the gateway. Byparr gets the tightest watch: it drives a real
browser engine and is the most likely to balloon.

## Known Risks

- **Torrenting without a VPN.** Traffic is attributable to whatever network
  the van is parked on, and notices go to the venue. This was a deliberate
  choice; `media_acquisition.vpn.enabled` is the hook for Gluetun if it
  changes.
- **The *arr UIs have no authentication** on the FreyHub LAN. The AP
  passphrase is the boundary today. Servarr local users cannot be seeded
  without writing the app's database, so auth is set to `External` — which is
  also exactly what the planned forward-auth module needs.
- **No HTTPS.** Everything is plain `http://`. Some mobile apps require TLS.
- **No backups yet.** `docs/IMPROVEMENTS.md` calls for a backup module before
  data-heavy services; the *arr SQLite databases need a consistent dump, not a
  tar of a live file.
- **Lidarr's metadata server** has been unreliable through 2026. Upstream, not
  configuration.
