# media_library

Playback and browsing: Jellyfin, Audiobookshelf, Seerr, AudioBookRequest,
Maintainerr and Jellystat.

This is the half of the media stack that works with **no internet at all**.
Parked off-grid it is the only half that matters, which is why it is a
separate module from [`media_acquisition`](../media_acquisition/README.md) and
why it creates the directories and network it needs rather than assuming the
other module ran first.

## Service Hostnames

| Service | URL (and aliases) | Purpose |
| --- | --- | --- |
| Jellyfin | `jellyfin.frey` | Film, TV, music |
| Audiobookshelf | `audiobookshelf.frey`, `books.frey` | Audiobooks and podcasts |
| Seerr | `seerr.frey`, `requests.frey`, `jellyseerr.frey` | Request films and shows |
| AudioBookRequest | `audiobookrequest.frey`, `bookrequests.frey` | Request audiobooks |
| Maintainerr | `maintainerr.frey` | Rule-based library cleanup |
| Jellystat | `jellystat.frey` | Playback statistics |

Each service answers on its own name plus any aliases. The service-name
hostname is always present: renaming one silently breaks every bookmark
pointing at the old name, so friendlier names are added alongside, never
instead.

Offline behaviour: Jellyfin and Audiobookshelf serve from local disk and need
nothing upstream. Seerr needs TMDB to browse, so with no uplink it degrades to
showing what is already requested — the queue still drains later when the
*arrs get a connection.

## The Pi 5 Cannot Transcode

The Pi 5's hardware video encoder was **physically removed**; only an HEVC
decoder remains. Every Jellyfin transcode is therefore pure software, and it
competes with FreyHub and SSH for the same four cores. FreyHub is the only way
into this machine — no Ethernet, no console — so Jellyfin is capped at 2 CPUs
and 2 GB.

The real fix is never to transcode. The quality profiles in
`media_acquisition` target 1080p H.264 with AAC audio for exactly this reason:
phones, tablets and laptop browsers all direct-play that, and browsers in
particular will transcode HEVC or non-stereo audio.

If playback stutters, check whether Jellyfin is transcoding before blaming
the network:

```bash
curl -sS -H "Host: jellyfin.frey" http://10.20.0.1/Sessions \
  -H 'Authorization: MediaBrowser Token="<token>"' | jq '.[].TranscodingInfo'
```

`devices: []` in `defaults/main.yml` is deliberate — Jellyfin's V4L2 support
for the Pi's HEVC decoder is partial, and a half-working hwaccel is worse than
none. The hook is there if you want to experiment.

## Jellyfin 12

This deploys Jellyfin **12.3**, a major jump from the 10.x the archived stack
ran. What changed:

- Legacy authorization is disabled by default.
- The `/emby/*` and `/mediabrowser/*` routes are gone; old third-party clients break.
- The database migration is **one-way** — 10.x cannot be restored from it.
- Plugins must be **removed before** migrating an existing 10.x config.

This deployment is greenfield, so none of that bites. **Do not point it at an
old 10.x config directory** without backing up first and uninstalling plugins.
This is also why Jellyseerr is gone: its Jellyfin authentication does not
survive the rework, and it is discontinued upstream. Seerr is the maintained
continuation of Overseerr and Jellyseerr both.

## Jellyfin Setup Is A Browser Step

`configure.provision_jellyfin` defaults to **false**. The API path exists in
`tasks/configure.yml` but it does not work on Jellyfin 12.3: the
`/Startup/Configuration` and `/Startup/Complete` calls are accepted while
`/Startup/User` does not create the administrator. Since every step tolerated
failure, the first deploy completed the wizard anyway and produced a server
with no account able to log in — and completing the wizard is a one-way door.

That has since been made safe (completion is gated on the admin actually
existing) but the automation is still off, because a convenience that can
brick admin access is not a convenience.

So: open `http://jellyfin.frey`, run the two-minute wizard, then add the three
libraries, all pointing into the read-only `/data/media` mount:

| Library | Type | Path |
| --- | --- | --- |
| Movies | Movies | `/data/media/movies` |
| TV Shows | Shows | `/data/media/tv` |
| Music | Music | `/data/media/music` |

The deploy prints this same list at the end of every run.

**Seerr's first run is deliberately not automated.** Its settings live in a
JSON file whose schema changes between versions, and a malformed seed does not
fail politely — it stops the container from starting. Trading a two-minute
form for a chance of a dead request service in a van with no internet is a bad
deal. The run prints the URLs and API keys to paste in.

## Required Variables

Shared values come from `media` in `inventory/group_vars/all/main.yml`.
Everything else is in `defaults/main.yml`. No vault entries are required;
the Jellyfin admin password and Jellystat's secrets are generated on first
deploy into `/opt/frey/appdata/.media-keys.json` (mode 0600).

Read the generated Jellyfin admin password with:

```bash
sudo jq -r .jellyfin_admin_password /opt/frey/appdata/.media-keys.json
```

## Validation

```bash
docker compose -f /opt/frey/stacks/media_library/docker-compose.yml ps

# Jellyfin answering through Traefik
curl -sS -H "Host: jellyfin.frey" http://10.20.0.1/System/Info/Public | jq

# Libraries exist and point at /data/media
curl -sS -H "Host: jellyfin.frey" http://10.20.0.1/Library/VirtualFolders \
  -H 'Authorization: MediaBrowser Token="<token>"' | jq '.[].Locations'

# From a FreyHub client, the real test
# open http://jellyfin.frey in a browser
```

## Notes

- Jellyfin mounts `/data/media` **read-only**. It plays; the *arrs write.
  Nothing here can delete the library.
- Transcode scratch goes to the NVMe, not a RAM tmpfs — a 1080p transcode can
  write gigabytes and would OOM the Pi.
- Jellystat's PostgreSQL is on the internal network only, never on
  `frey_proxy`. Turn the pair off with
  `media_library.services.jellystat.enabled: false` if you want the RAM back.
- There is no HTTPS yet, so everything is plain `http://`. Some mobile apps
  insist on TLS; that waits on the Frey root CA noted in `docs/IMPROVEMENTS.md`.
