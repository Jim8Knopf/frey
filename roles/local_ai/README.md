# Local AI

Local inference as a shared service. The llama.cpp chat UI and an
OpenAI-compatible API are served at `https://ai.hub.frey` behind Frey sign-in,
limited to `frey_admins` and `notes`. Inference runs entirely on the Pi; only
model downloads need internet.

Three interfaces share one model, and they share **one llama-server slot**:

| | |
| --- | --- |
| `ai.hub.frey` | the model's own chat UI, and the `/v1` API |
| `campaign.hub.frey` | the campaign assistant, which reads and writes the notes |
| `hermes.hub.frey` | Hermes Agent — slower, but a real agent. See below. |

This replaces the `campaign_ai` role. The role name, the module tag, the host
and the `identity_services` key all changed together, because the role asserts
its own access policy and fails its first task otherwise. An Ansible deploy
retires the old stack: it stops and removes the `frey-campaign-ai-*`
containers, deletes `/opt/frey/stacks/campaign-ai` and removes the old
download units. **The retired Qwen3 1.7B model file is deliberately left on
disk** at `/opt/frey/appdata/campaign-ai/models/` — 1.2 GiB that cost a slow
uplink to fetch. Delete it yourself when you are confident you will not want it
back.

## The model

Qwen3.5-4B, Unsloth Dynamic 2.0 4-bit (`UD-Q4_K_XL`), Apache 2.0. It is
**natively multimodal**: the `mmproj` file is what gives the same server
binary vision, so you can attach an image to a message. Expect mistakes and
review every draft — this is a 4B model, and the rules benchmark in
`docs/CAMPAIGN_ASSISTANT_PLAN.md` found its predecessor unreliable without
review.

Compatibility was verified against the pinned llama.cpp build before pinning
the model, because neither half is obvious:

| What | Value | Where it is supported in `b12019` |
| --- | --- | --- |
| model architecture | `qwen35` | `src/llama-arch.cpp` |
| vision projector | `qwen3vl_merger` | `tools/mtmd/clip-impl.h` |

Qwen3.5 reuses Qwen3-VL's merger, which is why vision works on a build whose
`clip.cpp` contains no string `qwen35` at all. If you move
`local_ai_llama_version`, check both again.

Speed on this hardware is set by file size, not thread count: generation is
memory-bandwidth-bound. **Measured on 2026-11-07: 2.70 tokens/s** — 260 tokens
in 96.2 s from a 29-token prompt, with two threads.

That is ~25% slower than the 3.5 tokens/s first estimated from the old 1.7B
figures. The estimate assumed ~10.5 GB/s of effective weight-read bandwidth;
this model actually achieves about **7.9 GB/s**. Larger models read more per
token than a simple scaling of a 1.7B measurement predicts, so treat 7.9 GB/s
as the number to project from — a 9B at 4 bits would be nearer 1.2 tokens/s
than the 1.6 originally guessed.

Threads buy *prompt* processing, which is compute-bound and the Pi 5's weak
axis — its A76 cores have no i8mm. The role uses two threads on purpose,
leaving cores for the gateway: on a Pi with no Ethernet and no console,
gateway responsiveness outranks inference speed.

Vision is correspondingly slow. An image becomes hundreds to low-thousands of
prompt tokens plus an encoder pass, so expect tens of seconds to a few minutes
per image. Fine for captioning a photo of a whiteboard; not interactive.

## The model registry

`local_ai.models` in `defaults/main.yml` is a registry, and
`local_ai.default_model` names the one llama-server loads. Each entry pins a
URL with an explicit revision and a SHA-256 for every artifact.

Adding a model is one entry; the role installs a manifest and enables a
download timer for it automatically. Registered models that are not the default
are downloaded and left on disk, ready for a `default_model` change or a future
model-swap layer. Switching the default is one variable and a redeploy,
provided the new model has finished downloading.

## Isolation

