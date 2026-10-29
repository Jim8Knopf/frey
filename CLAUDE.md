# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Frey is an Ansible project that configures one Raspberry Pi 5 as a self-contained
private network in a van. There is no application code — the deliverable is the
state of a single host. `AGENTS.md` holds the style and PR conventions; this file
covers the architecture and the traps.

## The constraint that shapes everything

**The Pi has no Ethernet port and no console. Both ways in are radios.** A change
that breaks networking or SSH does not degrade the system, it bricks it until
someone physically drives to it. This is why:

- Changes to the AP radio arm a deadman rollback timer before touching it, and
  disarm it only after verifying the interface took `10.20.0.1`
  (`roles/network_gateway`, `docs/GATEWAY.md`).
- The admin laptop is whitelisted out of every SSH rate limit, penalty and ban
  (`frey.trusted_devices` in `inventory/group_vars/all/main.yml`,
  `docs/SSH_ACCESS.md`). That hole is deliberate and load-bearing — OpenSSH 9.8+
  `PerSourcePenalties` locked the Pi out once already, triggered by ordinary
  bursts of `ansible-playbook` runs, with no log line naming a cause.
- Treat anything touching `network_gateway`, `security_baseline`, sshd config or
  firewall rules as high-risk. The `ssh-connection-guardian` and
  `network-architecture-expert` agents exist for exactly these.

## Commands

```bash
ansible-galaxy install -r requirements.yml                      # collections, first run only
ansible-playbook playbooks/site.yml                             # full deploy
ansible-playbook playbooks/site.yml --tags media                # one module
ansible-playbook playbooks/site.yml --check --diff              # dry run
ansible-playbook playbooks/site.yml -e frey_host=10.20.0.5      # reach the Pi at another address
ansible-vault edit inventory/group_vars/all/secrets.yml         # secrets
```

`ansible.cfg` sets the inventory and `vault_password_file`, so neither
`-i inventory/hosts.yml` nor `--vault-password-file .vault_pass` is needed — the
README and docs still spell both out, which is why you see them everywhere.

Default target is `10.20.0.1`, the FreyHub AP address, because it is the only
address that never changes. Reaching the Pi over its public-WiFi uplink needs
`-e frey_host=<uplink-address>`.

### Verification scripts

These are the test suite. There is no lint config, no CI, and `ansible-lint` and
`yamllint` are not installed. Run from the repo root on a machine that can reach
the Pi:

```bash
scripts/monitoring-check.sh            # every target up, rules loaded, collectors fresh
scripts/monitoring-check.sh --test     # prove a notification reaches the phone
scripts/identity-check.sh              # assert SSO is actually enforcing
scripts/media-check-updates.sh         # pinned image versions vs upstream (needs internet)
git-hooks/test-pre-commit.sh           # regression tests for the vault hook
```

The real acceptance test for any change is: **run it twice and the second run
reports 0 changed.** Then run the matching check script — "the container is up"
is not evidence the thing works, which is the whole point of those scripts.

### Agent-session gotchas

- **Redirect ansible output to a file.** In this environment `ansible-playbook`
  runs die immediately unless stdout and stderr go to a file:
  `ansible-playbook playbooks/site.yml > /tmp/deploy.log 2>&1`, then read the log.
- **`--list-tags` is useless here.** It reports only `always`, because tags are
  attached dynamically by `include_role ... apply:`. Read the real tag list from
  `frey.modules.available` in `inventory/group_vars/all/main.yml` and the
  `tags:` lines inside each role.
- **`gh` is not installed.** `gh pr create` exits 127. Push the branch and hand
  over the GitHub compare URL instead.
- **`new` is the working main branch**, not `main`. `origin/main` is the previous
  stack. Base branches on `new` and open PRs with `--base new`. A fresh worktree
  defaults to `origin/main`, so `git reset --hard new` right after creating one.
