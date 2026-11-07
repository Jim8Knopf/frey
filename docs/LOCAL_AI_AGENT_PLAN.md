# Local AI agent plan — a self-healing assistant with hard limits

Status: **phases 0-4 deployed and verified on 2026-11-07.** Builds on
`docs/LOCAL_AI_EVALUATION.md` and extends `docs/CAMPAIGN_ASSISTANT_PLAN.md`
phase 4 from "restricted draft agent" to "agent that helps keep Frey healthy".

Where a section describes what was *planned* and the deployed reality differs,
the deployed reality is marked inline — those divergences are the useful part
of this document, because each one was found by running the thing.

## 1. The four constraints this plan is built around

Given directly:

1. **Broad read, hard-capped write.** The agent may read nearly everything; what
   it may *change* is tightly bounded.
2. **Write only to explicitly named paths.** As deployed that is exactly two:
   the drafts directory and the broker's request queue. *(This started as
   "writes begin in the notes only" and was revised: reports go to a separate
   drafts directory the agent owns, so the write boundary is enforced by mount
   absence rather than by path checking inside the notes space.)*
3. **Immich and the photo directories are hard-capped for WRITING**, at system
   level, not by instruction — the agent can look at a photo and can never
   edit or delete one. *(Also revised. These were originally unmounted
   entirely; they are now mounted read-only, because reading is safe when
   there is no egress and the cap that matters is on writing.)*
4. **Networking is hard-blocked, to prevent bricking.**

The one place reading is itself the risk is credential material, because the
model could quote a secret into a draft that syncs to a phone. Those paths
stay unmounted, and there are more of them than the obvious four — the
per-service `.*-keys.json` files under `appdata` are generated secrets too.

And one inherited from `CLAUDE.md`: the Pi has no Ethernet and no console, so a
change that breaks networking or SSH does not degrade the system, it bricks it
until someone drives to it.

## 2. The governing idea: the model classifies, it does not invent

The agent must never hold a shell, `docker.sock`, or the ability to compose a
command. Instead:

- **You** write a finite catalogue of repair actions, each individually
  reviewed, idempotent and reversible.
- **The model's job is to match symptoms to a catalogue entry** — a
  classification task, well inside a 4B's range — or to say "no entry matches"
  and escalate.
- A separate **broker** service holds the privileges and exposes only those
  named actions, validated against an allowlist.

This is what makes the limits real. The model cannot restart `hostapd` because
**no endpoint accepts it** — there is no verb to call and no name that
validates. That is a property of the system, not a rule the model is asked to
honour.

The corollary matters as much: **everything is an allowlist, never a
denylist.** A denylist of forbidden containers fails *open* the moment a new
container appears — exactly what would happen when Immich is finally deployed.
An allowlist fails closed. Every list in this plan is generated from Ansible
variables and defaults to empty.

## 3. The hard limitation set

Six mechanisms, strongest first. A limit worth having is enforced by at least
two.

### M1 — Absence. Not mounted, therefore cannot exist.

The strongest primitive available, and the one that answers constraint 3. A
path that was never mapped into the container's mount namespace cannot be read
by any means: no traversal, no symlink, no bug in tool code, no prompt
injection. The denial is `ENOENT`, not `EACCES` — the path genuinely is not
there.

**As deployed.** The agent's row is what the container actually mounts; the
broker is a host service confined by systemd rather than by mounts, so its
column means "reachable in its namespace".