The model container has no Docker socket, no credentials, no notes, no photos
and **no external network** — `ai_private` is `internal: true`. Only the model
directory is mounted, read-only. It runs as uid 65534 with all capabilities
dropped, `no-new-privileges`, a read-only root filesystem and no published
ports. No agent tools or MCP servers are enabled. A minimal Traefik gateway is
the only thing connecting it to Frey's authenticated proxy.

Conversations may be stored in the browser; protect the device and clear its
site data when appropriate.

## The API, and a caveat worth knowing

`/v1/` is served, so the endpoint is OpenAI-compatible — but it sits behind
`authelia@file` forward auth, which answers an unauthenticated request with a
**302 to the login page**. A browser works. A script, an editor plugin or
another host gets HTML instead of JSON and will look like a broken API rather
than an auth failure.

Container-to-container consumers on `frey_proxy` bypass Authelia the way the
rest of Frey does. An off-Pi API client needs either an SSH tunnel or a
deliberate bypass rule scoped to `/v1/` with a bearer token — **which does not
exist yet and should not be added without a decision.** Do not expose an
unauthenticated inference API to the network.

## First deployment

The first deploy starts a background download of about **3.6 GB** — 2.9 GB of
weights plus a 672 MB vision projector. The UI returns an error until it
finishes. Each artifact is verified against its SHA-256 before being moved into
place, and a completion marker is written only when all of them pass.

```sh
systemctl status 'frey-local-ai-download@qwen35-4b.service'
sudo journalctl -u 'frey-local-ai-download@qwen35-4b.service' -n 30
ls -lh /opt/frey/appdata/local-ai/models/
```

A systemd timer retries an incomplete download after a failure or reboot, and
partial downloads resume rather than restart — which is what makes a dropped
campground uplink recoverable. Once the marker exists the timer's unit
condition stops matching, so **it will not restart a model you stopped on
purpose** in Dockge. Retry immediately with:

```sh
sudo systemctl start 'frey-local-ai-download@qwen35-4b.service'
```

## The observer

Phase 1 of `docs/LOCAL_AI_AGENT_PLAN.md`: a component that **reads and
explains, and cannot act**. There is no broker, no Docker socket, no shell and
no action verb anywhere in it. The limits are a property of what is mounted and
which networks it is on, not of the prompt.

It polls Alertmanager every five minutes. When an alert it has not seen before
is firing, it gathers evidence from Prometheus, Loki and the textfile
collectors, asks the local model to explain it, and writes a Markdown report
into its drafts directory. It also writes one daily summary. A report about a
**critical** alert is pushed to your phone; a warning is written silently,
matching Frey's two-severity convention.

Alertmanager is **polled, not configured to push here.** Adding a receiver
would put this component in the path of the notifications Frey already depends
on, and polling cannot break them.

### Its boundaries

The rule is **read broadly, write only to explicitly named paths**. Reading is
safe here because there is no egress; writing is what is capped.

| | |
| --- | --- |
| **writes** | exactly two: `/drafts` for reports, and `broker/req`, the only channel to anything privileged. Both as uid 10002 |
| reads | notes, media, photos, the stacks tree, textfile collectors, Prometheus, Loki, and `broker/res` — all `:ro` |
| networks | `ai_private` and `ai_observe`, **both internal** |
| never mounted | `/opt/frey/pki`, `.vault_pass`, the vaulted `secrets.yml`, `/etc/shadow`, the per-service `.*-keys.json` files, `docker.sock`, host `/etc` |

Photos are mounted read-only and listed before Immich exists, so the boundary
precedes the thing it guards: the agent can look at a photo and can never edit
or delete one. A read path that does not exist yet is skipped rather than
mounted, since Docker would otherwise create an empty directory for it.

