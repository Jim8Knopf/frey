# Local AI evaluation, 2026-11-07

Evaluates generalising `campaign_ai` from a single-purpose campaign chat into a
shared inference service, renaming it, and the specific technologies asked
about: llama.cpp, speculative decoding, image recognition, a Pi coding agent,
Unsloth, Strata, and whether Qwen still has the right models.

Web-sourced facts were checked on 2026-11-07 and are dated below. Performance
figures labelled *estimate* are derived from this repo's own two measurements,
not from new runs on Frey. Nothing here has been deployed.

## 1. What is deployed, and what the repo already proved

`roles/campaign_ai` runs llama.cpp `server-b12019` serving **Qwen3 1.7B
Q4_K_M** behind `authelia@file` at `campaign-ai.hub.frey`, restricted to
`frey_admins` and `notes`. The model container has no Docker socket, no
credentials, no notes mount and no external network; only `models/` is mounted,
read-only. 2 CPUs, 3 GiB, `--threads 2`, `--ctx-size 8192`.

Two findings in `docs/CAMPAIGN_ASSISTANT_PLAN.md` and
`docs/CAMPAIGN_AGENT_EVALUATION.md` decide most of this evaluation:

- **The binding constraint is model quality, not speed.** On 2026-11-02 the
  deployed model answered six real rules questions in 19.64–48.40 s each. It
  contradicted itself about failed evasion, missed the long-rest contradiction
  and did not flag the untrained-skill ambiguity. The recorded verdict: *"not
  reliable for rules decisions without review."* On the synthetic note-update
  prompt it attributed an existing page fact to the wrong source. These are
  **capability failures at 1.7B**, and no amount of tuning the runtime fixes
  them.
- **There is headroom to spend.** *"The Pi has approximately 12 GiB available
  RAM in the current configuration."* The container is capped at 3 GiB and 2 of
  4 cores. The deployment is using roughly a quarter of the machine to run a
  model that is too small to trust.

So the highest-value change is a bigger, newer model — not a faster runtime.

### Measured baseline, for scaling estimates

| Run | Model | Threads | Result |
| --- | --- | --- | --- |
| 2026-11-01 | Qwen3 1.7B **Q8_0** (~1.83 GB) | 2 | 6.1 tok/s, 2.185 GiB resident |
| 2026-11-02 | Qwen3 1.7B **Q4_K_M** (1.28 GB) | 2 | 250 tok in 19.6–48.4 s (~8 tok/s), 2.5/3 GiB, 60.6 °C |

Both imply an effective weight-read bandwidth of **~10–11 GB/s** on two
threads. Token generation on this machine is memory-bandwidth-bound, which
means two things that recur throughout this document:

- **Generation speed is set by model file size**, roughly
  `tok/s ≈ 10.5 / size_in_GB`. Choosing a quant is choosing a speed.
- **More threads will not fix generation.** Raising `--threads` past 2 buys
  little on a bandwidth-bound workload; it buys a lot on *prompt processing*,
  which is compute-bound and is the thing that will hurt as contexts grow.

The Pi 5's Cortex-A76 cores have dotprod and fp16 but **no i8mm and no SVE**,
so llama.cpp's fastest ARM quant kernels are unavailable. Prompt processing is
correspondingly weak and is the real ceiling on retrieval, vision and anything
agentic.

## 2. Verdict summary

| Topic | Verdict | Why |
| --- | --- | --- |
| Generalise the module | **Yes, and it is already on plan** | The plan's own goal says the assistant *"should later support other workspaces"*. Ship an inference *service*, keep chat as one client. |
| Rename | **Yes — `local_ai`, host `ai.hub.frey`** | Every sibling role is named functionally. `campaign_ai` is the only role named after a use case. |
| llama.cpp | **Keep. Now non-optional** | Qwen3.5 GGUFs need separate `mmproj` vision files, which Ollama cannot load. The existing choice turned out to be the correct one. |
| Qwen | **Yes — but upgrade two generations, to Qwen3.5** | Qwen3.5-4B is natively multimodal, Apache 2.0, and +9 Intelligence Index over Qwen3-4B, which already far exceeds the deployed 1.7B. |
| Unsloth **quants** | **Adopt now** | UD-Q4_K_XL is better quality at similar size. On a bandwidth-bound Pi, quality-per-byte *is* quality-per-token/s. |
| Unsloth **fine-tuning** | **No, and not needed** | Requires CUDA; cannot run on a Pi. Retrieval plus a system prompt beats a LoRA for campaign facts anyway. |
| Image recognition | **Yes, nearly free — with a caveat** | One `mmproj` file on the model you are already running. But it is three different wants, and only one is cheap. |
| Speculative decoding | **Measure last, do not assume** | Generic advice says CPU gains are small; the arithmetic for a 0.8B/4B pair on *this* machine says 1.5–2× is plausible. Unresolved without a run. |
| Pi coding agent | **No** | Prompt processing makes it unusable, and a model that can edit `network_gateway` is the exact brick-the-van risk `CLAUDE.md` is built around. |
| Strata | **Not yet** | Solves tool overload. Frey has zero agent tools enabled. Revisit if a local agent ever exceeds ~20 tools. |

