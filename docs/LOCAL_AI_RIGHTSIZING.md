# Local AI, rightsized — reassessment 2026-11-18

`LOCAL_AI_EVALUATION.md` (2026-11-07) asked which model and runtime to serve.
That question is settled and the answers held up. This document asks the one
that was never asked: **what is local AI on Frey actually for, and is the
deployed shape delivering it?**

Measured on the Pi on 2026-11-18, against the live deployment. Every number
below was read off the running host, not estimated.

## Status — applied in config 2026-11-19, NOT YET DEPLOYED

The recommendation in §3 has been implemented on this branch. A
`--check --diff` run passes (`failed=0`) and renders exactly:

| Change | From | To |
| --- | --- | --- |
| `lfm25-8b-a1b.ctx` | 65536 | **16384** |
| `lfm25-8b-a1b.mem_limit` | 9g | **6g** |
| `lfm25-8b-a1b.cache_ram` | 1536 | **512** |
| `observer.enabled` | true | **false** (service removed from compose) |
| `hermes.enabled` | true | **false** (service removed from compose) |

Plus a new `Remove the containers of disabled components` task, because an
`enabled: false` without it leaves a compose **orphan** running forever, and a
skip guard in `scripts/local-ai-observer-check.sh`.

**The deploy itself has not been run** — it needs a human:

```bash
ansible-playbook playbooks/site.yml --tags local_ai > /tmp/local-ai-deploy.log 2>&1
```

Then run it a second time for the 0-changed acceptance test, and confirm the
memory actually came back with the commands in **Acceptance test** below. The
projections in §3 are projections until that output exists.

`campaign.enabled` is deliberately left **true**: `frey-campaign-agent` holds
7.95 MiB, has logged nothing since 2026-11-11, is genuinely on-demand rather
than a poll loop, and does not pin the context window. It costs nothing worth
reclaiming and was not part of the measured problem.

## The verdict in one line

**The hardware is adequate and the model choice was right. The *workload* is
wrong.** Eleven days of operation produced 302 reports nobody read, zero human
conversations, and a model whose own weights have been evicted from RAM by a
context window reserved for a component that does nothing.

The fix is not a bigger model, a smaller model or a faster runtime. It is to
stop running local AI as a service that works on its own, and run it as a tool
that is picked up when the uplink is gone.

## What is actually deployed

The Pi is serving **LFM2.5-8B-A1B UD-Q4_K_XL** at 64K context, with Hermes
Agent and the read-only observer alongside it. None of that is on `new` — see
§5, it is the most urgent item here.

```
-m LFM2.5-8B-A1B-UD-Q4_K_XL.gguf --ctx-size 65536 --parallel 1
--threads 2 --threads-batch 3 --cache-ram 1536 --cache-reuse 256
--spec-type ngram-simple --cache-type-k q8_0 --cache-type-v q8_0 -fa on
--reasoning off --jinja
```

## 1. What the measurements say

### The host is oversubscribed, and local AI is why

| Reading | Value |
| --- | --- |
| RAM total / available | 16,218 MB / **2,357 MB** |
| Swap used | **2,046 of 2,047 MB — 100 %** |
| Load average (4 cores) | 3.80, 2.97, 3.61 |
| Uptime | 17 d 10 h |

`llama-server` is the single largest consumer on the machine, and the shape of
its memory is the finding that matters:

| `smaps_rollup` for `llama-server` | Value | What it is |
| --- | --- | --- |
| Rss | 6,419 MiB | |
| **Private_Clean** | **1,731 MiB** | file-backed — the mmap'd weights |
| **Private_Dirty** | **4,687 MiB** | anonymous — KV cache, prompt cache, buffers |
| **Swap** | **1,091 MiB** | already paged out |

The model file is **4.98 GiB**. Only **1.73 GiB of it is resident.** The other
~3.2 GiB has been evicted, because 4.69 GiB of non-reclaimable anonymous
memory — the 64K KV cache plus `--cache-ram 1536` — outbid it for RAM, and
then 1.09 GiB of that went to swap anyway.

**So every forward pass re-reads most of the weights from the NVMe.** That is
visible in the logs as prefill degrading within the same workload:

```
19.37  19.44  19.29  19.38  19.26  18.99  19.19  19.14  19.65  16.66  19.26  12.14   tok/s
```

It is also the one thing on this host that should never be casually accepted:
sustained paging against the drive that leaves the PCIe bus
(`frey-power-loss-events`, `nvme-smart-blind-to-dropouts`). Inference is now
partly disk-bound on the component with the open hardware fault.

### Utilisation: 100 % robot, 0 % human

In the last **72 hours** `llama-server` accepted **91 requests**. Every single
one was the observer:

- prompt size on all of them: **2,566–2,599 tokens**
- `n_gen` maximum: **exactly 499** — the observer's `max_tokens: 500`

