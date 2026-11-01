# Campaign Knowledge and Local Assistant Plan

Status: phases 1–3 are in progress and phase 4 evaluation has started.
SilverBullet is deployed and the initial rules and campaign structure are in
the Notes space. Check product
versions, licensing, compatibility and policies again when implementing each
phase.

## Goal and boundaries

Create a private, offline-capable knowledge base and local assistant for a
custom tabletop role-playing campaign. The GM can browse and edit linked notes,
consult the rules, prepare and recap sessions, and approve suggested changes.
The assistant should later support other workspaces without inheriting access
to private services or data.

Frey's gateway and existing services must remain usable under AI and transcription
load. The Pi may have no internet during a game: local notes, the assistant and
previously imported character snapshots must work without it. Discord recording
therefore needs a separate connected machine or a participant's computer.

## Architecture to evaluate

- **Knowledge base:** prototype [SilverBullet Server](https://silverbullet.md/),
  a self-hosted, MIT-licensed server using Markdown files. It offers wiki links,
  backlinks, queries and an experimental graph. Its Android interface is an
  installable progressive web app (PWA), not a separate Play Store app. A synced
  browser copy contains space data; protect the device and control which spaces
  are synced. SilverBullet Desktop is separately licensed.
- **AI:** evaluate a small local model and document search first. The archived
  Ollama and Open WebUI configuration is reference material, not an active
  dependency. Evaluate Hermes as an optional restricted agent once useful tasks
  and Pi performance are understood.
- **Campaign truth:** Markdown notes and original documents are authoritative;
  a search index is rebuildable. Distinguish established events, GM plans,
  rumors and ideas. AI-generated changes require GM review.
- **Characters:** treat the [Archipelago GM site](https://jim8knopf.github.io/Archipelago/gm/?campaign=pirate)
  as the source for live character data, subject to verification of how it
  stores and exposes data. Use configurable, read-only imports and timestamped
  local snapshots; do not assume that the campaign or site format is fixed.
- **Recording:** capture Discord audio on a separate connected host or a
  participant's computer, then transfer it securely to Frey for local
  transcription. GitHub Pages can host static pages, not the bot backend.

## Privacy and access decisions

- [ ] Obtain each participant's agreement before recording; explain the
  purpose, recording indicator, storage location, access, retention, deletion,
  and how to decline or stop. Repeat the agreement when circumstances change.
- [ ] Choose a retention and deletion policy for audio, transcripts, temporary
  files, search indexes and backups; document who can access each copy.
- [ ] Protect GM secrets and player-facing material with separate access
  boundaries, not tags alone. Test the chosen application and sync behavior.
- [ ] Give the AI read-only access to explicitly selected campaign material and
  write access only to a draft area. Review changes before applying them to
  established notes.
- [ ] Deny AI access to Immich, pictures, other services, host credentials,
  secrets and the Docker socket by default. Any later picture access requires a
  separate explicit decision and must be read-only at most.
- [ ] Enforce boundaries with separate identities, narrowly scoped mounts and
  network restrictions, not instructions to the model alone. Test denials.
- [ ] Choose backups and retention that cover sensitive notes and recordings;
  test restore and deletion procedures as well as creation.

Hosted [Craig](https://craig.chat/privacy/) is an option to evaluate, not an
approved privacy choice. Its policy describes collection of audio and Discord
identifiers, link-based recording access, and possible retention for debugging.
The published default recording expiry is seven days, while the privacy policy
permits exceptions. Storage country, processing agreements, subprocessors and
transfer arrangements need verification; GDPR compliance cannot be assumed.
Self-hosting gives more control over the recording copy but does not remove
Discord or the hosting provider from the workflow.

## Roadmap

### 1. Prototype the knowledge base

- [x] Measure available memory, storage and architecture; deploy a pinned ARM64
  SilverBullet Server release. On 2026-11-01 Frey had 15 GiB RAM, 12 GiB
  available and 3.4 TiB free; SilverBullet 2.12.1 started successfully.
- [ ] Confirm suitability of the editor, links, backlinks, queries and graph
  using sample NPC, species, ship, location and session pages.
- [x] Integrate a new Ansible role with persistent storage, Frey HTTPS,
  appropriate authentication and a Dashy entry. Follow `ADDING_MODULES.md`.
- [ ] Verify authentication and sync compatibility: SilverBullet documents a
  limitation for desktop sync behind external authentication proxies. Test the
  intended browser and Android flows before choosing the final arrangement.
  Frey registers an Authelia OIDC client while preserving group-based forward
  auth. The provider test passed and SSO is enabled. A directory group sync is
  active using the existing `note_admin` account and has enrolled current Frey
  administrators; interactive sign-in and live group-change tests remain.
  It manages enrollment and roles from `frey_admins` and `notes`. See
  `roles/silverbullet/README.md`.
- [ ] Install the Android PWA; test initial sync, offline access and edits,
  reconnection and conflicts, and access after a phone/browser restart.
- [ ] Set up backups and demonstrate a restore on a separate test location.
  On 2026-11-02 an ad hoc archive of the live Notes space was restored to a
  private temporary directory on the admin computer; 68 regular files matched
  the archive by SHA-256, and the temporary files were removed. This did not
  test an application-level restore or a consistent snapshot during edits,
  and no scheduled or retained backup was established.
- [ ] Complete and verify SilverBullet first-run setup and authenticated use.
  On 2026-11-02 `bash scripts/silverbullet-check.sh` passed: anonymous space
  paths redirected, the service worker loaded and the manifest required
  SilverBullet login. This does not verify interactive sign-in or offline sync.
- [ ] Complete service acceptance checks, including the authenticated and PWA
  checks with an authenticated user. The focused dry run and deployment succeeded,
  and the repeat deployment reported zero changes on 2026-11-01. Anonymous
  content access was denied; the existing identity and monitoring checks passed.

**Done when:** the GM can edit linked notes from a browser and Android, use a
previously synced copy offline, and recover the space from backup.

### 2. Organize and import campaign material

- [ ] Import supplied custom rules and story ideas, keeping originals and
  document versions. Check searchable text; evaluate OCR for scanned documents.
  The supplied Pirate d100 Markdown draft was imported unchanged and verified
  on 2026-11-01. No story outline has been supplied yet.
- [ ] Create practical templates for characters, NPCs, species, places,
  factions, ships, sessions and unresolved threads.
  Eight SilverBullet page templates and a linked Pirate campaign overview have
  been added; check their behavior in the browser before marking this complete.
- [ ] Test examples such as an NPC linking to its species and faction, and a
  query listing NPCs by location.
- [ ] Separate GM-only plans from player-facing information and distinguish
  plans, rumors, proposed events and established history.

**Done when:** the GM can navigate real campaign material and find related
pages without relying on the AI.

### 3. Add local AI reading and search

**Immediate priority:** get a usable local chat for turning pasted ideas and
Markdown documents from the GM's phone into proposed linked campaign pages.
The first workflow is review-and-copy into SilverBullet, with no automatic
access to notes, photos or other services. Whole-campaign search and automatic
page creation remain later steps.

On 2026-11-01 the `campaign_ai` role was deployed with Frey group access,
an isolated local runtime and a background download of Qwen3 1.7B Q4_K_M.
The model has finished downloading; chat and phone attachments still need a
real user test. A linked "Turn ideas into pages" guide
and two reusable prompts are now in the Pirate campaign home; its source is
`docs/CAMPAIGN_IDEA_WORKFLOW.md`. See `roles/campaign_ai/README.md`.
The pinned chat UI bundle contains Markdown and plain-text attachment support;
the actual phone upload remains untested. A retry timer resumes an incomplete
model download after a failure or reboot, and
`scripts/campaign-ai-ready-check.sh` reports download and readiness status.
On 2026-11-02 the deployed identity configuration no longer contained the
SilverBullet and assistant rules; the identity role restored them. The assistant
readiness and anonymous-access checks passed, and a repeat identity deployment
reported zero changes. The wider identity check passed except for its outdated
Cleanuparr forward-auth expectation after Cleanuparr moved to OIDC; a 200
response alone does not verify Cleanuparr sign-in. Interactive campaign sign-in
and phone uploads remain untested.

- [ ] Benchmark suitable small quantized models against real rules questions,
  response time, RAM, CPU, temperature and existing service responsiveness.
  The Pi has approximately 12 GiB available RAM in the current configuration.
  A preliminary test on 2026-11-01 used llama.cpp `server-b12019` and Qwen3
  1.7B Q8_0 with a 2-CPU, 3-GiB container limit. A short armor/evasion question
  with its rule supplied in the prompt produced the expected answer in 4.84 s
  (about 6.1 generated tokens/s); idle memory while loaded was 2.185 GiB. This
  is one simple test, not a quality or retrieval evaluation. The temporary
  container was removed. On a later check the model volume was empty, although
  the runtime image remained. A fresh download was stopped because the uplink
  was slow; the incomplete download and temporary container were removed.
  `scripts/campaign-rules-benchmark.py` now provides six repeatable questions
  using excerpts from the actual draft, including missing rules and a possible
  long-rest contradiction. Its answers need human review against the printed
  rubrics. On 2026-11-02 the deployed Q4_K_M model answered all six in
  19.64–48.40 seconds each. It got the mana cost and cross-training numbers
  right and recognized that maximum mana lacks a formula. It contradicted
  itself about failed evasion, did not flag the untrained-skill ambiguity,
  and missed the long-rest contradiction; two answers hit the 250-token
  limit. This small model is not reliable for rules decisions without review.
  After the run Docker reported 2.5 GiB of its 3 GiB limit and the CPU
  temperature was 60.6 °C; these are single post-run readings, not peak
  measurements or a comparison of models or service responsiveness.
- [ ] Choose and pin a runtime and model; arrange model downloads ahead of
  offline use. Add an authenticated dashboard interface and explicit start,
  stop and running status; define behavior after reboot and redeployment.
- [ ] Index only approved documents and notes; preserve source references and
  support rebuilding the index after edits or restore.
- [ ] Check that answers cite useful passages, distinguish unknowns and perform
  acceptably on the custom rules. Verify operation without internet.
- [ ] Verify resource limits, acceptance checks and repeated idempotent deploys.

**Done when:** the GM can start the local assistant, ask grounded questions and
stop it without compromising Frey's network or other essential services.

To compare a running local OpenAI-compatible model against the draft, run:

```sh
python3 scripts/campaign-rules-benchmark.py /path/to/Pirate_TTRPG_Rules_Draft.md --url http://127.0.0.1:8080
```

Use `--model` if the server requires a particular model name. The benchmark
accepts only a loopback server address. If the server is on Frey, use an SSH
tunnel to its loopback-only port; do not expose an unauthenticated inference
API to the network. Each JSON line contains a question, answer, timing and a
rubric for manual review. These questions supply their own excerpts, so they
test rule reasoning, not search or retrieval. Treat the results as private
campaign material. The script does not start a model or download one.

### 4. Evaluate a restricted agent and reviewable edits

On 2026-11-02 the existing assistant was tested on two synthetic recap and
note-update prompts. It preserved the rumor but incorrectly attributed an
existing page fact to the new source. See `docs/CAMPAIGN_AGENT_EVALUATION.md`
for the prompts, results, review criteria and Hermes isolation requirements.
This is a baseline, not a Hermes comparison or a test with real campaign notes.
A four-minute pull of a pinned ARM64 Hermes image timed out before completion;
an additional 15-minute attempt also timed out. No Hermes container was
started, and the pull is no longer running. Monitoring
reported all targets up but ntfy delivery failing with seven queued alerts;
the cause was not established. See the evaluation for the image digest.

- [ ] Compare Hermes with a simpler assistant on actual recap and note-update
  tasks; verify compatibility with the selected local model and Pi resources.
- [ ] Isolate the selected agent and give it access only to approved inputs and
  drafts. Disable unnecessary tools, credentials and network routes.
- [ ] Produce proposed recaps, links and record changes with evidence; provide
  a review step before applying changes to established notes.
- [ ] Test history, rollback, concurrent editing and denied access to unrelated
  services, especially Immich and host administration.

**Done when:** suggested changes are inspectable, reversible and never applied
to campaign truth without GM review.

### 5. Connect the live character site

- [ ] Inspect the site's actual storage, API or export and permissions before
  choosing an integration. Recheck if the site changes.
  On 2026-11-02 the live GM JavaScript matched the locally cached
  `origin/main` version and used the Firebase SDK's Firestore listener on
  `campaigns/{campaignId}/characters`. The checked-in prototype rules allow
  unauthenticated reads and writes to those documents; the actually deployed
  Firestore rules have not been verified. The campaign ID is not an access
  control mechanism. The local checkout has uncommitted changes and its
  `origin/main` reference may be stale; no live character data was fetched.
  Verify the deployed rules and authorization before integrating, and use a
  read-only identity rather than relying on client-side behavior.
- [ ] Choose the fields to import and keep the campaign identifier configurable.
- [ ] Implement a read-only import if reliable; record source, last successful
  update and errors, and preserve the last valid offline snapshot.
- [ ] Test changed schemas, unavailable internet, multiple campaigns and
  stale data. Do not write to the site without a separate design decision.

**Done when:** available character data can be consulted offline with its
freshness clearly visible.

### 6. Choose and test private recording

- [ ] Agree the process with players and decide between a participant's
  computer, a separately hosted server and other suitable alternatives.
- [ ] Evaluate maintained recording software and verify current Discord DAVE
  voice compatibility and permission to add a bot to the Discord server.
- [ ] Test explicit start/stop and a visible recording indicator; test all
  speakers, late arrivals, reconnection, recording quality and track separation.
- [ ] Secure storage and transfer, limit access, apply the agreed retention
  policy and verify deletion. Keep the bot token and download links private.
- [ ] Transfer a test recording to Frey without requiring the Pi to be online
  during the session.

**Done when:** a recording can be captured and transferred independently of
Frey's uplink, with the group comfortable with its data handling.

### 7. Transcribe and prepare session notes

- [ ] Evaluate local Whisper-based transcription; the archived Wyoming Whisper
  service is a reference, not a ready-made long-session workflow.
- [ ] Benchmark Pi processing against another computer; schedule background
  work and protect existing services from CPU and memory pressure.
- [ ] Preserve speaker tracks and timestamps where possible; test custom names,
  languages, overlapping speech and error correction.
- [ ] Generate a draft recap, proposed character changes and open threads with
  references back to the transcript where practical.
- [ ] Review before updating notes; apply the agreed retention and deletion
  policy to audio, transcript, drafts, indexes, temporary files and backups.

**Done when:** a session can produce a reviewable, traceable recap without
automatically turning transcription mistakes into campaign facts.

### 8. Expand to other uses

- [ ] Add other knowledge spaces and integrations only when there is a concrete
  use case; decide access and data handling separately for each one.
- [ ] Reassess model quality, isolation, backup and resource budgets as the
  assistant gains capabilities. Keep campaign and personal data boundaries.

## Open decisions

- Confirm SilverBullet is pleasant to use on the GM's Android device and that
  its experimental graph and authentication fit the intended workflow.
- Determine actual Pi memory and acceptable inference/transcription speed.
- Decide who can see which campaign material and whether players need access.
- Inspect the evolving character site's data format and import options.
- Choose the recording host, software, participant agreement and retention
  periods; verify any hosted provider's terms before use.
- Decide how much agent functionality is useful after the read-only trial.