## 3. Naming

`campaign_ai` is the only role in the repo named after a *use case*. Every
other role is named after a *function*: `network_gateway`, `service_proxy`,
`media_library`, `media_acquisition`, `security_baseline`, `frey_pki`,
`rpi_nvme`, `monitoring`. The mythology lives in the product name (Frey,
FreyHub), not in role names.

**Recommendation: role, module key and tag `local_ai`; host `ai.hub.frey`.**

`local_ai` says what it is (local inference, as opposed to a cloud API), reads
correctly next to `media_library` in `frey.modules.enabled`, and does not
promise agents it does not have. `ai.hub.frey` is short enough to type on a
phone, which matters because the phone is the primary client.

Considered and rejected:

- `mimir` — semantically perfect (a preserved head consulted for counsel of
  uncertain reliability is an unusually honest name for a 4B model). **Rejected
  because Grafana Mimir is a metrics store and Frey runs Grafana and
  Prometheus.** A `mimir` role in a repo with a `monitoring` role is a
  collision waiting to confuse someone at 2 a.m.
- `kvasir` — Norse, knowledge incarnate, no software collision known. Viable as
  a *hostname* flourish (`kvasir.hub.frey`) if you want one, but it fails the
  phone-typing test and tells a guest nothing.
- `huginn`/`muninn` — thought and memory, and the pair maps beautifully onto
  inference and retrieval if a vector store is ever added. Collides with the
  Huginn automation project, and is too cute for a role name.
- `assistant`, `inference`, `ai_inference` — accurate but either vague about
  locality or awkward in the registry.

### Rename is cheap but touches more than the role

Renaming is mechanical, and because `playbooks/site.yml` knows nothing about
any service, the blast radius is a known list of files:

- `roles/campaign_ai/` → `roles/local_ai/`
- `inventory/group_vars/all/main.yml` — the `enabled` entry and the `available`
  registry key plus its tag
- `inventory/group_vars/all/identity.yml` — the `identity_services` key and its
  `hosts: [campaign-ai]`
- `inventory/group_vars/all/images.yml` — `campaign_ai_llama_version`
- `/etc/systemd/system/frey-campaign-ai-download.{service,timer}`
- `scripts/campaign-ai-check.sh`, `scripts/campaign-ai-ready-check.sh`
- `roles/dashy` tile, and any monitoring target or dashboard referencing the host

Three traps specific to this repo:

- The old systemd units **will not be removed by renaming the templates.** Add
  an explicit `state: absent` cleanup for
  `frey-campaign-ai-download.{service,timer}`, or the Pi keeps a stale timer
  pointing at a path Ansible no longer manages.
- `roles/campaign_ai/tasks/main.yml` asserts its own access policy against
  `identity_services.campaign_ai`. That assert is good and should be kept, but
  it means the identity key and the role name must be renamed **in the same
  commit** or the role fails its first task.
- Changing the host changes the certificate SAN and Authelia's rules; deploy
  `pki,identity` with the new name before or with `local_ai`, per the existing
  module order.

The old `campaign-ai.hub.frey` can keep working by listing both hostnames, but
since this is a new, lightly used service, accepting the break is simpler.

## 4. Generalising: ship an inference service, not a chat app

The current role bakes one model, one hostname, one access policy and one
purpose into the compose file. The generalisation that matters is not "add more
features to the chat" — it is **inverting the dependency**: expose a stable
OpenAI-compatible endpoint and let the chat UI be one client among several.