| Path | Agent | Broker | Why |
| --- | --- | --- | --- |
| `<drafts dir>` | **rw** (uid 10002) | — | reports; one of exactly two write paths |
| `<broker req queue>` | **rw** (uid 10002) | rw | the only channel to anything privileged |
| `<broker res queue>` | **ro** | rw | read-only to the agent, so it cannot forge its own answer |
| `/opt/frey/appdata/silverbullet` | **ro** + ACL | — | notes; 0700/0600, so an ACL grants the read |
| `/opt/frey/data` | **ro** | ro | media and its metadata, read freely |
| `/opt/frey/data/photos` | **ro** | ro | readable, never writable — constraint 3, and listed before Immich exists |
| `/opt/frey/stacks` | **ro** | ro | compose state. Chosen deliberately despite carrying API keys; see below |
| `/opt/frey/metrics/textfile` | **ro** | ro | the collector seam |
| `/opt/frey/appdata/local-ai/models` | **ro** | — | weights |
| `<broker approved dir>` | **never** | rw | the agent cannot approve its own proposal |
| `/opt/frey/pki` | **never** | **never** | 0700, holds the root private key |
| `.vault_pass`, `inventory/.../secrets.yml` | **never** | **never** | vault |
| `appdata/*/.*-keys.json`, `identity/secrets` | **never** | **never** | generated secrets, easy to miss |
| `/var/run/docker.sock` | **never** | yes, from phase 4 | the whole point of the split |
| host `/etc`, `/boot`, `/root`, `/etc/shadow` | **never** | **never** | sshd, firewall, `config.txt` |
| host root filesystem | **never** | ro | — |

One residual risk, recorded because it was a deliberate choice rather than an
oversight: the rendered compose files under `/opt/frey/stacks` **do** contain
*arr API keys, Authelia secrets and the LLDAP admin password. Nothing can be
exfiltrated — there is no egress, see M6 — but the model could quote one into
a draft, and drafts are read on a phone. Removing the single `/stacks` entry
from `local_ai.observer.read_paths` closes it; nothing else depends on it.

### M2 — No verb. The forbidden action has no endpoint.

The broker exposes a closed set of named operations. Anything absent from it is
unreachable, including every route to bricking the van:

**Has no endpoint, in any tier:** interface or route changes · `nmcli`, `ip`,
`iptables`/`nft`, `ufw` · `hostapd`, `dnsmasq`, NetworkManager · sshd or its
drop-ins · `ansible-playbook` or any deploy · `reboot`, `poweroff`, `systemctl
isolate` · `apt` · `/boot/firmware/config.txt` and the NVMe cure ladder ·
container create, exec, build, or volume operations · any write under
`roles/network_gateway` or `roles/security_baseline` · Immich, ever.

There is deliberately **no generic `run_command` and no generic
`restart_service`.** Those are the two verbs that would quietly re-admit
everything above.

### M3 — Allowlist lookup, generated from Ansible.

Verbs that name a target validate it against a list rendered from Ansible
variables. `restart_container` accepts only names appearing in that list.

Candidate tier-1 (stateless) targets, from the real container names in this
repo: `frey-media-dns`, `byparr`, `prowlarr`, `recyclarr`, `unpackerr`,
`blackbox`, `cadvisor`, `node-exporter`, `alloy`.

Explicitly **not** in the tier-1 list: `jellyfin`, `audiobookshelf`, `seerr`,
`lldap`, `authelia`, `sonarr`, `radarr`, `lidarr`, `bazarr`, `qbittorrent`,
`prometheus`, `loki`, `grafana`, `jellystat-db` — all SQLite- or
database-backed, so every restart carries the corruption risk `CLAUDE.md`
raises around unsafe shutdowns. `frey-traefik` is excluded too: restarting it
404s every service at once. These are tier-2 proposals (§5).

Add a role-time assertion that the generated allowlist never contains
`immich`, `hostapd`, `dnsmasq`, `frey-traefik`, or anything matching the
network roles — so a future edit cannot widen it by accident. The repo already
uses this pattern: `roles/campaign_ai/tasks/main.yml` asserts its own access
policy before doing anything.

### M4 — Kernel confinement on the broker. **Revised 2026-11-07: systemd, not AppArmor.**

**AppArmor is not available on this Pi.** The module is loaded, but
`/sys/module/apparmor/parameters/enabled` reads **`N`**, the filesystem is not
mounted, and `apparmor_parser` and `aa-status` are not installed. Enabling it
needs a kernel command-line change and a reboot — which on a console-less Pi
is exactly the class of change the constraint at the top of `CLAUDE.md` says
not to make casually.

**systemd's own sandboxing gets the same guarantees with no reboot and no new
package**, and it is enforced by namespaces and seccomp in the kernel rather
than by the broker's own code. Crucially `InaccessiblePaths=` produces
**ENOENT**: the path is not there, rather than there and refused — the same
distinction M1 rests on. The deployed unit carries:

| Directive | Effect |
| --- | --- |
| `ProtectSystem=strict` | the entire filesystem is read-only… |
| `ReadWritePaths=` | …except the two broker queues. This *is* the write allowlist |
| `InaccessiblePaths=` | every credential path, ENOENT even to root |
| `CapabilityBoundingSet=` (empty) | root without `CAP_DAC_OVERRIDE`, so it obeys ordinary permissions |
| `PrivateNetwork=yes` | no network at all; the channel is a directory |
| `SystemCallFilter=@system-service` | seccomp |
| plus | `NoNewPrivileges`, `ProtectHome`, `RestrictNamespaces`, `ProtectProc=invisible`, `ProtectKernelTunables/Modules/Logs`, `RestrictSUIDSGID`, `LockPersonality` |

Two things this cost, both worth recording:

- **The empty capability set has teeth.** Root without `CAP_DAC_OVERRIDE` is
  subject to ordinary permission checks, so the broker could not even traverse
  a request directory owned by the agent at 0750 — and Python's `glob()`
  swallows that `PermissionError` and yields nothing, so it sat there finding
  no work and logging nothing at all. Fixed by group ownership rather than by
  handing the capability back.
- `systemctl show` **does** work under `ProtectSystem=strict`, which was the
  main worry about going this strict. Verified.

Enabling AppArmor properly remains available as a deliberate, scheduled
change: `apparmor=1 security=apparmor` on the kernel command line, a reboot,
and the tools installed. It is not needed for the guarantees above.

### M5 — Rate limit, circuit breaker, kill switch.

An agent that restarts a container in a loop is a self-inflicted outage, so
bound the damage rather than trusting judgement:

- at most 3 actions per hour, and 1 action per target per hour;
- any health regression after an action **trips the breaker**: the agent is
  demoted to observe-only until a human resets it;
- a kill switch (an Ansible variable and a file the broker checks on every
  call) that returns the agent to observe-only with one deploy or one `touch`;
- every call logged to Loki and pushed to ntfy, so the action trail survives
  the agent and arrives on your phone.

### M6 — No egress.

Keep `ai_private` as `internal: true`, exactly as `roles/campaign_ai` already
has it. The agent reaches the broker and the model and nothing else — no
internet, no host, no other service by address. This is what makes constraint 1
(broad read) safe: there is no channel to leak to, and the only output is a
chat reply to someone already authenticated and already authorised to see that
material.

The agent container also keeps the hardening the current role already gets
right: `cap_drop: [ALL]`, `no-new-privileges`, `read_only: true`, non-root uid,
no `NET_ADMIN`, no host network namespace.

## 4. Shape

```
  observation (read-only)              action (privileged)
  ───────────────────────              ───────────────────
  Prometheus HTTP API  ─┐
  Loki query API       ─┤                  ┌─ verb allowlist (M2/M3)
  textfile collectors  ─┼→  AGENT  ──────→ │  rate limit + breaker (M5)
  notes (ro)           ─┤   no sock        │  deadman arm/disarm
  media metadata (ro)  ─┤   no shell       │  AppArmor (M4)
  image inbox (ro)     ─┘   no egress      └─ docker.sock (ro)
                              │                      │
                         writes ONLY to          BROKER
                         <drafts> (uid 10002)         │
                                                 Loki + ntfy
```

Container-to-container is how the rest of Frey already works, and
`CLAUDE.md` notes that nothing in `monitoring` reaches the host by address —
the agent must follow the same rule. It queries Prometheus and Loki as
containers on `frey_proxy`, never the host, and never `https://10.20.0.1`.

### Deadman, generalised from the AP radio

The repo already arms a rollback timer before touching the AP and disarms it
only after verifying the interface took its address. Apply the same idea to
every tier-1 action: before acting, the broker writes a pending-action record
with a deadline and an escalation; a systemd timer checks health afterwards. If
health is worse, the timer trips the breaker and ntfys **without the agent's
cooperation**. The agent cannot suppress its own failure.

### The agent cannot be its own watchdog