Per `one-model-slot-is-the-contended-resource`, that signature *is* the
observer. There is no chat traffic in the trace at all.

- **Hermes made 0 requests in 72 h.** Its log for the last 24 h contains
  **457 lines of `system memory pressure is elevated; limiting to at most 1
  new worker` and nothing else.** It is holding 347 MiB to refuse to work.
- **The observer wrote 302 drafts** (6.5 MB) between 2026-11-07 and
  2026-11-18. None have been promoted or deleted. Eight were written today
  between 14:17 and 20:44, each taking 3½–5 minutes of wall time.
- At the moment of checking there were **no failed units and no unhealthy
  containers** — so a good share of those 302 reports narrate flapping that
  resolved itself.

### The prompt cache is wiped on every request

`f_keep = 0.161–0.168` on every recent request (`f_sim_best ≈ 0.20`). Near 1.0
means the prefix was reused; 0.16 means it was thrown away. So each observer
report pays the **full** prefill — 130–211 s for ~2,570 tokens — and then
generates at 4.2–6.1 tok/s.

This is the mechanism that makes the observer costly rather than merely
wasteful: it does not just occupy the slot for ~4 minutes, it **evicts whatever
prefix was cached there.** A human turn landing after it is a cold turn.

## 2. Why nothing human ever used it

This is the part worth being honest about. The capability is real — the MoE
upgrade was a genuine ~2× win, and `frey-local-model-measured-limits` records
Hermes answering correctly in ~2 min per warm turn. But in eleven days nobody
reached for it, and the reason is structural, not a usability bug:

**A 2-minute-per-turn assistant does not compete with the phone in your
pocket.** Whenever there is an uplink, a frontier model is faster, better and
already there. Local inference on this machine has exactly one unbeatable
situation: **parked, off-grid, no uplink.** Then 5 tok/s beats nothing, and
nothing else is available at any price.

Every autonomous use — the observer's poll loop, Hermes's kanban dispatch —
has produced zero realised value and measurable cost. Every on-demand use is
untested because the autonomous ones consumed the capacity.

## 3. Recommendation — on demand, not on duty

Keep a single model, served on demand, sized so it stays in RAM. Retire
everything that runs on its own.

| Keep | Retire |
| --- | --- |
| LFM2.5-8B-A1B — prefill ~19 tok/s is 2–3× Qwen3.5-4B; the right call | **The observer** — 100 % of load, 302 unread drafts, wipes the cache |
| The `qwen35-4b` registry entry and its `mmproj` as the vision fallback | **Hermes** — 0 requests in 72 h, 457 refusals in 24 h, 347 MiB |
| The chat UI at `ai.hub.frey` behind Authelia | The 64K context floor that Hermes alone requires |
| `/v1` on `frey_proxy` for the laptop when off-grid — the actual use case | `--cache-ram 1536`, which outbids the weights it exists to serve |
| The broker's read verbs and propose-only writes — good design, keep it idle | |

### What this buys, quantified

Dropping Hermes releases the context floor — `ctx: 65536` is not a preference,
**Hermes enforces a 64,000 minimum in code** (commit `f6444f7`), so it cannot
be lowered while Hermes stays. With it gone:

- `ctx` 65536 → **16384** cuts the KV cache roughly 4× — of the ~4.2 GiB of
  anonymous memory that is KV plus buffers, about **3 GiB** comes back.
- `--cache-ram` 1536 → **512** returns another ~1 GiB of contention.
- Together that should let the **full 4.98 GiB of weights stay resident**, end
  the swapping, and hold prefill at ~19 tok/s instead of decaying to 12.
- `mem_limit` 9g → **6g**, and ~350 MiB back from Hermes, ~31 MiB from the
  observer.

Expected end state: local AI as the largest single consumer still, but ~6 GiB
resident and **not swapping** — against 7 GiB today that *is*.

**These are projections from the measured split, not measurements.** Per
`CLAUDE.md`'s own rule, confirm them by reading `smaps_rollup` and
`memory.peak` after the change rather than assuming.

## 4. Steps, in order

1. **Merge the branch first** (§5). Everything below edits config that only
   exists there.
2. **Retire the observer.** `local_ai.observer.enabled: false`.
   **Trap:** the compose template gates the observer service, but the role has
   **no `state: absent` cleanup for it** — so the flag alone leaves
   `frey-local-ai-observer` running as a compose orphan indefinitely. This is
   the identical trap the role's own `legacy_containers` list exists to handle
   for `frey-campaign-ai-*`. Add `frey-local-ai-observer` to that list, or
   remove it by name once. Keep `/drafts` on disk; it is the evidence trail.
   Retire `scripts/local-ai-observer-check.sh` in the same commit, or it
   becomes a check asserting the health of a component you removed.