One residual risk, stated plainly because it was a deliberate choice: the
rendered compose files under `/stacks` **do** contain *arr API keys, Authelia
secrets and the LLDAP admin password. Nothing can be exfiltrated — there is no
egress — but the model could quote one into a draft, and drafts are read on a
phone. Removing the single `/stacks` entry from `local_ai.observer.read_paths`
closes it; nothing else depends on it.

It has **no internet egress at all**, which is what makes broad read access
safe: there is nowhere to send anything, and its only output is a file you
read. Notifications therefore go through the existing alert relay, which
already owns ntfy delivery and queues messages on disk until an uplink
appears — rather than punching a hole in the network boundary.

`monitoring_internal` is **not** internal despite its name, which is why
`ai_observe` exists: Prometheus, Loki, Alertmanager and the relay join it as a
second network so the observer can reach them without inheriting their egress.
`local_ai` creates it and runs earlier in `frey.modules.enabled`; monitoring
joins it as external, guarded on `local_ai` being enabled so monitoring still
deploys with the module switched off.

Reports are deliberately **not** written into the notes space. The write
boundary is enforced by the read-only mount rather than by a path check, and
the observer has its own uid so a future read-write mount cannot silently
grant it notes access. Promote a report by hand when you want it in Notes.

### Reading the notes needs an ACL

The notes directory is mode 0700 owned by SilverBullet (uid 10001) and the note
files are 0600, so a read-only mount alone is not enough — the inode
permissions block it regardless of the mount. The role installs the `acl`
package and grants `u:10002:rX` recursively, plus a **default** ACL on
directories so notes created later inherit the grant. An ACL is used rather
than widening the mode because the mode is shared with everyone and the grant
should not be.

Capital `X` grants execute only on directories, so note files do not pick up a
pointless execute bit.

### How long a report takes, and why the evidence is trimmed

Measured 2026-11-07: an incident report took **9.5 minutes** end to end. Prompt
processing is the cost, not generation — it runs at **8.4–9.25 tokens/s** on
this Pi, and the untrimmed evidence came to about **5500 tokens**, which is ten
minutes before a single output token.

So the model's copy of the evidence is capped by a character budget
(`EVIDENCE_BUDGET_CHARS`, default 6000 ≈ 1500 tokens) and trimmed from the end,
where the long tail of log lines sits. **The report still records the full
evidence** — only the model's copy is cut, and the trim is stated in the
report rather than left silent.

One practical consequence: **restarting the observer cancels an in-flight
request.** `llama-server` logs `cancel task` and the report is lost. Redeploying
the role restarts it, so avoid redeploying while a report is generating.

## The broker

Phase 3: the only privileged thing the assistant can reach, and it exposes
**read verbs only**. It runs on the host, and **its channel is a directory
rather than a socket or a port** — because the agent container has no default
route and cannot reach the host on any port, which is deliberate and is what
makes its broad read access safe.

The agent writes a request into `broker/req`, which it can write; the broker
validates it and writes a response into `broker/res`, which the agent can only
read — so it cannot forge an answer to its own request.

| Verb | Returns |
| --- | --- |
| `unit_state` | systemd state for one allowlisted unit |
| `diagnostic` | output of one allowlisted read-only command |
| `container_logs` | tail of one allowlisted container's log |

**No Docker socket and no Docker CLI.** Container state already reaches the
agent from cAdvisor through Prometheus, and `container_logs` reads Docker's
JSON log files straight off disk — which grants no ability to start, stop or
exec anything, and still works when Loki is the thing that broke. Note that
the log files live under **`/opt/frey/docker/containers`**, not
`/var/lib/docker`: the NVMe migration moved Docker's data-root, and the old
path still exists and is empty.

Dispatch is an exact dictionary lookup, so an unknown verb has nowhere to go.
`restart_container`, `run_command`, `restart_service`, `reboot`, `write_file`
and `nmcli` are absent rather than refused.

### Write actions: the model proposes, you decide

`recreate_container`, `restart_container` and `rerun_unit` exist — and are
**not in the verb table**, so the agent cannot call them. The only path to one
is a proposal you approve by typing its id on the host. The write path has a
person in it by construction, not by policy.