That single change serves every use the plan foresees — rules Q&A, note
drafting, transcription summarising, image captioning, embeddings for search —
without the role learning anything about any of them.

### Concrete shape

- **`local_ai.models` as a registry, not a scalar.** Each entry carries
  `file`, `url`, `sha256`, optional `mmproj`, `ctx`, `threads`, `aliases`.
  The existing download pattern generalises directly to a systemd *template*
  unit, `frey-local-ai-download@.service`, instanced per model — which also
  gives you per-model retry and per-model status for free.
- **One endpoint, many models, loaded on demand.** 12 GiB will not hold a 4B
  chat model, a vision model and an embedding model resident simultaneously
  alongside Jellyfin and the *arrs. Two options, both OpenAI-compatible:
  - `llama-server`'s **router mode**, which needs no new dependency, or
  - **llama-swap** (Go, single binary, single config, no external deps),
    which adds per-model TTL idle-unload and `/running` plus
    `POST /api/models/unload`. Idle-unload is the feature that makes a
    multi-model Pi honest: nothing holds RAM it is not using.

  **Constraint:** llama-swap can drive backends either by spawning processes or
  via Docker. It must be the **process-spawning** mode. The Docker-socket mode
  violates the plan's explicit *"Deny AI access to … the Docker socket"* and
  would hand the model host-level control.
- **Keep the isolation exactly as it is.** The `ai_private` internal network,
  `cap_drop: [ALL]`, `read_only: true`, `user 65534`, read-only model mount and
  the minimal Traefik gateway are the best-designed part of this role. A
  generalised module should widen *what it can answer*, never *what it can
  reach*. Note that `--jinja` plus a model-supplied chat template means the
  model file controls template rendering; keep the template pinned with the
  model's SHA-256, as the role already does.

### The gotcha that will bite first

**`authelia@file` forward auth will break every non-browser client.** Forward
auth answers an unauthenticated request with a 302 to the login page, so a
script, an editor plugin or another container calling `/v1/chat/completions`
gets HTML, not JSON — and will look like a broken API rather than an auth
failure. Any general-purpose endpoint needs a deliberate second path:

- container-to-container consumers reach it on `frey_proxy` directly and never
  traverse Authelia, which is how the rest of Frey already works;
- off-Pi clients need either an Authelia bypass rule scoped to `/v1/` with a
  bearer token the role issues, or an SSH tunnel.

Respect the stance already recorded in the plan: *"do not expose an
unauthenticated inference API to the network."* `scripts/campaign-rules-benchmark.py`
already enforces loopback-only for this reason.

### What stays single-purpose

Campaign-specific prompts, the rules benchmark and the idea workflow are
*content*, not infrastructure. They belong where they are — in `docs/` and the
SilverBullet space — and should not move into the role. The role should ship no
campaign knowledge at all once renamed.

## 5. Models: Qwen is still the right family, two generations newer

**Qwen3.5 Small Series — 0.8B, 2B, 4B, 9B — was released 2026-03-02**, after
the deployed model was chosen. Checked 2026-11-07:

- **All four are natively multimodal with vision.**
- **Apache 2.0**, 262K context (extendable to 1M via YaRN), 201 languages.
- Reasoning is **hybrid**, and the small series ships with thinking *disabled
  by default* — which matches what the role already does with
  `--chat-template-kwargs '{"enable_thinking":false}'`.
- Artificial Analysis Intelligence Index: 9B = 32, 4B = 27, 2B = 16, 0.8B = 9.
  The 9B is *"roughly double the next closest models under 10B"*; the 4B is
  **+9 over Qwen3-4B**, and the 2B scores MMLU-Pro 79.6.
- On MMMU-Pro, *"Qwen3.5 9B (69%) and 4B (65%) lead all sub-15B models."*

The deployed Qwen3 **1.7B** sits below Qwen3-4B, which itself sits 9 points
below Qwen3.5-4B. The quality gap against what is now available is large, and
it is precisely the gap the 2026-11-02 rules benchmark failed in.

### Estimated cost on Frey

Sizes from Unsloth's 4-bit figures; speeds are **estimates** from the
10.5 GB/s baseline in §1 and cover *generation only* — prompt processing is
separate and worse.