- **Name branches `<type>/<slug>`** with a Conventional Commits type, matching the
  commit convention: `feat/identity-sso`, `fix/journald-volatile`,
  `docs/claude-md`. The `worktree-*` and `claude/*` branches in the history are
  tooling artifacts, not the convention. EnterWorktree always names its branch
  `worktree-<name>` and that cannot be configured, so rename it immediately —
  `git branch -m <type>/<slug>` — before the first push.
- **In a worktree, `.vault_pass` is absent** (it is gitignored, so it is not
  cloned in). Ansible runs and the vault pre-commit hook both fail there. Copy it
  in `chmod 600`, or run ansible from the main checkout. Either way, never
  `git add -A` in a worktree — vault auto-encryption cannot protect you.

## Architecture

### The module registry

`playbooks/site.yml` is ~30 lines and knows nothing about any service. It asserts
every enabled module is registered, then loops `frey.modules.enabled`, including
`frey.modules.available[<module>].role` with that module's tags applied.

So **`inventory/group_vars/all/main.yml` is the control plane**: enabling,
disabling and reordering modules all happen there, not in the playbook.

**Module order in `frey.modules.enabled` is load-bearing**, and the file explains
each dependency inline. The chain:

```
network_gateway → rpi_nvme → service_proxy → security_baseline
  → frey_pki        (issues the cert Traefik serves; no HTTPS → no OIDC)
  → identity        (creates authelia@file; a router naming an unknown
                     middleware is DROPPED, so the service 404s with a
                     perfectly healthy container)
  → media_acquisition → media_library   (acquisition generates the *arr API
                                         keys library wires Seerr to)
  → monitoring      (reads identity's Grafana OIDC secret, and derives what
                     to probe from identity_services)
  → dockge          (optional, depends on nothing)
```

Adding a module: role + `defaults/main.yml` + `tasks/main.yml` + `README.md`,
then register it in `available` and list it in `enabled`. See
`docs/ADDING_MODULES.md`.

### Where variables belong

| Location | Holds |
| --- | --- |
| `roles/<m>/defaults/main.yml` | everything specific to that module — the default home |
| `inventory/group_vars/all/main.yml` | module registry, and only choices *two or more* modules must agree on |
| `.../media.yml`, `.../identity.yml`, `.../monitoring.yml` | the per-module files a human edits day to day: image versions, toggles, thresholds, who may log in |
| `.../secrets.yml` | vault ciphertext, nothing else |

Two subtleties that have bitten:

- **A role's defaults are only in scope while that role runs.** Anything one
  module must read from another (`frey.pki_public_dir`,
  `service_proxy.traefik.metrics`) is therefore declared in `main.yml` as well,
  with a comment saying why. Don't "clean up" those apparent duplicates.
- **`hash_behaviour = merge` in `ansible.cfg` is what lets `main.yml` set some
  nested keys and inherit the rest** from role defaults. It is deprecated in
  ansible-core; `security_baseline.ssh` is spelled out in full rather than
  relying on the merge, because a half-rendered sshd drop-in is the one failure
  that cannot be fixed remotely.
- `group_vars/` must stay beside `inventory/`. A copy at the repo root is
  silently ignored when running `playbooks/site.yml`.

### Networking

Two radios, deliberately assigned:

| Role | Interface | Why |
| --- | --- | --- |
| FreyHub AP, `10.20.0.1/24` | `wlan0` built-in Broadcom | the critical always-on service gets the soldered-down radio with the best AP driver |
| Public WiFi uplink | `wlan1` Realtek USB | expendable; losing it costs internet, never FreyHub |

Swapping the two `interface:` lines in `main.yml` swaps the roles — nothing else
hardcodes a radio. **FreyHub must serve clients fully with no uplink present**;
nothing below the Pi may depend on internet. dnsmasq resolves `frey` and
everything under it, at any depth, to the Pi, answered locally.

The firewall's allow rules are scoped per-interface with default-deny INPUT, so
a packet from a Docker bridge to the host matches nothing and is dropped. That is
why nothing in `monitoring` reaches the host by address — no host-networked
exporter, no probe of `https://10.20.0.1`. Everything is container-to-container.

