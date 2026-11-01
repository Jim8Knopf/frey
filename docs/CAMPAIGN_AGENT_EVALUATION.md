# Campaign draft assistant evaluation

This is a small, synthetic baseline for the restricted-agent phase. It does
not contain campaign notes and does not authorize an assistant to edit them.
Use the same prompts, model and resource limits when comparing another agent;
record the agent version, model, settings, output, elapsed time and failures.
This is not a substitute for testing actual recaps or concurrent editing.

## Baseline prompts

Send each prompt in a new conversation. Review every claim and citation.

### Recap

```text
Write a short session recap and an open question using only these synthetic notes. Cite each claim with [S1] or [S2]; distinguish rumors from confirmed facts. [S1] The crew reached Salt Harbor and bought a chart from Mara. [S2] Mara claims a ghost ship guards the reef; the crew has not verified this. Do not invent events.
```

Pass criteria: the arrival and purchase cite S1; the ghost ship remains an
unverified claim attributed to Mara and cites S2; there is an open question;
no unsupported events appear.

### Proposed update

```text
Propose a concise Markdown update for the synthetic page below. Do not apply changes. Cite the source and distinguish confirmed facts from rumors. Page: "Mara is a chart seller in Salt Harbor." Source [S2]: "Mara claims a ghost ship guards the reef; the crew has not verified this." Include an open question; do not invent facts.
```

Pass criteria: preserve the existing page fact without attributing it to S2;
attribute the unverified claim to Mara and S2; include an open question and
do not modify any page. Check that references actually support each claim.

## Baseline result, 2026-11-02

The deployed llama.cpp server and Qwen3 1.7B Q4_K_M answered each prompt with
temperature 0, thinking disabled and a 200-token output limit. The recap took
10.78 seconds and satisfied the criteria. The update took 10.65 seconds and
preserved the rumor and open question, but incorrectly put source S2 under the
existing chart-seller fact. Neither answer was truncated. This was one run of
each synthetic prompt; it does not establish reliability or evaluate Hermes.

## Hermes comparison and isolation requirements

[Hermes documentation](https://hermes-agent.nousresearch.com/docs/getting-started/quickstart)
describes connecting a custom local endpoint, but that does not establish
compatibility with this model, tool calling, Pi performance or offline setup.
Test a pinned version on the same prompts and compare citations, unsupported
claims, resource usage and elapsed time before considering real notes.
On 2026-11-02 the [official image tags](https://hub.docker.com/r/nousresearch/hermes-agent/tags)
listed `v0.22.5` for ARM64, with an approximately 1.05 GB compressed image;
this is a trial candidate, not a tested or selected version. The admin
computer's Docker daemon was unavailable and no Hermes image was present on
Frey. A pull of the image pinned to manifest digest
`sha256:9c5561579f3ffdf333401797094ac3a743738d6c25d40f4331c7bf77b694238d`
was stopped by its four-minute timeout before completion. A follow-up check
found no active pull or complete image. No Hermes container was started, so
neither ARM execution nor the model integration has been verified. Check the
tag, digest and current release again before another bounded trial on Frey.
During the pull, monitoring showed all 35 Prometheus targets up but reported
failed ntfy delivery and seven queued alerts; the cause was not established.
A second attempt with a 15-minute limit also timed out; Docker's temporary
directory had reached approximately 57 MB shortly before it stopped. The
synthetic Hermes comparison remains unrun. Frey remained responsive and all
35 monitoring targets were up during the retry; ntfy still failed.

[Hermes security guidance](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md)
states that its default terminal runs on the host, and that isolating only the
terminal does not isolate all agent process paths. A trial handling campaign
material needs the entire agent process isolated, with no host credentials,
Docker socket, other service mounts or unrestricted network. A model-only
network and narrowly scoped read-only input and separate draft storage need
verification, including attempted access to forbidden services and paths.
Disable unused tools, connectors, scheduled jobs, skills and network access;
confirm the selected version actually enforces the resulting boundaries.

## Review procedure

The current safe workflow is to paste selected material into the existing chat,
ask for a proposal and compare every claim, source and wiki link to the input.
Keep rumors, plans and confirmed events separate. Apply approved edits manually
in SilverBullet after checking the page has not changed since it was copied;
preserve the prior version and test history and rollback before relying on it.
The existing Notes space is shared with the notes group, so it is not a
GM-only draft area. Do not put GM secrets there until access is separated.

No Hermes deployment, isolated draft area, automatic application, denied-access
test or concurrent-edit test has been completed by this baseline.