`docker kill -s HUP` flags a container manually-stopped so it vanishes at the
next reboot, and Prometheus cannot alert on its own absence. The same logic
applies here: the agent must be a monitored Prometheus target with its own
`absent()` alert, plus a host-side systemd timer that notices it is gone. An
agent that is supposed to notice problems must not be the thing that notices it
has stopped.

## 5. What the agent is actually for

Grounded in the faults this project has actually hit, not hypotheticals.

**Tier 1 — autonomous, reversible, stateless.** Each is already a documented
fix:

| Action | Fault it addresses |
| --- | --- |
| `recreate_container(frey-media-dns)` | container DNS goes stale after an uplink change; the relay stops reaching ntfy while TCP looks fine |
| `clear_arr_backoff(<app>)` | indexer failures leave each *arr with its own backoff that must be cleared separately |
| `dns_upstream_reevaluate()` | resolver pinned to a departed venue's DNS while `frey-media-dns-upstream status` reports healthy, because it probes the *host* |
| `rerun_collector(<unit>)` | a stalled textfile collector. Mind the trap: `frey-logrepair.prom` is written by `frey-log-repair.service`, so the allowlist must map file → unit explicitly |
| `flush_alert_relay()` | the relay holds undelivered alerts on disk and flushes when an uplink appears |
| `restart_container(<tier-1 name>)` | stateless containers from the M3 list |

**Tier 2 — propose, you approve over ntfy.** The agent writes the diagnosis and
the exact action; you reply yes. Restarting any SQLite-backed service, `docker
rm frey-traefik` for the stale port reservation (note the follow-up
`--tags proxy` deploy is **tier 3** — it proposes, you run it), disk cleanup.

**Explicitly out of scope: the NVMe dropout.** When the drive leaves the PCIe
bus the host wedges rather than crashes, the journal is gone with the disk, and
only the button recovers it. The agent cannot fix that and must not try — it
cannot even run. Its job there is to have already shipped the evidence to Loki,
which is what makes the wedge diagnosable at all, and to report the unsafe
shutdown count on the next boot.

**[DECIDE]** which subsystems get verbs at all. My proposal: media acquisition
and monitoring in tier 1; media library and identity in tier 2 only; notes
read-only plus the drafts write; networking never.

## 6. Where the LLM sits, and where it does not

A large share of what "keep the system healthy" means is better built **without
a model**. `frey-media-dns-upstream` already self-heals deterministically. For
every symptom you can already name — and `CLAUDE.md` plus the memory notes name
a dozen — a systemd timer and a script is faster, auditable, and cannot
hallucinate.

So the proposal is a division of labour:

- **Deterministic scripts own every known fault.** Build these first; they are
  useful with no agent at all, and they are the catalogue the broker exposes.
- **The model owns triage of what no rule matched.** It correlates metrics,
  logs and collector state, names a likely cause, and either picks a tier-1
  action or writes a proposal. This is where it adds something a script cannot:
  the 2026-11-01 class of fault where every *arr fails at once and the question
  is *which* of four known causes it is.
- **The model also owns the explanation.** A plain-language incident report in
  `/drafts`, readable on a phone, is valuable even when the fix was automatic —
  and it is the whole deliverable in the most conservative option. **[DECIDE]**

Keep the model's reliability in view: your 2026-11-02 benchmark caught it
contradicting itself with the rule supplied in the prompt. The architecture is
what makes that tolerable — the worst case is a *wrong but safe* choice from a
safe menu, caught by the deadman and the breaker. Do not relax the menu because
the model seems to be doing well.

## 6a. Hermes Agent, evaluated 2026-11-07

**Verdict: do not deploy on Frey. Disqualified by hardware arithmetic, not by
design.** This supersedes the open question in
`docs/CAMPAIGN_AGENT_EVALUATION.md`, which recorded two timed-out image pulls
and never reached a conclusion.

What changed since that note: the current release is **v0.23.0 (2026-11-05)**,
not the v0.22.5 recorded there. **ARM64 is confirmed**, so the architecture
doubt in that document is settled — `nousresearch/hermes-agent:v0.23.0` ships
`arm64/linux` at about 1120 MB compressed, with a `-desktop` variant at
1355 MB. The two earlier pull timeouts were a slow uplink, not a missing image.