That is deliberately stricter than `frey-self-heal`, which acts on its own.
The difference is what is being trusted: self-heal runs a fix *you wrote* for
a symptom a *tuned alert rule* matched. Here the model's judgement is the
input — and it has already produced one confident, well-structured, entirely
wrong diagnosis. Gating it costs nothing, because the known faults still
self-heal untouched; only novel cases wait for you.

```sh
sudo frey-broker-approve --list        # what is waiting, and why
sudo frey-broker-approve <id>          # allow it; runs within seconds
sudo frey-broker-approve --reject <id> # decline now
```

Ignoring a proposal declines it — they expire on their own. ntfy pushes each
one with the literal command to paste.

What may be targeted, and nothing else: `recreate_container` only
`frey-media-dns` (recreation is for a fault baked in at container creation, so
a restart would faithfully reproduce it); `restart_container` only the eight
stateless containers, which excludes every SQLite-backed service and
`frey-traefik`; `rerun_unit` only idempotent oneshots that already run on
timers, so running one early is indistinguishable from the timer firing.

**Approving takes an id and nothing else.** Execution re-validates the verb
and its target from scratch, so approval cannot smuggle a different action
than the one you were shown, and a target since removed from the allowlist
stops being executable.

### The deadman

Every executed action arms one. It records the health measured beforehand —
stopped containers among the watched set, plus firing alerts — and
`frey-broker-supervisor` re-measures after three minutes using the *same
code*, imported rather than reimplemented, because a deadman comparing two
different definitions of health is worse than none.

If either count rose, it **trips the kill switch first and notifies second**
— the order matters, because when there is no uplink the agent must still be
stopped. The broker then refuses every verb until you clear it. Being a
separate process is the point: the broker cannot suppress its own failure by
crashing, hanging, or choosing not to look.

**There is no automatic revert**, deliberately. A blind undo is itself an
unattended action taken while the system is already degraded, which is how one
fault becomes two. Every action here is reversible by hand.

A missing measurement never counts as a regression — a failed probe would
otherwise make every uplink outage look like a bad repair.

Health is **stopped containers plus critical alerts only**, and that matters.
The first live run defined it as *all* firing alerts and false-tripped: the
count went 2 → 3 right after re-running a metrics collector, which cannot
cause an alert. The warning tier flaps constantly here — the 5V rail sits
right at its threshold, container memory is high because the model is 4 GiB —
and `Watchdog` fires permanently by design. The breaker worked; the definition
of health did not.

### Why approval needs SSH

ntfy's action buttons cannot approve: Authelia forward auth answers any
non-browser POST with a 302 to the login page. The alternatives were a web
endpoint whose whole purpose is triggering privileged actions, or parsing
notes for approvals. SSH was chosen as the least surprising of the three. On a
phone that means an SSH client rather than a tap.

### Its confinement is systemd's, not its own code

AppArmor was the intent, but it is **disabled in this Pi's kernel** —
`/sys/module/apparmor/parameters/enabled` reads `N` and the tools are absent,
so enabling it needs a kernel command-line change and a reboot. systemd's
sandboxing gives the same guarantees with neither: `ProtectSystem=strict`
makes the whole filesystem read-only except `ReadWritePaths=` (the write
allowlist), `InaccessiblePaths=` makes every credential path **ENOENT even to
root**, `PrivateNetwork=yes` removes networking entirely, and
`CapabilityBoundingSet=` is empty.

That empty capability set has real teeth, and it caused the one bug worth
remembering: root without `CAP_DAC_OVERRIDE` obeys ordinary permission checks,
so the broker could not traverse a request directory owned by the agent at
0750 — and Python's `glob()` swallows that `PermissionError` and yields
nothing, so it ran happily, found no work and logged nothing at all. The fix
was group ownership, not handing the capability back.