| Model | ~4-bit size | Est. generation | Fits 12 GiB? | Note |
| --- | --- | --- | --- | --- |
| Qwen3.5-0.8B | <1 GB | ~15 tok/s | yes | draft / FIM candidate |
| Qwen3.5-2B | ~1.5 GB | ~7 tok/s | yes | ≈ current speed, far better quality |
| **Qwen3.5-4B** | **~3 GB** | **~3.5 tok/s** | yes | **recommended default** |
| Qwen3.5-9B | ~6.5 GB | ~1.6 tok/s | tight | batch-only; starves other services |

> **Corrected by measurement, 2026-11-07.** The table above was built by
> scaling this repo's old 1.7B figures, which assumed ~10.5 GB/s of effective
> weight-read bandwidth. Qwen3.5-4B UD-Q4_K_XL, once deployed, measured
> **2.70 tokens/s** (260 tokens in 96.2 s) — about 25% below the 3.5 predicted.
> Effective bandwidth for this model is nearer **7.9 GB/s**, so a larger model
> reads more per token than scaling a small one predicts. Project from 7.9:
> the 9B row is closer to **1.2 tok/s** than 1.6, and the 2B nearer 5.3 than 7.
> Also note the host reported **8 GiB available**, not the 12 GiB recorded
> earlier in `CAMPAIGN_ASSISTANT_PLAN.md`.
>
> Vision was verified on the same day: a generated solid-colour image was
> identified correctly in 5.8 s at 37 prompt tokens. A real photograph carries
> far more vision tokens and will be much slower.

**Recommended default: Qwen3.5-4B at UD-Q4_K_XL.** It is the point where
quality crosses into "worth reviewing" while generation stays tolerable for
drafting, and it brings vision at no extra model. Raise `mem_limit` from 3 GiB
to about 5 GiB to hold weights plus KV cache.

Qwen3.5-2B is the right fallback if 3.5 tok/s proves too slow in practice; it
should still beat the deployed 1.7B clearly.

Qwen3.5-9B is not recommended as the interactive default. At ~1.6 tok/s a
250-token answer takes over two and a half minutes, and 6.5 GiB resident
competes with Jellyfin and the *arrs — the same CPU-contention argument
`CLAUDE.md` already makes about software transcoding. It is defensible as an
*on-demand, idle-unloaded* model for batch jobs (session recaps, bulk
captioning) under llama-swap, which is a good argument for the swap layer.

### Where Qwen is not the best answer

- **German prose.** Qwen3.5 covers 201 languages and the 2026 German public
  sector benchmark (MÖVE) tested Qwen alongside Gemma and Ministral with all
  three supporting German natively, but I found **no head-to-head German
  quality comparison at the 4B scale**. If German output quality matters for
  campaign notes, this is worth a direct A/B against **Gemma 3 4B** on your own
  prompts — Gemma 3's training is more European-weighted. Treat it as untested,
  not settled.
- **Code completion.** Qwen3.5 small is not documented as FIM-trained.
  **Qwen2.5-Coder-1.5B** remains the proven fill-in-the-middle model at this
  size. See §10.
- **Embeddings.** If a search index is added (plan phase 3), use a dedicated
  embedding model — **Qwen3-Embedding-0.6B** is strong for its size, with
  bge-m3 as the multilingual alternative. Do not use a chat model for
  embeddings.

One hard compatibility fact, and it validates the existing runtime:
*"Currently no Qwen3.5 GGUF works in Ollama due to separate mmproj vision
files. Use llama.cpp compatible backends."* The plan's archived Ollama
configuration should stay archived.

## 6. llama.cpp

Keep it. The judgement has only improved since the role was written.

- It is the backend Qwen3.5 GGUFs actually load in, `mmproj` included.
- `llama-server` is one binary covering chat, completions, embeddings, vision
  and reranking, so new capabilities arrive as new *files*, not new containers
  — which is what makes the generalisation in §4 cheap.
- It already hardens cleanly: non-root, read-only rootfs, all caps dropped.

Runtime changes worth making alongside the model upgrade, in value order and
independent of speculative decoding:

1. **Prompt caching / `--cache-reuse`.** A long, stable system prompt is
   re-processed on every request today. Reusing the cached prefix removes the
   dominant share of latency for repeated-prompt workflows, and costs nothing.
   This is a larger and far more certain win than speculative decoding.
