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

## The File You Edit

`inventory/group_vars/all/media.yml` holds service settings. Image tags for all
services are in `inventory/group_vars/all/images.yml`:

| Block | What it controls |
| --- | --- |
| `media_versions` in `images.yml` | media image tags |
| `media_enable` | which services run |
| `media_vpn` | the VPN toggle and its credentials |

Structure — volumes, networks, Traefik labels, API wiring — stays in the two
roles. You should not need to open them to run the stack.

### Updating images

```bash
scripts/media-check-updates.sh      # what has moved upstream
# edit inventory/group_vars/all/images.yml
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags media --vault-password-file .vault_pass
```

The script skips linuxserver's `-lsNNN` build suffix and treats a short pin
like `"1"` as deliberately tracking a major line, so it only reports real
moves. It compares against each project's latest **release**, and a few
projects tag releases differently from their published images — Maintainerr
currently publishes a v3 release with no v3 image — so check a tag exists
before applying it:

```bash
docker manifest inspect ghcr.io/jorenn92/maintainerr:3.31.0
```

### Turning the VPN on

1. Put the credentials in the vault:

   ```bash
   ansible-vault edit inventory/group_vars/all/secrets.yml \
     --vault-password-file .vault_pass
   ```

   ```yaml
   vault_vpn_wireguard_private_key: "..."
   vault_vpn_wireguard_addresses: "10.2.0.2/32"
   ```

2. Set `media_vpn.enabled: true` (and `provider`/`type`) in
   `inventory/group_vars/all/media.yml`.
3. Re-deploy: `--tags media_acquisition`.

qBittorrent then runs **inside** Gluetun's network namespace
(`network_mode: service:gluetun`), so every tracker, peer and DHT packet
leaves through the tunnel and nothing else. If the tunnel drops, Gluetun's
firewall blocks the lot rather than falling back to the venue's network:
downloads stop instead of leaking. A SOCKS proxy would fail open instead.

What Ansible changes for you:

- Traefik serves the qBittorrent UI from the Gluetun container, so
  `qbittorrent.frey` keeps working unchanged.
- The *arrs are repointed at `gluetun` as their download-client host, since
  qBittorrent no longer has a hostname of its own.
- `FIREWALL_OUTBOUND_SUBNETS` is set to the Docker networks plus the FreyHub
  LAN. Without that the killswitch blocks Traefik and the *arrs too, and the
  UI vanishes along with the leaks.

Enabling it without credentials fails the deploy immediately with
instructions, rather than starting an unconfigured tunnel that looks like a
broken stack.

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
| AudioBookRequest | Prowlarr → qBittorrent → Audiobookshelf | Direct requests use the `audiobookrequest` category. A five-minute timer hardlinks completed audio into the Audiobookshelf `Requests` folder; the torrent remains available for seeding. |
| Prowlarr | Byparr | Cloudflare solver, applied to `cloudflare`-tagged indexers |
| Sonarr, Radarr, Lidarr, Chaptarr | qBittorrent | Download client with the right category |
| Sonarr, Radarr, Lidarr, Chaptarr | — | Root folders under `/data/media` |
| Bazarr | Sonarr, Radarr | Templated `config.yaml` |
| Ansible | Sonarr, Radarr | Language custom formats and their scores, on every quality profile |
| Recyclarr | Sonarr, Radarr | TRaSH quality profiles and custom formats, nightly — *when it can reach the guides* |
| Unpackerr | Sonarr, Radarr, Lidarr | Archive extraction |

For audiobook requests, select `de` or an English region in the search form.
Automatic source ranking does not guarantee the spoken language: inspect the
source before choosing a download when an exact edition matters. The importer
only accepts completed, selected audio files and common cover/metadata files;
it does not unpack archives. Check `journalctl -u frey-audiobook-import.service`
if a completed request does not appear. An indexer can only find titles and
languages currently available from its sources.

## First-Run Steps That Are Not Automated

Five things. The deploy prints the values you need for each.