Stop every verb with one file and no deploy:

```sh
sudo touch /etc/frey/broker-disabled   # every verb now refuses
sudo rm /etc/frey/broker-disabled      # and back
```

### Caveats

Every report is written by a 4B model. Verify every claim before acting on one;
the model is given evidence and asked to classify it, never to invent a fix,
and the system prompt forbids suggesting changes to networking, SSH, the
firewall or a deploy — none of which it could perform anyway.

**The first real report got the diagnosis wrong in an instructive way**, and the
system prompt now carries the corrections. It read `status="none"` — which
simply means *no healthcheck is defined* — as containers being in an unknown
state, then built a causal chain on it and concluded the 5V rail sag was
causing NVMe corruption. That is precisely the wrong answer `CLAUDE.md`
records: the NVMe dropouts are a **PCIe transport fault**, and power and APST
were both investigated and ruled out.

The lesson generalises. A 4B will assemble a confident, well-structured,
plausible story out of a misread label. What fixes it is not a bigger model but
**grounding** — the system prompt now states the hard-won facts about this
machine explicitly, including that unsafe-shutdown counts are cumulative
lifetime totals rather than live events. When a report is wrong, add the fact
it lacked rather than arguing with the model.

With no model downloaded the observer still runs and still records evidence;
the assessment section simply says the model did not answer. That is
deliberate: a monitoring component that refuses to run until everything else is
healthy is useless in exactly the situation it exists for.

## Hermes Agent