2. **Flash attention and a quantised KV cache** (`-fa`, `--cache-type-k q8_0`).
   Necessary if context grows beyond 8192; a 262K-capable model with an fp16 KV
   cache will exhaust RAM long before it exhausts context. Note Unsloth
   suggests `--cache-type-k bf16 --cache-type-v bf16` for Qwen3.5 context
   issues, so validate output quality when quantising the KV cache rather than
   assuming q8_0 is safe here.
3. **Thread count, deliberately.** Generation is bandwidth-bound and will
   barely move; prompt processing is compute-bound and scales. Going from 2 to
   3 threads helps long prompts and vision, but takes a core from the gateway.
   Leave at least one core free — the single-radio, no-console constraint means
   gateway responsiveness outranks inference speed every time.
4. **Pin the sampler to the published settings** — for non-thinking general
   tasks Unsloth gives `temperature 0.7, top_p 0.8, top_k 20, min_p 0.0,
   presence_penalty 1.5`. The existing benchmarks ran at temperature 0, which
   is right for *benchmarking* and wrong for drafting.

## 7. Quantisation and Unsloth's GGUFs

**Adopt Unsloth Dynamic 2.0 quants.** This is the cheapest real improvement
available: a different URL and SHA-256 in `defaults/main.yml`.

Dynamic 2.0 assigns different bit-widths per layer by sensitivity, upcasting
embeddings, attention and output, where stock Q4_K_M quantises everything
uniformly. Published KLD figures (lower is better): **UD-Q4_K_XL 0.4097 at
99.9%, mean 0.0137** against **Q4_K_M 0.5478, mean 0.0192** — roughly a 25–30%
reduction in quantisation damage, at a size between Q4_K_M and Q5_K_M.

This matters more on Frey than on a GPU box. Generation speed here is set by
file size, so quality-per-byte converts directly into quality-per-token/s.
UD-Q4_K_XL is Unsloth's own recommended default for Qwen3.5, and UD-Q2_K_XL
exists if a 9B ever needs to be squeezed in.

Keep everything the role already does right: pin the revision in the URL,
verify SHA-256 before first start, and never track `:latest`.

### Unsloth as a fine-tuning library: no

Unsloth's trainer requires an NVIDIA CUDA GPU. It cannot run on a Pi 5, and
fine-tuning a 4B on four A76 cores is not a thing to attempt. If a fine-tune
were ever wanted, the shape would be: train on a rented GPU, export GGUF, then
ship the artefact — and the existing pinned-URL-plus-SHA-256 download service
handles that delivery unchanged. It is a laptop-and-cloud step, not an Ansible
role.

But question the premise first. For campaign knowledge, **fine-tuning is the
wrong tool**: a LoRA bakes facts into weights that cannot be updated after a
session, cannot cite a source, and will confabulate confidently about
superseded details — the exact failure mode the 2026-11-02 benchmark already
found. Retrieval over the SilverBullet Markdown, plus a good system prompt, is
both better and reversible, and it is already plan phase 3. Revisit tuning only
for *style* (house tone, output format), never for *facts*.

## 8. Speculative decoding

**Verdict: plausible here, but unproven — measure it, and measure it last.**