3. **Decide Hermes** (§6). If retired: stop and remove the container, drop its
   profile, then apply the context and memory changes in §3.
4. **Re-measure**, and only then judge. `smaps_rollup` for `llama-server`
   (expect Swap ≈ 0 and Private_Clean ≈ 4.9 GiB), `free -m`, and a timed
   request from a cold slot and a warm one.
5. **Leave the §7a escalation unbuilt.** The design in
   `LOCAL_AI_AGENT_PLAN.md §7a` is sound and its gate is well reasoned, but it
   re-creates an autonomous consumer of the one slot. Nothing measured here
   argues for building it; the observer it replaces produced 302 reports and
   zero actions. Build it when something concrete asks for it.

## 5. The urgent item, independent of every recommendation above

**Everything described in this document is unmerged.** Head `6e1a60c` on
`docs/local-ai-eval` (pushed as `origin/docs/local-ai-eval`) and on the
local-only `feat/hermes-usability` — about 24 commits: the MoE upgrade, the
prompt-cache cap, Hermes, the observer's `model_busy()` deferral, the §7a
design. `new` still has `default_model: qwen35-4b` and knows nothing about any
of it.

The Pi is running branch state. **The next deploy from `new` reverts the model
to Qwen3.5-4B, deletes Hermes, and restores the observer's un-deferred poll
loop** — per `deploys-from-different-branches-revert-each-other`, the Pi's
state is whichever unmerged branch ran last.

This is the costliest recurring failure in this project
(`fixes-stall-unmerged-on-branches`) and it is live right now. Merge it before
touching anything else, and verify per commit rather than by ancestry of the
branch head:

```bash
git merge-base --is-ancestor 6e1a60c new && echo merged || echo NOT merged
```

## 6. Open decisions

- `[DECIDE] Retire Hermes?` **Recommended: yes.** It is the only thing holding
  `ctx` at 64K, which is what evicted the weights, and it has served 0 requests
  in 72 h while logging 457 refusals in 24. Against: it is the only path to
  tool-use and the broker, and `f6444f7` deliberately committed to it. If it
  stays, accept the swapping or raise `mem_limit` past 9g — and the honest
  version of "keep it" includes actually using it for a week.
- `[DECIDE] ctx once Hermes is gone.` **Recommended: 16384.** A window you
  cannot afford to fill buys nothing, and prefill at ~19 tok/s makes 16K about
  14 minutes of prompt — far more than any on-demand question needs.
- `[DECIDE] Keep serving the 8B MoE, or fall back to Qwen3.5-4B?`
  **Recommended: keep the MoE.** It is 2–3× on prefill *and* faster on
  generation; its only cost was the context it was asked to carry. The 4B's
  2.9 GB file would fit more comfortably, which is the argument for revisiting
  if the host stays this tight after Immich settles.
- `[DECIDE] Vision.` **Correction to an earlier draft of this document:** the
  served MoE carries `enable_vision: false`, because **no projector is
  published for LFM2.5-8B-A1B**. The `mmproj-F16.gguf` on disk belongs to
  `qwen35-4b`, so vision is not a free addition to the current model — it means
  switching `default_model` back to the 4B for that request. Both model files
  are already downloaded and registered, so the switch is one variable, but it
  is a switch and not a toggle. Recommended: leave vision off, keep the 4B
  entry registered as the vision fallback, and revisit only if captioning turns
  out to be something you actually reach for.

## 7. What not to do

- **Do not add a bigger model.** The constraint measured here is RAM residency
  and slot contention, not model capability.
- **Do not add a second slot.** `parallel_slots: 1` is correct; two slots split
  two threads and measured 0.59 tok/s.
- **Do not fix the observer's quality by prompting harder.** Its test concluded
  on 2026-11-08: a 4B assembled a confident wrong causal chain from one misread
  label. That result is worth keeping; the component is not.
- **Do not leave it swapping while assuming the cap protects you.**
  `mem_limits starve rather than kill` — a cap at its ceiling throttles
  silently, and here it surfaced as prefill decaying from 19 to 12 tok/s with
  every container healthy throughout.

## Acceptance test

Per `CLAUDE.md`: deploy twice, second run reports **0 changed**, then
`scripts/local-ai-check.sh`. Specific to this change, and the part the check
script does not cover:

```bash
# weights resident, nothing swapped
p=$(ps -eo pid,rss,comm --sort=-rss | awk '/llama-server/{print $1; exit}')
sudo awk '/^Private_Clean|^Private_Dirty|^Swap:/{print $1, int($2/1024)" MiB"}' /proc/$p/smaps_rollup

# the cache is actually being reused — f_keep near 1.0, not 0.16
sudo docker logs frey-local-ai-model | grep -oE 'f_keep = [0-9.]+' | tail

# and nothing is calling it but you
sudo docker logs --since 24h frey-local-ai-model | grep -c launch_slot_
```
