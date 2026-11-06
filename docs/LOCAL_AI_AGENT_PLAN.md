# Local AI agent plan — a self-healing assistant with hard limits

Status: **proposal, nothing deployed.** Builds on `docs/LOCAL_AI_EVALUATION.md`
and extends `docs/CAMPAIGN_ASSISTANT_PLAN.md` phase 4 from "restricted draft
agent" to "agent that helps keep Frey healthy".

Decisions still open are marked **[DECIDE]** and collected in §9. Everything
else is a proposal you can correct.

## 1. The four constraints this plan is built around

Given directly:

1. **Broad read, hard-capped write.** The agent may read nearly everything; what
   it may *change* is tightly bounded.
2. **Writes begin in the notes only.**
3. **Immich and the photo directories are hard-blocked**, at system level, not
   by instruction.
4. **Networking is hard-blocked, to prevent bricking.**

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

| Path | Agent | Broker | Why |
| --- | --- | --- | --- |
| `/opt/frey/appdata/silverbullet` | **ro** | — | notes, uid 10001 |
| `<drafts dir>` | **rw** (uid 10002) | — | the only write surface |
| `/opt/frey/data/media` | **ro** | — | media metadata, read freely |
| `<image inbox>` | **ro** | — | one drop folder, not a library |
| `/opt/frey/metrics/textfile` | **ro** | — | the collector seam |
| `/opt/frey/appdata/local-ai/models` | **ro** | — | weights |
| **photos / Immich library** | **never** | **never** | constraint 3 |
| `/opt/frey/pki` | **never** | **never** | 0700, holds the root private key |
| `.vault_pass`, `inventory/.../secrets.yml` | **never** | **never** | vault |
| `/opt/frey/stacks/**` | **never** | ro | rendered compose carries *arr API keys, Authelia secrets, the LLDAP admin password **[DECIDE]** |
| `/var/run/docker.sock` | **never** | ro | the whole point of the split |
| host `/etc`, `/boot`, `/root` | **never** | **never** | sshd, firewall, `config.txt` |
| host root filesystem | **never** | **never** | — |

Note the asymmetry on `/opt/frey/stacks/**`: it is excluded from the agent not
because of exfiltration risk — there is no egress, see M6 — but because the
agent would otherwise quote an API key into a draft note, and that draft syncs
into a browser copy on your phone.

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

### M4 — Kernel MAC on the broker.

The broker is the one component whose compromise is serious, because it holds
`docker.sock`. It gets an AppArmor profile denying the photo paths, `/opt/frey/pki`,
`.vault_pass` and `/etc/shadow` outright, so a future compose-file mistake
cannot silently widen access even if M1 is misconfigured.

The honest cost: **this repo has no AppArmor or seccomp anywhere today**, and a
wrong profile denies silently on a machine with no console. Mitigation is to
ship it in complain mode first, read the denials out of Loki, and only then
enforce. **[DECIDE]** — this is the one layer with a real downside.

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

**Phase 2 — deterministic self-healing, no LLM.** Turn the known faults in §5
into scripts and timers. Independently valuable; this is the catalogue.

**Phase 3 — broker with read verbs only, plus the denial test suite.** Build
the broker, expose only reads, and prove every limit in §3 holds before a
single write verb exists (§8).

**Phase 4 — tier-1 write verbs, deadman, breaker, kill switch.** One verb at a
time, starting with `recreate_container(frey-media-dns)` — the most frequent
fault and the most clearly reversible.

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