1. **Jellyfin's setup wizard** at `http://jellyfin.frey`, then its three
   libraries (`/data/media/movies`, `/data/media/tv`, `/data/media/music`).
   Not automated because Jellyfin 12.3's `/Startup/User` endpoint does not
   create the administrator, and completing the wizard without one leaves a
   server nobody can log into. See `roles/media_library/README.md`.
2. **Additional Prowlarr indexers.** Knaben is added as a public search source
   when `media_audiobook_public_indexer` is true; private sources may need your
   own tracker credentials. Add those at
   `http://prowlarr.frey` and they propagate to every *arr automatically.
3. **Seerr setup** at `http://seerr.frey`. Point it at
   `http://jellyfin:8096`, then add Sonarr (`http://sonarr:8989`) and Radarr
   (`http://radarr:7878`) with the API keys from the secret file. Not
   automated because Seerr's settings JSON changes schema between versions and
   a malformed seed stops the container from starting outright.
4. **Bazarr providers and language profiles** at `http://bazarr.frey`. These
   live in Bazarr's database, not its config file, so Ansible cannot seed
   them. Attach an `en` then `de` profile — it is what makes the last-resort
   grab in neither language watchable.
5. **Jellyfin's audio track**, per user, under Settings > Playback: preferred
   audio language English, and untick *Play default audio track regardless of
   language*. Jellyfin keeps this per user rather than server-wide, so Ansible
   cannot set it. Without it a dual-audio release plays whichever track it
   tagged default — which is how an English grab ends up playing Italian.

`media_library` also carries code to complete Jellyfin's wizard over the API,
disabled by default for the reason above.

## Spoken Language

**English first, German if there is no English, and anything else only when
there is neither** — with the anything-else copy replaced automatically once
an English release appears. Parked off-grid, a watchable Italian copy now
beats an English copy in three weeks.

Which languages: `media.languages` in `inventory/group_vars/all/main.yml`.
How strict: `media_language_require_one` in
`inventory/group_vars/all/media.yml` — `false` (default) keeps the last-resort
grab, `true` rejects it and leaves the episode missing until English or German
exists.

| release | score | outcome |
| --- | --- | --- |
| English | 500 | grabbed first |
| German | 300 | grabbed when there is no English |
| German **and** English | 800 | best case; both formats match |
| neither | 0 | allowed, ranked last, upgraded away later |

Applied by `roles/media_acquisition/tasks/configure/languages.yml` as one
custom format per language, scored on **every** quality profile — because
Seerr, the UI and the request bots each use whichever profile they were
pointed at, and a policy on one profile out of six is a policy that silently
does not apply.

Three traps this avoids:

- **A negative score plus a minimum of `0`** rejects the fallback instead of
  ranking it last, and the symptom is a stack that downloads nothing and
  reports no error. Nothing here scores below zero.
- **Radarr's profile `language` field is a hard filter.** On its default
  `Original` it rejects an English dub of a foreign film outright, before any
  score is considered. The task sets it to `Any`. Sonarr 4 has no such field
  at all — language profiles were removed, and scoring is the only mechanism
  left.
- **Recyclarr cannot own this.** It has to fetch the TRaSH Guides over the
  uplink first, and a failed fetch makes it exit rather than apply the rest:

  ```
  [WRN] All references failed to fetch: Could not resolve host
  [ERR] Exiting due to fatal error
  ```

  That is what its 04:00 run had been doing every night — which is why Sonarr
  and Radarr had zero custom formats and no language preference whatsoever,
  while `media.languages` sat in `group_vars` looking authoritative. Anything
  that must hold with the uplink down belongs in the Ansible path.

If Recyclarr ever does succeed and resets a profile's custom format scores,
re-run `--tags media_config` to put them back.

Audio *playback* is separate: see step 5 of the first-run steps above. The
*arrs choose the file; Jellyfin chooses the track inside it.

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

When the uplink returns, the gate tests Prowlarr, Sonarr and Radarr indexers
to clear stale failures. It also checks their health while online and retries
failed tests at most every 30 minutes. Unavailable indexers or credentials
still need attention if they do not recover; check the gate's journal with
`journalctl -t frey-media-gate`.

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