`https://hermes.hub.frey` runs [Hermes Agent](https://github.com/NousResearch/hermes-agent)
against the local model. It is a third interface beside the model's own chat UI
and the campaign assistant — not a replacement for either.

**It is usable, but it is slow, and the numbers matter more than the feature
list.** Measured on this Pi (`docs/LOCAL_AI_AGENT_PLAN.md` §6a):

| | prefill | time |
| --- | --- | --- |
| first turn on a cold slot | 4,070 tok | **11.5 min** |
| each turn after that | 489 tok | **~1.8 min** |

The deployed configuration is lighter than that measurement — `hermes
prompt-size` reports **~17.4 KB (~3,900 tokens)** against the ~57.9 KB a
default install sends — so treat those figures as the pessimistic end.

### Why it is slow, and the one setting that decides it

Hermes sends a large prompt before you type anything, and on this hardware
prompt processing is the binding constraint (and gets *slower* as context
grows). `hermes prompt-size` says where it goes, and the obvious suspect is
innocent:

```
tool schemas (21 tools)   39,999 B   <- 69% of it
stable (identity/skills)  12,177 B
volatile (memory/time)     5,112 B
```

The 44 bundled skills cost only **70–88 B each** of always-on index; their
bodies are read lazily. **Tool schemas are the cost**, so
`local_ai.hermes.toolsets` is the setting that decides whether this is usable
at all. It is `[file]`, which takes the prompt from 12,800 to ~3,900 tokens —
the difference between about an hour to first token and about eleven minutes.

Adding a toolset is paid for twice: once in the cold prefill, and again in
every warm turn, because the re-evaluated tail begins at the first byte that
differs from the cached prefix.

### One slot, shared three ways

`llama-server` runs with `parallel_slots: 1`, because two slots split two
threads and collapsed to 0.59 tok/s. The practical consequence:
**`ai.hub.frey`, `campaign.hub.frey` and `hermes.hub.frey` evict each other's
cached prompt.** Alternating between the model's chat UI and Hermes means
paying Hermes's 11.5-minute cold start again. Staying in one of them is cheap.

A related hazard, and not Hermes's fault: **a cancelled request does not free a
slot.** An abandoned turn was observed still occupying the model 4.6 minutes
after its cancel, with everything else queued behind it. If the stack seems
wedged, check `docker logs frey-local-ai-model` for a task that was cancelled
but never released.

### Sign-in

`auth: oidc`, not forward auth. Hermes is a real OIDC relying party and
*requires* an auth provider as soon as it binds anything but loopback, so it
logs in against Authelia itself — one login, not two. Access is still
`identity_services.hermes.groups`, which Authelia applies before issuing a
token, so the missing forward-auth middleware does not widen who gets in.

`ctx: 65536` is **mandatory while this is enabled**: Hermes enforces a 64,000
minimum in its own code. Disabling Hermes allows `20480` / `6g` again and
reclaims about 2 GiB.

### Things that cost hours, recorded so they cost nobody else any

- **`HERMES_PROVIDER` is not a knob.** The provider comes from `config.yaml`
  (`model.provider`), which the role templates.
- **`provider: auto` plus any `OPENAI_*` variable resolves to `openai-api`**,
  whose transport is the Codex **Responses** API — `/v1/responses`, which
  llama.cpp does not implement. It does not fail as a 404: the call produces
  no events and dies as *"Non-streaming API call timed out after 240s"*, three
  times, then trips a stale-attempt breaker. Nothing names the cause.
- **A `context window of 20,480` error may be about nothing real.** The stock
  config ships `anthropic/claude-opus-4.6`; that error described the stored
  placeholder, not the served model.
- **`provider: llamacpp` is for a server Hermes supervises itself** and raises
  `LocalRuntimeUnavailableError` against an external one. Use `custom`.
- **Do not set `user:` on the container.** s6-overlay's preinit then dies in a
  restart loop (`/run belongs to uid 0 instead of 10003`), and `init: true`
  only hides it by making s6 skip itself — which leaves the agent running as
  root. Pass `HERMES_UID` / `HERMES_GID` instead, which the image documents.
- **`HERMES_HOME` must be `0700`** or Hermes exits with
  `unsafe_control_permissions` before reading any configuration.
- **`dashboard.public_url` is required behind Traefik.** Without it Hermes
  builds an `http://` redirect URI from the proxy's plain-HTTP hop, Authelia
  rejects it as a mismatch, and the error appears in *Authelia's* log. The
  wrong fix is registering an `http://` callback; that would put the
  authorization code on the wire unencrypted.
- **`SSL_CERT_FILE=/frey-ca.crt`** is what makes httpx trust the Frey CA for
  OIDC discovery.

## Verifying

From the Frey project directory on the admin computer:

```sh
bash scripts/local-ai-ready-check.sh     # download, readiness and isolation; exit 2 = still downloading
bash scripts/local-ai-check.sh           # anonymous access is redirected
bash scripts/local-ai-observer-check.sh  # tries to break every observer boundary
bash scripts/local-ai-broker-check.sh    # asks the broker for things it must refuse
```

`local-ai-observer-check.sh` is the important one. It attempts egress, attempts
to write outside `/drafts`, attempts a traversal out of the notes mount and
stats every forbidden path — and requires each attempt to fail. Forbidden paths
must report **ENOENT, not EACCES**: that is the difference between "not
mounted" and "mounted but denied", and only the first is a real boundary.

Neither tests sign-in, vision, or the quality of an answer. The real
acceptance test is a second deploy reporting **0 changed**, then these scripts,
then a real question you check yourself.

Deploy with:

```sh
ansible-playbook playbooks/site.yml --tags pki,identity,local_ai,dashy,monitoring
```

`pki` and `identity` are in that list because the host changed: the
certificate SAN and Authelia's rules both derive from `identity_hostnames`, so
they must be deployed with — or before — the role. On Android, trust the Frey
CA and use the browser.

## Resource notes

The model container is capped at 2 CPUs and 5 GiB. The host reported 8 GiB
available on 2026-11-07, so that leaves roughly 3 GiB of headroom — re-check
`free -g` before raising `ctx` or adding a second resident model. Context is
8192, far below the model's 262144 maximum, deliberately: a 262K-capable model
with a large KV cache will exhaust RAM long before it exhausts context.