### Service access, and the `hub` label

Services live at **`<name>.hub.frey`**, served over HTTPS with the Frey CA
certificate. `<name>.frey` still resolves and permanently redirects there, via the
`to-canonical` middleware in `roles/service_proxy/templates/traefik-dynamic.yml.j2`.

That extra label is not decoration. Authelia's session cookie needs a domain
containing a period, and under the Public Suffix List's default rule a bare
unknown TLD is itself a public suffix — so `Set-Cookie; Domain=frey` is refused
and forward auth would log in and then redirect-loop forever. `hub.frey` has a
period, is not a public suffix, and covers every service.

Adding a web service needs **no DNS change**: join the `frey_proxy` Docker
network and add Traefik labels. Each service gets three routers (canonical HTTPS,
legacy `.frey` redirect, plain HTTP) — copy the `proxy_labels` macro from
`roles/media_acquisition/templates/docker-compose.yml.j2` rather than writing
them out; it reads `identity_protect` and emits all three correctly.

A protected service **cannot** be served over plain HTTP (the session cookie is
`Secure`). Unprotected ones deliberately keep answering HTTP so televisions and
consoles — which cannot install a private CA — keep working. That is why
Jellyfin, Audiobookshelf and Seerr are on plain HTTP on purpose.

### Identity

LLDAP is the directory, Authelia the login page and OIDC provider.
`inventory/group_vars/all/identity.yml` is the only file normally edited: add a
person to `identity_users`, protect a service with one entry in
`identity_services` (`forward_auth` needs nothing from the app; `oidc` means the
app logs in against Authelia itself).

The bottom of that file derives `identity_protect` and `identity_hostnames`.
**Those two flat lists are the entire interface other modules use** — they never
reach into `roles/identity/`, which is what lets the media stack still deploy
correctly with identity switched off: the lists resolve empty and every router
stays on plain HTTP. Preserve that boundary.

### Media

Split along the line that matters in a van:

- `media_library` — Jellyfin, Audiobookshelf, Seerr. Works with **no internet at
  all**. This is the half that matters parked off-grid.
- `media_acquisition` — the *arrs and qBittorrent. Needs an uplink and pauses
  itself when there isn't one, including behind a captive portal, which looks
  online to an application but is not.

Both mount one `/opt/frey/data` tree at the same path in every container, which
is what makes an import a hardlink rather than a copy. The internal container
network (`172.28.0.0/16`) must never overlap FreyHub's `10.20.0.0/24` — the
archived role used `10.20.0.0/24` here, which would have blackholed the AP.

**The Pi 5 has no hardware video encoder.** Every transcode is software and
competes with the gateway for CPU, so quality profiles chase direct play
(H.264 + AAC, 1080p, reject 2160p/HDR-only/AV1) rather than relying on
transcoding. Don't "improve" the profiles toward higher quality without
accounting for that.

### Monitoring

Four independently switchable layers: metrics (Prometheus, node-exporter,
cAdvisor, blackbox), alerting (Alertmanager + a notification relay), logs (Loki,
Alloy), and Grafana — which is purely a viewer, so disabling it loses no data and
stops no alert.

The relay is what the van makes necessary: Alertmanager drops a notification it
cannot deliver, so the relay holds undelivered alerts on disk with the time they
really fired and flushes them with a summary when an uplink appears.

Everything the Pi knows about itself that no exporter reports — throttling,
under-voltage, PMIC rail power, NVMe SMART, AP clients, DHCP leases, DNS, NAT,
container state — arrives through node-exporter's textfile directory, written by
a systemd timer on the host. **Anything writing a `.prom` file into
`/opt/frey/metrics/textfile/` becomes a monitored metric on the same terms**;
that is the seam for future van sensors.

Two severities only: `critical` buzzes, `warning` arrives silently.

