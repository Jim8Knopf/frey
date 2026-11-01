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

## Cleanuparr

Cleanuparr is configured over its REST API rather than by rendering a file,
because it has neither: its settings live in its own SQLite database, and
upstream dropped environment-variable configuration when v2 moved everything
into the UI. `PORT`, `PUID`, `PGID`, `UMASK`, `TZ` and the database variables
are the only environment knobs left, which is also why its `PUID` must be
pinned explicitly — the image defaults to 1000 and then cannot create a file
in the `media`-owned config directory.

`tasks/configure/cleanuparr.yml` registers qBittorrent as its download client,
registers Sonarr, Radarr and Lidarr with the same API keys Ansible seeded them
with, and switches the queue cleaner on. Defaults live under
`media_acquisition.cleanuparr_wiring`.

Three things that are easy to get wrong:

- **The API key is the inverse of the *arr keys.** Ansible chooses those and
  seeds them before the container starts; Cleanuparr generates its own when
  the first account is created. So the role reads it back out of Cleanuparr's
  database read-only. Create the account once in the UI — until then the role
  reports Cleanuparr as unwired and changes nothing. Set
  `vault_media_api_keys.cleanuparr` to pin it in the repo instead.
- **A fresh install does nothing.** Every strike counter ships at `0`, which
  disables that category, so the container looks perfectly healthy and cleans
  up nothing.
- **`failed_import_pattern_mode` must be `Exclude` while the pattern list is
  empty.** `Include` means *only* failed imports matching a pattern are
  struck, so an empty list under `Include` is rejected outright and the whole
  queue-cleaner section refuses to save.

Chaptarr is absent on purpose: Cleanuparr has no Chaptarr application type,
and its Readarr type is not a drop-in for it.

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

The public indexer list is declarative: `media_indexers` in
`inventory/group_vars/all/media.yml`. `tasks/configure/indexers.yml` adds any
that Prowlarr is missing, puts the audiobook sources on their own sync
profile, and tags the ones marked `cloudflare: true` so Byparr is actually in
their path. It is a **floor, not a mirror** — nothing is reconfigured or
removed, so private trackers added by hand survive every deploy.

## The Resolver, And Why Indexers Kept Breaking

`frey-media-dns` is a dnsmasq container with one job: **delete AAAA records**.

The van's uplink has no usable IPv6 — no address on the uplink interface, no
default IPv6 route, no global IPv6 in any container. Campground resolvers
answer AAAA for Cloudflare-fronted trackers anyway, because the record really
does exist, and Docker's embedded resolver forwards whatever the campground
handed the Pi over DHCP.

.NET's `HttpClient` then connects to an address that cannot be reached:

```
System.Net.Http.HttpRequestException: Resource temporarily unavailable
  (www.limetorrents.fun:443)
```

Prowlarr reports that as "Unable to connect to indexer … typically caused by
DNS/SSL issues", backs the indexer off for hours, and Sonarr and Radarr say
*All search-capable indexers are temporarily unavailable*.

**What makes it so hard to diagnose:** `curl` against the identical URL
succeeds, because curl falls back to IPv4 and .NET does not. Every manual
check says the tracker is fine. Combined with Prowlarr's escalating backoff,
the whole thing looks intermittent and unreproducible.

So the stack resolves through its own dnsmasq with `filter-AAAA`, which also
means a campground's broken or filtering DNS can no longer disable indexers —
the reason this used to come back at every new parking spot.

```bash
# Is it up, and is it actually stripping AAAA?
docker exec prowlarr getent ahostsv6 thepiratebay.org
#   ::ffff:162.159.136.6  -> correct: an IPv4-mapped address, no real AAAA
#   2606:4700:7::a29f:8906 -> the resolver is being bypassed
```

Setting `dns:` does **not** replace Docker's embedded resolver — `resolv.conf`
keeps `127.0.0.11` and only its upstream changes — so container-name lookups
(`prowlarr` → `sonarr`) are unaffected. Worth knowing before changing it:
getting that wrong breaks every service-to-service call in the stack.

### When we cannot reach our own upstreams

Preferring public resolvers assumes we can reach them. Libraries, schools,
hotels and corporate guest networks routinely block outbound port 53 to
anything but their own resolver. Then every upstream times out, dnsmasq has
nowhere to forward, and **every lookup in the stack fails at once** — all the
*arrs, not one indexer.

It hides well: NetworkManager gives the *host* the network's resolver, so
`curl` and `ping` on the Pi work while the containers resolve nothing. It
reads as "Prowlarr is broken", then "Lidarr too", then "all of them".

`/usr/local/bin/frey-media-dns-upstream` keeps the upstream list honest. It
prefers `dns.upstreams` and falls back to the uplink's own DHCP resolvers only
while none of ours answers, returning the moment they do. Each candidate is
probed **from inside the resolver container** before being written — the
container's egress is NAT'd and firewalled differently from the host's, so the
host reaching an address is no evidence the container can. `filter-AAAA` keeps
working on the fallback, because it applies to the answer, not the upstream.

The list lives in `servers.conf`, not in `dnsmasq.conf`, because
`servers-file` is the one dnsmasq input re-read on **SIGHUP** — so the
upstreams change without restarting the resolver and dropping the stack's DNS
mid-search. Two traps in that file:

- It is bind-mounted as a single **file**, so the mount follows its inode. It
  must be rewritten in place; an atomic `mv` leaves dnsmasq reading the old
  inode forever and the update appears to work while changing nothing.
- Ansible deploys it with `force: false`. Re-rendering it every deploy would
  overwrite a live fallback with upstreams the current network blocks, taking
  DNS from the whole stack until the timer next ran.

```bash
frey-media-dns-upstream status        # mode now, and what each candidate does
sudo frey-media-dns-upstream apply    # re-select without waiting for the timer
scripts/test-media-dns-upstream.py    # offline tests for the selection logic
```

`frey_media_dns_upstream_mode{mode="preferred|uplink|none"}` reports which set
is live. Set `dns.fallback_to_uplink: false` to refuse the fallback entirely.

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

- **German release scoring** is not configured. The language *profiles* are
  set, but boosting German releases needs TRaSH custom formats referenced by
  `trash_id`, and those IDs are not guessed at in
  `templates/recyclarr.yml.j2`. Instructions are in that file.
- **Bazarr subtitle providers and language profiles** live in its database,
  not its config file, so they are a one-time UI step.
- **Private indexers** need your own tracker credentials, so they are added in
  Prowlarr's UI. Public ones are declared in `media_indexers`.
- **`media_library` still uses the campground's resolver.** Jellyfin and Seerr
  fetch metadata over the same uplink and are also .NET, so they can hit the
  same AAAA failure. Pointing them at `frey-media-dns` would make the library
  depend on a container this role owns, and the library is deliberately able
  to deploy and run with acquisition switched off entirely. Fixing it properly
  means a resolver that belongs to neither module.
- **Byparr's proxy test fails by design.** It implements no `sessions.*`
  commands, which is what Prowlarr's test button calls, so it answers `502`
  and Prowlarr logs `Proxy validation failed` on every health check while
  solving works correctly. Judge it by `docker logs byparr`.
- **Lidarr** depends on an upstream metadata server that has been unreliable
  through 2026; adding artists and imports break periodically. Not a
  configuration problem.
