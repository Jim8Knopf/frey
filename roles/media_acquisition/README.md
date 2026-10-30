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
`media_enable` (which services run) and
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
  qbittorrent_username: "media_admin"      # optional; defaults to admin
```

### Changing qBittorrent's WebUI login

Both halves live in the vault, and the vault is the only place to change
them. One deploy moves all four consumers together: qBittorrent's own
preferences, the download-client entry in each of the four *arrs, and the
download-gate script.

```bash
ansible-vault edit inventory/group_vars/all/secrets.yml \
  --vault-password-file .vault_pass
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags media_config --vault-password-file .vault_pass
```

**Do not change them in qBittorrent's web UI.** That moves one side only. The
*arrs keep sending the old credential, every poll comes back `401`, and they
report *"All download clients are unavailable due to failures"* while
qBittorrent itself looks perfectly healthy — with a `Username` in its config
that appears nowhere in this repository. The deploy is authoritative and will
put the vault's values back.

### Rotating the password, and the deadlock to avoid

Changing `qbittorrent_password` in the vault is **not** a plain re-deploy.
`setPreferences` is the only route to a running container, and reaching it
requires logging in with the credential you are trying to replace — so the
deploy authenticates with the new password against a qBittorrent that still
has the old one, fails, and retries for the full ten-minute API budget.

The order that works, and the reason for each step:

```bash
# 1. Stop it FIRST. A running qBittorrent holds its preferences in memory and
#    writes the whole file back out, silently discarding anything Ansible put
#    there - including the hash this procedure depends on.
sudo docker stop qbittorrent

# 2. Move the config aside. Clearing just the password line is not enough once
#    qBittorrent has migrated the file (see below): the role writes the legacy
#    key, and a migrated config ignores it.
sudo mv /opt/frey/appdata/qbittorrent/qBittorrent/qBittorrent.conf \
        /opt/frey/appdata/qbittorrent/qBittorrent/qBittorrent.conf.old

# 3. Deploy while it is still stopped. The seed template writes a fresh config
#    with both vault credentials, the container comes back up, and the wiring
#    stage then logs in and corrects all four *arrs.
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags media_acquisition --vault-password-file .vault_pass
```

Losing the old config costs nothing: every other preference is re-applied
through the API in the same run, and the torrents and their categories live in
`BT_backup/` and `categories.json`, not in `qBittorrent.conf`.

If you skip step 1, the symptom is qBittorrent logging
*"The WebUI administrator password was not set. A temporary password is
provided for this session"* on every start, because its own rewrite dropped
the seeded hash and it fell back to a random one.

qBittorrent reads the legacy `[Preferences]` `WebUI\…` keys this role seeds and
migrates them into a `[WebUI]` section of its own on first write, which is why
the stored keys are bare names rather than the prefixed ones in the template.

A banned IP (*"Your IP address has been banned after too many failed
authentication attempts"*) is held in memory only, so `docker restart
qbittorrent` clears it. Read the current password with:

```bash
sudo python3 -c 'import json; print(json.load(
  open("/opt/frey/appdata/.media-keys.json"))["qbittorrent_password"])'
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

## Spoken Language

English first, German if there is no English, anything else only when there is
neither — and the anything-else copy is replaced automatically once an English
release turns up.

Which languages is `media.languages` in `group_vars/all/main.yml`. How strict
is one flag, `media_language_require_one` in `group_vars/all/media.yml`:
`false` (default) keeps the last-resort grab, `true` rejects it and leaves the
episode missing until English or German exists.

`tasks/configure/languages.yml` applies it by creating one custom format per
language ("Language: English", "Language: German") and scoring them on **every**
quality profile:

| release | score | outcome |
| --- | --- | --- |
| English | 500 | grabbed first |
| German | 300 | grabbed when there is no English |
| German **and** English | 800 | best case; both formats match |
| neither | 0 | allowed, ranked last, upgraded away later |

Three things about that are deliberate:

- **No negative scores.** The profile minimum is `0`, so a negative score for
  the unwanted languages is exactly how you build a profile that downloads
  nothing and reports no error. Ranking last is enough.
- **Custom formats, not language profiles.** Sonarr 4 removed language
  profiles outright. Radarr still has a `language` field on the quality
  profile, but it is a hard *filter* — on its default `Original` it rejects an
  English dub of a foreign film — so the task moves it to `Any` and lets the
  scores rank. One mechanism for both apps.
- **Not Recyclarr.** Recyclarr has to fetch the TRaSH Guides over the uplink
  before it does anything, and when that fails it exits rather than carrying
  on. Its nightly run had been failing on DNS continuously, which is why both
  apps had *zero* custom formats and no language preference at all. Anything
  the van needs to be true with the uplink down cannot live there.

`cutoffFormatScore` is set to the English score, so Sonarr stops upgrading
once it has an English release instead of churning forever.

Jellyfin's *audio track* is the other half, and is not settable from here —
see Known Gaps.

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

**Image tags** are configured in `inventory/group_vars/all/images.yml`. An unattended pull on a campground Wi-Fi
must not be able to hand you a broken stack with no internet left to fix it
with. `scripts/media-check-updates.sh` reports what has moved upstream. Bump
deliberately:

```bash
# Re-pull the pinned tags and recreate what moved, while you still have a
# connection. Needs the explicit flag: a plain deploy never pulls.
ansible-playbook ... --tags media_update -e media_update=true
```

## Known Gaps

- **Bazarr subtitle providers and language profiles** live in its database,
  not its config file, so they are a one-time UI step. They matter most for
  the last-resort grab that is in neither preferred language.
- **Jellyfin's audio track** is a per-user playback setting, not a server one,
  so it cannot be set from here. A dual-audio file plays whichever track the
  release tagged default until "Play default audio track regardless of
  language" is unticked. The deploy's closing message spells it out.
- **Indexers** need your own tracker credentials and are added in Prowlarr.
- **Lidarr** depends on an upstream metadata server that has been unreliable
  through 2026; adding artists and imports break periodically. Not a
  configuration problem.