The generic advice is discouraging: gains are typically 1.5–3× on GPU, while
*"on CPU-only setups gains are usually small because both models fight for the
same memory bandwidth."* A llama.cpp research issue proposing a CPU study
(#21453) was closed as already-implemented with **no measurements attached**, so
there is no authoritative CPU number to cite.

The arithmetic for *this* machine is more encouraging than the generic advice,
because Frey's bottleneck is exactly what speculation addresses. Normal
generation re-reads the whole model per token. Speculation drafts K tokens
cheaply, then verifies them in **one batched pass that reads the target weights
once**. For a Qwen3.5-0.8B draft (~0.7 GB) against a 4B target (~3.0 GB) at
K=4: drafting costs 4 × 0.7 = 2.8 GB of reads, verification 3.0 GB, so up to 5
tokens for 5.8 GB — about **1.16 GB/token against 3.0 GB/token**, a ~2.6×
ceiling at perfect acceptance. At a realistic 60–70% acceptance that lands near
**1.5–1.8×**, and higher on structured output.

Which is the interesting part: this workload is unusually speculation-friendly.
Markdown page generation, `[[wiki link]]` scaffolding, JSON and repeated
templated phrasing are highly predictable, so acceptance should run well above
the prose average. Free-form rules reasoning will do worse.

Why it is still last in the queue:

- **Verification is compute-bound**, and the Pi 5 is compute-poor — four A76
  cores with no i8mm. On `--threads 2` the batched verify may eat the bandwidth
  saving outright. Any test needs 3 threads to be a fair one, which costs the
  gateway a core.
- **It costs ~0.7 GB of RAM** that the 4B upgrade also wants.
- **Tokenizer compatibility must hold.** llama.cpp requires the draft and
  target to share a vocabulary. Qwen3.5-0.8B and Qwen3.5-4B are the same
  family, so this is very likely fine — and `llama-server` fails at startup
  rather than silently misbehaving if it is not, which makes it cheap to check.
- **It changes nothing about quality.** Speculative decoding is mathematically
  output-identical to the target model. It cannot fix the 2026-11-02 failures.
  Spending effort here before the model upgrade optimises the wrong variable.
- `--cache-reuse` (§6) is a bigger, more certain latency win for the actual
  workflow and should be done first.

If tested, record draft acceptance rate alongside tok/s; acceptance is the
single number that decides whether it is worth keeping, and it is workload-
dependent enough that one prose test will mislead.

## 9. Image recognition

"Image recognition" is three different wants with three different costs. Only
the first is nearly free.

### a. Describe or caption an image you upload — nearly free

llama.cpp's multimodal support means **the 4B you are already running does
this** once an `mmproj-F16.gguf` sits beside the weights. No new container, no
new service, no new network path — one more pinned file in the existing
download registry, and Qwen3.5-4B leads all sub-15B models at 65% MMMU-Pro.

The honest caveat is speed. Vision inflates the *prompt*, and prompt processing
is the Pi's weakest axis: an image becomes hundreds to low-thousands of tokens
plus a vision-encoder pass. Expect **tens of seconds to a few minutes per
image**, not an interactive experience. Fine for "caption this photo of a
whiteboard"; not fine for a live feed.

### b. Read text from documents or signs — use OCR, not a VLM

For extracting text, a dedicated OCR engine (Tesseract, PaddleOCR) is far more
accurate per CPU-second than asking a 4B VLM, and it does not hallucinate
plausible-but-wrong characters. If the goal is getting rules PDFs or handwritten
session notes into SilverBullet, this is the right tool and it is a separate,
much lighter component.

### c. Search photos by content — use CLIP embeddings, not a VLM

For "find the photo with the harbour map", captioning every image with a VLM is
the expensive way. Image embeddings plus a vector index cost a fraction per
image and give ranked retrieval. This is the same infrastructure plan phase 3
needs for note search, which argues for building the embedding path once.

### The policy constraint, which matters more than the technology

`docs/CAMPAIGN_ASSISTANT_PLAN.md` already decided this: *"Deny AI access to
Immich, pictures, other services, host credentials, secrets and the Docker
socket by default. Any later picture access requires a separate explicit
decision and must be read-only at most."*

Adding vision to the chat — where a human uploads one image per request — is
**consistent** with that, because no photo library is mounted and the
`ai_private` network still has no route anywhere. Pointing the model at a photo
library is the thing the plan requires a separate decision for. Keep those two
apart: ship (a), and treat (c) as a distinct proposal with its own access
review.

## 10. A coding agent on the Pi

**Verdict: no.** Two independent reasons, either sufficient.

**It does not work.** Agentic coding is prompt-processing-dominated, which is
the Pi's weakest axis. A single turn carrying ~6k tokens of file context, at a
generous 20 tok/s prompt processing for a 4B, spends **about five minutes
before the first output token**, then generates at ~3.5 tok/s. A ten-step task
runs over an hour. And a 4B model's tool-calling reliability is far below the
threshold where an agent saves more time than it costs — this repo's own
benchmark found the current model contradicting itself on a question with the
rule supplied in the prompt.

**It is the wrong thing to put on this machine.** `CLAUDE.md`'s organising
constraint is that the Pi has no Ethernet and no console, so a bad change to
networking or sshd bricks it until someone drives to it. An autonomous agent
with write access to `roles/network_gateway` or the ability to run
`ansible-playbook` is precisely that risk, executed by the least reliable
available model. The deadman rollback timer exists because *careful humans* get
this wrong.

### What is actually worth doing instead

- **Keep the coding agent on the ThinkPad.** It has the compute, and Claude
  Code against a frontier model is not comparable to a local 4B. The Pi's
  contribution is *availability*, not capability.
- **The Pi as an offline endpoint of last resort.** Because the generalised
  module exposes OpenAI-compatible `/v1`, an editor or agent on the laptop can
  point at `ai.hub.frey` when parked with no uplink. Degraded, but better than
  nothing, and it costs nothing extra once §4 is done.
- **Code completion, not agency — the one defensible local coding use.**
  Fill-in-the-middle with **Qwen2.5-Coder-1.5B** (~1 GB at Q4, est. ~10 tok/s)
  returns a 20-token single-line completion in roughly two seconds. That is
  genuinely usable over FreyHub, needs no tools, no repo access and no write
  path, and fits the model registry as just another entry. Note Qwen3.5 small
  is not documented as FIM-trained, so this stays on Qwen2.5-Coder.
- **If an agent is ever wanted, keep the §4 boundary.** Read-only mounts of
  explicitly selected material, writes only to a draft area, human review before
  anything lands in established notes — which is what plan phase 4 already
  specifies, and what `docs/CAMPAIGN_AGENT_EVALUATION.md` found Hermes does not
  provide by default (*"its default terminal runs on the host"*).

## 11. Strata

**Disambiguation first:** this evaluates **Klavis AI's Strata** (YC P25), an
open-source MCP server providing *progressive tool discovery*. There is also an
unrelated "Strata Identity" enterprise SSO product; given Frey already runs
Authelia and LLDAP, that one is both irrelevant and the wrong scale. If you
meant something else by Strata, say so and this section needs redoing.

**What it does.** Instead of flooding an agent's context with hundreds of tool
definitions, Strata exposes tools in stages — categories first ("Pull
Requests", "Issues"), then the specific actions inside a chosen category. It
reports **+15.2% pass@1 over the official GitHub MCP server**, and the claimed
mechanism is sound: revealing tool detail only as intent narrows prevents the
hallucination that happens when a model picks among dozens of similar-looking
functions.

**Verdict: not now.** The reasoning is about fit, not quality:

- **It solves a problem Frey does not have.** `roles/campaign_ai/README.md`:
  *"No agent tools or MCP servers are enabled."* Tool overload begins somewhere
  north of twenty tools. Frey has zero. Adopting a tool router before having
  tools is pure complexity.
- **The benchmark does not transfer.** +15.2% pass@1 was measured against
  GitHub's MCP server with a capable model. On a 4B, the bottleneck is not tool
  *discovery* but tool-calling reliability and the minutes of prompt processing
  each extra discovery round-trip costs. Progressive discovery means **more
  turns**, and on this hardware every turn is expensive — it could plausibly be
  net negative here.
- **Offline-first cuts against it.** Klavis is a hosted platform with a
  self-hostable server. `CLAUDE.md` is explicit that nothing below the Pi may
  depend on internet, and FreyHub must serve clients fully with no uplink. Any
  adoption must be the fully self-hosted path, pinned, with its network
  reachability verified when parked off-grid.

**Revisit when** a local agent exists, has more than roughly twenty tools, and
a model that can reliably call them — which on current Pi hardware is not
foreseeable. Its *design lesson* is worth stealing immediately though, and for
free: when the assistant eventually gets tools, expose few, and expose them in
stages.

## 12. Recommended order of work

Strictly in value order. Steps 1–3 address the recorded failure; everything
after is optimisation.

1. **Upgrade the model to Qwen3.5-4B UD-Q4_K_XL** and raise `mem_limit` to
   ~5 GiB. Pin URL, revision and SHA-256 as the role already does. Re-run
   `scripts/campaign-rules-benchmark.py` and the two synthetic prompts in
   `docs/CAMPAIGN_AGENT_EVALUATION.md` — same prompts, same limits, as that doc
   requires — and record tok/s, RAM, temperature and whether the long-rest
   contradiction is now caught. This is the one change that could move the
   verdict off *"not reliable without review."*
2. **Add `--cache-reuse`, `-fa`, and the published sampler settings.** Validate
   KV-cache quantisation against output quality rather than assuming.
3. **Rename to `local_ai` / `ai.hub.frey`**, in one commit covering the role,
   both group_vars keys, images.yml, the scripts, the Dashy tile and an explicit
   `state: absent` for the old systemd units.
4. **Generalise the shape**: `local_ai.models` registry, templated download
   unit, and a stable OpenAI-compatible `/v1` — including the deliberate
   non-browser auth path from §4, since forward auth will otherwise 302 every
   API client.
5. **Add the `mmproj` file** for vision (§9a). No new container.
6. **Add model swapping** (llama-server router mode or llama-swap, process-
   spawning only) once there is more than one model — which step 5 plus any
   embedding model makes true.
7. **Then, optionally, measure speculative decoding** with an 0.8B draft at 3
   threads, recording acceptance rate. Keep it only if it clears ~1.4× on real
   prompts without hurting gateway responsiveness.

Not recommended: a Pi coding agent, Strata, Unsloth fine-tuning, Qwen3.5-9B as
the interactive default.

Per `CLAUDE.md`, the acceptance test for each step is a second run reporting
**0 changed**, plus the matching check script — `scripts/campaign-ai-check.sh`
and `scripts/campaign-ai-ready-check.sh`, renamed with the module. Note that
neither currently tests answer quality, which is why step 1 explicitly re-runs
the benchmarks.

## 13. Open questions

- **German output quality at 4B** — Qwen3.5-4B against Gemma 3 4B on real
  campaign prose. No published head-to-head found at this scale; needs your own
  A/B.
- **Actual prompt-processing throughput on Frey.** Every estimate in §8–§10
  depends on it, and it has never been measured here — only generation has.
  Measure pp with `llama-bench` before trusting any of those figures.
- **Whether 3.5 tok/s is tolerable** for phone drafting, or whether Qwen3.5-2B
  is the better default in practice.
- **Gateway contention under inference load**, which the plan lists as an
  explicit requirement and which no test has covered. The transcode precedent
  in `CLAUDE.md` suggests it matters.
- **The unresolved Cleanuparr OIDC 404** from 2026-11-02 is a prerequisite for
  trusting any claim about identity enforcement on a renamed host.
- Whether retrieval (plan phase 3) lands before or after the model upgrade.
  Retrieval over trustworthy notes plus a 4B will beat a 9B guessing from
  memory, which argues for doing it sooner than the roadmap implies.

## Sources

Checked 2026-11-07.

- [Qwen3.5 — How to Run Locally (Unsloth)](https://unsloth.ai/docs/models/qwen3.5)
- [Qwen3.5 small models: Everything you need to know (Artificial Analysis)](https://artificialanalysis.ai/articles/qwen3-5-small-models)
- [unsloth/Qwen3.5-4B-GGUF](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF) ·
  [2B](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF) ·
  [0.8B](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF)
- [Unsloth Dynamic 2.0 GGUFs](https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs) ·
  [blog](https://unsloth.ai/blog/dynamic-v2) ·
  [UD-Q4_K_XL vs Q4_K_M discussion](https://huggingface.co/unsloth/Qwen3-30B-A3B-GGUF/discussions/6)
- [Speculative Decoding (Unsloth docs)](https://unsloth.ai/docs/basics/inference-and-deployment/saving-to-gguf/speculative-decoding)
- [llama.cpp issue #21453 — Speculative Decoding for Low-Latency CPU Inference](https://github.com/ggml-org/llama.cpp/issues/21453)
- [llama-swap](https://github.com/mostlygeek/llama-swap) ·
  [llama-swap and llama-server Router Mode](https://www.bigiron.cc/guides/llama-swap-and-llama-server-router-mode-many-models-behind-one-endpoint)
- [Introducing Strata (Klavis)](https://www.klavis.ai/blog/introducing-strata-one-mcp-server-for-thousands-of-tools) ·
  [Strata GitHub use case](https://www.klavis.ai/use-case/strata-github-usecase) ·
  [Launch HN: Strata (YC P25)](https://news.ycombinator.com/item?id=45347914)
- [MÖVE: A Holistic LLM Benchmark for the German Public Sector](https://arxiv.org/pdf/2606.13111)
- [Best Small LLMs to Run Locally (2026)](https://codersera.com/blog/best-small-llms-to-run-locally-a-comprehensive-guide/)
