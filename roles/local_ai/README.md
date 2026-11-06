# Local AI

Local inference as a shared service. The llama.cpp chat UI and an
OpenAI-compatible API are served at `https://ai.hub.frey` behind Frey sign-in,
limited to `frey_admins` and `notes`. Inference runs entirely on the Pi; only
model downloads need internet.

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
memory-bandwidth-bound, so ~2.7 GiB of weights at the ~10.5 GB/s this Pi
achieves is roughly 3.5 tokens/s. Threads buy *prompt* processing, which is
compute-bound and the Pi 5's weak axis — its A76 cores have no i8mm. The role
uses two threads on purpose, leaving cores for the gateway: on a Pi with no
Ethernet and no console, gateway responsiveness outranks inference speed.

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

## Verifying

From the Frey project directory on the admin computer:

```sh
bash scripts/local-ai-ready-check.sh   # download, readiness and isolation; exit 2 = still downloading
bash scripts/local-ai-check.sh         # anonymous access is redirected
```

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