### What is genuinely good about it

- **It runs fully offline against an OpenAI-compatible endpoint** — the docs
  name vLLM, SGLang, Ollama "or any OpenAI-compatible API", with a custom base
  URL. Phase 0 just gave Frey exactly such an endpoint, so the integration
  point already exists.
- **It can be fully contained.** Alongside terminal-backend isolation it
  supports **whole-process wrapping**, running the entire agent process tree
  in a Docker container under declarative filesystem, network, process and
  inference policy. That is precisely what §3 requires.
- **Its security documentation is unusually honest**, and worth quoting
  because it states the thesis of this whole plan better than this document
  does: *"The only security boundary against an adversarial LLM is the
  operating system. Nothing inside the agent process constitutes
  containment."* It also says in-process approval gates and redaction are
  *"not security boundaries"* but heuristics. Any vendor willing to write that
  down is being straight with you.

### Why it still cannot run here

**The context requirement.** The documentation states a hard minimum:
*"Hermes Agent requires a model with at least 64,000 tokens of context."*
Frey serves 8192. The cost of 64K on this hardware is arithmetic, not opinion.

Qwen3.5-4B is 32 layers with 4 key/value heads and head_dim 256, so each token
costs `2 x 32 x 4 x 256` values of KV cache — **128 KiB per token at fp16**:

| Context | KV cache fp16 | KV cache q8_0 | Plus 2.71 GiB weights |
| --- | --- | --- | --- |
| 8192 (deployed) | 1.0 GiB | 0.5 GiB | 3.7 / 3.2 GiB |
| **64000 (Hermes minimum)** | **7.8 GiB** | **~3.9 GiB** | **10.5 / 6.6 GiB** |

The host reported **8 GiB available** on 2026-11-07. The fp16 column is
impossible. The q8_0 column technically fits and then leaves about 1.4 GiB for
Jellyfin, the *arrs, Authelia, LLDAP and monitoring — which is the same
CPU-and-RAM contention argument `CLAUDE.md` already makes about software
transcoding, except worse, because it is resident rather than occasional.

**And the arithmetic that actually settles it is prompt processing.** Context
is not free to *fill*. Prompt processing is compute-bound and the Pi 5's A76
cores have no i8mm. At a generous 20 tokens/s, a 64K-token agent turn spends
**roughly 53 minutes before the first output token**. Even a modest 10K-token
turn is about eight minutes. An agent that takes tens of minutes per step
cannot keep a system healthy; the fault it was reasoning about has moved on.

A secondary problem: *"Any component running inside the agent process (skills,
plugins, hook handlers) can read whatever the agent itself can read, including
in-memory credentials."* That is fine under whole-process wrapping with no
credentials present, but it means the boundary must be the container, and
every skill and plugin must be treated as having the agent's full access.

### What to do instead

- **Keep the broker design in §3.** It exists because the model must not hold
  a shell. Hermes's own security page agrees with that reasoning.
- **Keep the `/v1` endpoint as the integration seam.** If Hermes is ever
  wanted, it belongs on the ThinkPad — a machine with real compute — pointed
  at a real model, not on the Pi. The endpoint makes that possible with no
  further work.
- **Re-evaluate only if** the context minimum drops substantially, or Frey
  gains hardware with the memory bandwidth and compute to fill 64K in seconds
  rather than minutes. Neither is foreseeable on a Pi 5.

## 7. Phases

Each phase is independently useful and independently abandonable.

**Phase 0 — prerequisites from the evaluation.** Model upgrade to Qwen3.5-4B
UD-Q4_K_XL, `--cache-reuse`, the rename to `local_ai` / `ai.hub.frey`, and the
generalised OpenAI-compatible endpoint. Do the rename *before* building agent
tooling, or you build it twice. Covers `LOCAL_AI_EVALUATION.md` §12 steps 1–4.

**Phase 1 — read-only observer. Zero risk, immediately useful.** The agent
reads Prometheus, Loki and the textfile collectors and writes incident reports
into `/drafts`. No broker, no verbs, no actions. This alone solves the real
problem of having to diagnose Frey from a phone, and it is the honest test of
whether a 4B is good enough at correlation before anything can act.