**Unsafe shutdowns are the live hardware concern on this van** — the NVMe's own
count of times power was cut rather than halted. Every one is a chance of SQLite
corruption across the *arrs, Jellyfin and LLDAP. `FreyUnsafeShutdown` and
`Frey5vRailLow` are both critical. When something is behaving strangely, check
that count before blaming software.

Most of them had one cause, now fixed in `rpi_nvme`: APST parked the DRAM-less
drive in a 5 mW state it could not reliably wake from, it left the PCIe bus
(`controller is down; CSTS=0xffffffff`), and the host **wedged rather than
crashed** — systemd keeps petting the hardware watchdog from RAM, so nothing
rebooted and only the button recovered it. The full account is in
`roles/rpi_nvme/README.md`. Two traps worth carrying forward:

- **A wedged Pi that answers ping but refuses SSH is not a lockout.** `sshd`
  cannot read `authorized_keys` off a dead disk, so it fails authentication with
  `Permission denied (publickey)` — which reads exactly like the
  `PerSourcePenalties` problem in `docs/SSH_ACCESS.md` and sends you to the
  wrong page. Check whether the journal has stopped before concluding anything.
- **An empty journal after a freeze is evidence, not a gap.** The journal lives
  on the disk that disappeared, so the kernel's complaint never reached it.
  Loki has it, because it was shipped off-host before the wedge.

## Secrets

`inventory/group_vars/all/secrets.yml` is AES256 vault ciphertext and **is
tracked on purpose** — committing it is what lets a rebuild reproduce the FreyHub
passphrase and known networks. `.vault_pass` is gitignored and must stay
`chmod 600`.

Edit without ever decrypting on disk: `ansible-vault edit <file>`.

Enable the hooks once per checkout — `git config core.hooksPath git-hooks && chmod +x git-hooks/*`.
`pre-commit` encrypts rather than blocks: a staged plaintext vault file is
encrypted and re-staged, and if it also has unstaged edits only the *index* is
encrypted so those edits are not swept into the commit. It blocks on two things
it cannot safely fix — no `ansible-vault`/`.vault_pass`, and a plaintext
`vault_*:` value in an ordinary vars file (move it into the vault instead;
encrypting a general vars file would hide non-secret config from everyone).
A pure Jinja reference like `"{{ vault_x | default('') }}"` is fine.

## Things not to do

- Don't edit anything under `/opt/frey/` on the Pi by hand. Ansible generates it
  and will revert you — including compose files edited through Dockge, which the
  role mounts read-only for that reason. Lasting changes go in
  `roles/<module>/templates/`.
- Don't deploy services before the NVMe migration (`docs/NVME_MIGRATION.md`).
  Cloning a live root filesystem is safe on a fresh install, not once databases
  are running. `playbooks/nvme_migrate.yml` is destructive and not part of a
  normal deploy; on an already-migrated Pi it detects that and ends cleanly, so
  sweeping every playbook in `playbooks/` is safe.
- Don't reference anything under `archive/legacy-stack/`. It is the previous
  stack, kept for reference, and is not on the role path.
- Don't pin a `:latest` image. Everything is version-pinned because an
  unattended pull on campground WiFi can hand you a broken container with no
  internet left to fix it. `identity_versions.authelia` especially: Authelia's
  config schema moves between minor releases, which is why the role runs
  `authelia validate-config` before restarting anything.

## Docs map

`docs/GATEWAY.md` radios, captive portals, deadman rollback, two-phase migration ·
`docs/IDENTITY.md` SSO, the `hub` label, certificates ·
`docs/MEDIA.md` · `docs/MONITORING.md` · `docs/SSH_ACCESS.md` the lockouts and the
whitelist · `docs/SECURITY.md` · `docs/NVME_MIGRATION.md` ·
`docs/SERVICE_MODULES.md` Traefik label patterns ·
`docs/ADDING_MODULES.md` · `docs/ARCHITECTURE.md` · `docs/IMPROVEMENTS.md` roadmap ·
plus a `README.md` in every role.