**Phase 2 — deterministic self-healing, no LLM. DONE 2026-11-07.** Turn the
known faults in §5 into scripts and timers. Independently valuable; this is
the catalogue.

Shipped as `frey-self-heal`, a sibling of the existing `frey-monitor-watchdog`
in `roles/monitoring`, so it keeps working with `local_ai` switched off
entirely. Three findings reshaped it, and two of them removed work:

- **It is alert-driven, not a second detector.** 70-odd Prometheus rules
  already detect these faults and are tuned against the real failure modes.
  Re-implementing detection would have meant a worse second copy that drifts,
  so the script maps an **alert name** to one repair. The rules stay the single
  source of truth for "something is wrong".
- **Two of the four chosen faults were already handled.** DNS upstream
  re-evaluation self-heals already — `frey-media-dns-upstream.timer` runs every
  10 minutes with a NetworkManager dispatcher hook — so nothing was built for
  it. And indexer revalidation already existed inside `frey-media-gate`, but
  only on the offline-to-online transition, which a DNS-only outage never
  produces. That became one new `refresh` verb on the gate rather than a
  reimplementation, reusing its API keys and its revalidation call.
- **`frey-media-dns-upstream` cannot see the fault it looks closest to.** It
  probes a *named upstream* directly from inside the container, so it reports
  healthy while resolution *through* dnsmasq fails. (The note in memory that it
  "probes the host" is wrong — it uses `docker exec`; the real gap is that it
  bypasses dnsmasq's own forwarders.) `frey-self-heal` therefore resolves
  through the container's own resolver and compares against the host before
  recreating anything.

It is deliberately separate from the watchdog, which depends on nothing —
not Prometheus, not Alertmanager — because its job is to tell you the
monitoring itself is dead. `frey-self-heal` *does* depend on the alert chain;
if Alertmanager is down it does nothing, and the watchdog is what notices.
**Do not merge them.**

Limits: a hardcoded refusal list (networking units, sshd, hostapd, dnsmasq,
NetworkManager, and the one collector owned by `network_gateway`), a per-fault
cooldown, a hard per-run action cap, and `monitoring_alerting.self_heal.act`
to drop back to diagnose-and-notify. Verbs for anything that could brick the
van do not exist in the file.

**Phase 3 — broker with read verbs only, plus the denial test suite. DONE
2026-11-07.** Build the broker, expose only reads, and prove every limit in §3
holds before a single write verb exists (§8).

**The channel is a directory, not a socket or a port.** That was forced by a
fact worth knowing: the agent container has **no default route and cannot
reach the host on any port** — verified, not assumed. That is deliberate, and
it is what makes the agent's broad read access safe. So a host-side listener
is unreachable by construction, and mounting `docker.sock` into the agent
would hand it the one thing this whole design withholds. The agent writes a
request file into a directory it can write; `frey-broker`, running on the host
under the systemd sandbox in §3 M4, validates it against an allowlist and
writes a response into a directory the agent can only read — so it cannot
forge an answer to its own request.

**No Docker access at all.** The agent already gets container state from
cAdvisor through Prometheus, so the broker never needed the socket. Even
`container_logs` reads Docker's JSON log files straight off disk, which grants
no ability to start, stop or exec anything — and still works when Loki, which
normally carries those lines, is itself what broke.

Three read verbs, each something the agent cannot get for itself:
`unit_state` (systemd state for an allowlisted unit), `diagnostic` (output of
an allowlisted read-only command — `frey-self-heal status` and friends), and
`container_logs`. Dispatch is an exact dict lookup, so an unknown verb has
nowhere to go.

`scripts/local-ai-broker-check.sh` drives all of it from inside the agent
container and **all 21 checks hold**: the three verbs work; `hostapd.service`,
`ssh.service`, `NetworkManager.service`, an unlisted container and an unlisted
diagnostic are all refused; `restart_container`, `run_command`,
`restart_service`, `reboot`, `write_file` and `nmcli` do not exist; argument
smuggling through a diagnostic name and traversal through a container name are
both rejected; and the response directory rejects writes from the agent.

Two traps found by running it rather than reading it:

- **Docker's data-root is `/opt/frey/docker`, not `/var/lib/docker`** — moved
  by the NVMe migration. The old path still exists and is empty, which is the
  worst case: reading it finds no containers and looks exactly like a
  container that is not running.
- An unquoted `Environment=` assignment containing a space is split by systemd
  into several broken assignments, reported as "Invalid environment
  assignment" and then **ignored** — which silently emptied the diagnostic
  allowlist.

The agent's read surface was also widened here, per the decision that it may
**read broadly and write only to explicitly named paths**: media, notes, the
collectors and the stacks tree are mounted read-only, photos are listed ready
for Immich, and only two paths are read-write — `/drafts` and the broker's
request queue. Credential material stays unmounted. Note that more credential
files exist than the obvious ones: the per-service `.{identity,media,monitoring}-keys.json`
files and `identity/secrets` are generated secrets too.

**Phase 4 — write actions, deadman, breaker, kill switch. DONE 2026-11-07,
propose-only.** One verb at a time, starting with
`recreate_container(frey-media-dns)` — the most frequent fault and the most
clearly reversible.

**The model proposes; it never acts.** `recreate_container`,
`restart_container` and `rerun_unit` are **not in the verb table at all**, so
the agent cannot call them — the only path to one is a proposal that a human
has approved by typing its id on the host. The write path therefore has a
person in it by construction rather than by policy.

That asymmetry against phase 2 is deliberate and worth stating, because it
would otherwise look inconsistent: `frey-self-heal` acts autonomously because
a tuned alert rule matched a **known** symptom and the fix was written by
hand. Here the **model's judgement** is the thing being trusted, and it has
already produced one confident, well-structured, entirely wrong diagnosis. So
nothing is lost by gating it — the known faults still self-heal untouched, and
only the novel cases wait for a human.

The flow:

1. The agent calls `propose` with an action and a reason of at least 20
   characters. The broker validates the inner verb **and its target** against
   the same allowlists execution will use, so an un-approvable proposal is
   refused while the model can still be told why rather than after a human has
   been paged.
2. `frey-broker-supervisor` pushes it to ntfy with the literal command to run.
   The broker cannot do this itself — it has `PrivateNetwork=yes` — and
   keeping egress in a separate unit means it lives in the component with no
   model input and no container privilege.
3. `sudo frey-broker-approve <id>` writes a marker carrying **only the id**.
   Execution re-validates from scratch, so approving cannot smuggle a
   different action than the one you were shown. `--list` shows what is
   waiting; `--reject` declines now; ignoring it lets it expire.
4. The broker executes it, then **arms a deadman** recording the health it
   measured beforehand.
5. The supervisor re-measures after a grace period using the *same* code —
   `health_snapshot` is imported, not reimplemented, because a deadman
   comparing two different definitions of health is worse than none. If
   stopped containers or firing alerts rose, it **trips the kill switch first
   and notifies second** (the order matters when there is no uplink) and the
   broker refuses every verb until you `rm` the switch.

There is **no automatic revert**, by choice: a blind undo is itself an
unattended action taken while the system is already degraded, which is how one
fault becomes two. Every action here is reversible by hand.

A missing health measurement never counts as a regression — a failed probe
would otherwise make every uplink outage look like a bad repair.

**The deadman false-tripped on its first real run, which was worth more than
a clean pass.** Health was defined as *all* firing alerts, and the count went
2 → 3 right after re-running a metrics collector — something that cannot
possibly cause an alert. The breaker tripped correctly on its own terms and
disabled the broker, exactly as designed; the definition of health was the
bug. On this Pi the warning tier flaps constantly (the 5V rail hovers right at
its 4.95 V threshold, container memory is high *because the model itself is
4 GiB*) and the `Watchdog` heartbeat alert fires permanently by design, so
counting those makes every action look harmful.

Health is now **stopped containers plus CRITICAL alerts only**. Criticals are
rare here and are what actually matters, so a new one appearing right after a
repair is worth stopping for. This is the kind of fault only a live run finds:
every unit test of that comparison would have passed.

Approval needs SSH, which on a phone means an SSH client rather than a tap.
That was accepted deliberately: the alternatives were a web endpoint whose
whole purpose is triggering privileged actions, or parsing notes for
approvals. ntfy's action buttons cannot do it, because Authelia forward auth
302s any non-browser POST.

`scripts/local-ai-broker-check.sh` proves both halves: that the three write
actions are **not callable by the agent at all**, that `propose` refuses a
forbidden target, a non-action verb and a missing reason, that the approval
directory is absent from the agent so it cannot approve itself, that a valid
proposal stays pending until approved, and that approval then really runs the
unit, arms the deadman, and cannot be replayed.

**Phase 5 — tier-2 propose-and-approve over ntfy.**

**Phase 6 — graduate verbs individually**, on logged accuracy, not impression.
A verb earns autonomy after N correct proposals. **[DECIDE]** the starting
autonomy: my proposal is phase 4's tiering, but propose-only for the first
weeks is the zero-surprise path.

## 8. Proving the limits — `scripts/agent-denial-check.sh`

Per `CLAUDE.md`, "the container is up" is not evidence the thing works, and the
check scripts are the test suite. A limit that has not been *attempted* is not
known to hold. The new check script must try to break each one and require
failure:

| Test | Expected |
| --- | --- |
| `restart_container("hostapd")` | rejected — not in allowlist |
| `restart_container("jellyfin")` | rejected in tier 1, proposal in tier 2 |
| any networking verb | 404 — no such endpoint |
| `run_command` / `restart_service` | 404 — deliberately absent |
| read the photo path | **ENOENT**, not EACCES — proves absence, not permission |
| read `/opt/frey/pki/`, `.vault_pass`, `/opt/frey/stacks/` | ENOENT |
| `stat /var/run/docker.sock` from the agent | ENOENT |
| `curl https://1.1.1.1` from the agent | fails — no egress |
| write outside `<drafts>`; `../` traversal; symlink escape from `<drafts>` | rejected after `realpath` |
| generated allowlist contents | asserts no `immich`, `hostapd`, `dnsmasq`, `frey-traefik` |
| 4th action within an hour | rate-limited |
| induced health regression | breaker trips, ntfy fires |
| kill switch set | every write verb refuses |

Run it before enabling any write verb, and after every change to the broker.
Acceptance for each phase stays the repo standard: deploy twice, second run
reports **0 changed**, then the check script.

## 9. Open decisions for your review

Marked **[DECIDE]** above, collected:

1. **Starting autonomy** — tiered auto-fix for the safe set from the start, or
   propose-everything for the first weeks and graduate verbs individually?
   (§5, §7 phase 6)
2. **Blast radius** — which subsystems get verbs at all? Proposal: media
   acquisition + monitoring in tier 1, media library + identity tier 2 only,
   networking never. (§5)
3. **AppArmor on the broker** — the one layer with a real downside on a
   console-less machine. Ship in complain mode first, or skip? (§3 M4)
4. **The LLM's role** — triage-only on top of deterministic scripts
   (proposal), decide-everything-from-the-menu, or incident-reports-only and
   never act? (§6)
5. **`/opt/frey/stacks/**`** — hard-denied to the agent (proposal), or mounted
   through a redaction filter so it can reason about compose state without
   seeing keys? (§3 M1)
6. **Where `<drafts>` lives** — a separate directory the agent owns and you
   promote from, or a folder inside the SilverBullet space? A folder inside the
   space is more convenient and means the agent's uid can write into notes
   territory; a separate directory keeps the write surface outside the notes
   entirely. Bears on constraint 2.
7. **The image inbox path**, and whether to build the Immich boundary now as a
   pre-emptive assert. Immich is not deployed — only its OIDC client exists, in
   `roles/identity/defaults/main.yml:252` — so the boundary would precede the
   thing it guards. Proposal: build it now; it is cheap, and an allowlist that
   already excludes Immich cannot fail open when Immich arrives.

## 10. What this plan does not do

- It does not give the agent a shell, `docker.sock`, or a generic command verb.
- It does not let the agent deploy. `ansible-playbook` stays yours.
- It does not touch the radios, the firewall, sshd, or `config.txt`.
- It does not attempt the NVMe fault, which it cannot survive.
- It does not read photos, secrets, or private keys.
- It does not write outside its drafts directory.
