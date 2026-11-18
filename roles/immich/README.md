# Immich

Immich serves photos at https://immich.hub.frey. Server and machine learning
images are pinned together; Postgres and Valkey follow the upstream compose for
the pinned release. Photos live under `/opt/frey/data/photos`, the database and
model cache under `/opt/frey/appdata/immich`. Back up the database and photo
folder together; see https://docs.immich.app/administration/backup-and-restore/.
The database password is generated once on the host and must be backed up too.
Do not reuse a legacy database without a tested migration and matching password.

Deploy identity first, then Immich and Dashy. The initial local administrator must be created from a trusted device listed in
`frey.trusted_devices` (currently the admin laptop). Sign in with that local account and link it to Frey SSO in User Settings
before signing in with SSO. Immich may otherwise create a separate user when
the local and Frey email addresses differ. Keep the local administrator password
for recovery. Mobile clients
must trust the Frey root CA and use the canonical HTTPS address. Frey SSO
allows `frey_admins` and `immich` group members. Frey administrators become
Immich administrators; members of `immich` receive the standard user role.
The policy is checked at SSO login; removing a group does not revoke existing
Immich sessions or disable a local password. Maps require an external tile
service.

OAuth is managed in the Immich config file, so Immich disables editing system
settings in its UI. Change settings through the role instead. Run
`scripts/immich-check.sh` after deployment to check routing, features, OAuth
discovery, the model cache, a real inference request and face-detection
coverage. Test the web and mobile OAuth flows, upload and download a photo,
and verify smart search. For upgrades consult the Immich release notes and
back up before database migrations.

## Face recognition

This is the part of Immich that behaves unlike anything else in Frey, and the
reason it has its own alerts, its own deploy-time probe and its own recovery
script.

### A failed face-detection job is lost, not retried

The ML container fetches its models from Hugging Face the first time each one
is needed. When that fetch cannot happen — no uplink, a captive portal, a
venue that blocks outbound DNS — `immich_ml` does not simply report an error.
Its load handler classifies the failure as a **corrupt download**, so it
`rmtree`s the cached model and tries again, and answers the request with
HTTP 500. The server then **discards** that job instead of re-queueing it, and
nothing in Immich ever picks it up again: the nightly tasks cover missing
thumbnails and clustering new faces, never missed *detection*.

Every one of the four containers stays `healthy` through all of this. The only
symptom is a People page that never fills up.

That is not hypothetical. On 2026-11-13/14 this host logged 3,658 failed
face-detection requests, 3,939 CLIP and 3,939 OCR, all `failed for all URLs`
with `Temporary failure in name resolution` underneath. Face detection was
left at 285 of 13,648 assets — 2% — with empty queues, no failures recorded
anywhere, and `/api/server/features` cheerfully reporting
`facialRecognition: true`.

So:

- **Never read "the containers are up" as "faces are being found."** Run
  `scripts/immich-check.sh`, which makes a real inference request and prints
  coverage.
- **After any offline window, check coverage.** If work was dropped, re-queue
  it with `scripts/immich-reprocess.sh`. Redeploying does not do it.
- `FreyImmichModelsMissing` and `FreyImmichFaceBacklogStalled` are the alerts
  that catch this without you looking.

### The job queue is persisted, unlike upstream

Upstream runs Valkey purely in memory, on the reasonable assumption that a lost
job queue can just be re-queued. That assumption does not hold here. This van
cuts power rather than halting — `FreyUnsafeShutdown` exists for that reason —
and Immich never re-queues missed detection on its own, so an in-memory queue
means **every unsafe shutdown silently discards the whole remaining backlog**
with no error anywhere. A full pass is hours of work, so the role turns on
`appendonly` and gives Valkey a volume under `/opt/frey/appdata/immich/valkey`.

The log lives on the host volume, so the queue now survives a restart, a
container recreation and a power cut alike. It was lost exactly once: on the
deploy that first enabled persistence, when the volume was still empty.

### Not every asset can be scanned, and that is not always a fault

Every ML job — face detection, smart search, OCR — reads the **preview**, not
the original. So an asset with no preview is permanently unsearchable, and
there are two very different reasons for that:

- **Hidden assets never get one, by design.** The video half of every motion
  photo is stored as a separate `visibility = 'hidden'` asset. There are ~441
  here. Immich never detects faces in them and never will. Counting them as a
  backlog is what would make an alert fire forever.
- **Undecodable originals.** ~68 phone JPEGs here have damaged DCT scan data.
  They are not truncated (they end in a proper `ff d9`) and their metadata
  reads fine, but libvips refuses them outright at every `failOn` level:
  `VipsJpeg: ./lib/jpegli/decode_scan.cc:543: Failed to decode DCT block`.
  Immich retries them nightly via `nightlyTasks.missingThumbnails` and fails
  every time, which is the only reason they show up in the log at all.

So coverage is measured against what *can* be scanned.
`frey_immich_faces_pending` and `scripts/immich-check.sh` both exclude hidden
and preview-less assets, and `frey_immich_assets_no_preview` tracks the second
group separately — alerting only when it **grows**, since a standing count of
damaged files is a fact rather than an event.

A damaged file is still partly recoverable: `ffmpeg` decodes one with
`error count: 69` and writes a usable JPEG, so re-encoding would restore a
viewable image with artefacts where the data is lost. That rewrites an
original, so it is a deliberate choice and not something any deploy does.

### `model_revision` is the tripwire

`immich.ml.model_revision` is `v2`, not the image default `main`. `v2` selects
the per-architecture ONNX models, and the aarch64 build is what makes
`buffalo_l` tolerable on this host at all.

It is also the thing most likely to brick face recognition, because any value
other than `main` moves the cache to `<task>/<model>/<revision>/`. Changing it
therefore invalidates **every already-downloaded model** and forces a fresh
~2.3 GB pull. Setting it with no uplink is what produced the outage above.
Change it only with an uplink, and run the check script afterwards.

### Why the limits are below the core count

The Pi 5 has no NPU and no GPU onnxruntime can use, so every face is found on
the same four cores that run the AP, dnsmasq and NAT. A pass over a full
library runs for hours.

`immich.ml.cpus` (3.0) and `immich.ml.request_threads` (3) leave a core for the
gateway, and `immich.concurrency.*` is 1 per queue rather than the upstream 2 —
a single request already uses three cores, so more concurrency buys no
throughput here, it only takes cores from FreyHub. Raising any of these makes
the van's network feel broken while photos are being scanned.

### Tuning thresholds is the *last* step, not the first

`IMMICH_CONFIG_FILE` makes the entire admin UI read-only — no `system-config`
row is written at all — so every setting absent from `config.json` is frozen at
the upstream default and cannot be changed from the browser. `immich.face.*`
exists so these are tunable through the role.

They are restated upstream defaults, deliberately:

| Setting | Effect of lowering | Effect of raising |
| --- | --- | --- |
| `min_score` (0.7) | finds more faces, and more things that are not faces | misses faces in profile or poor light |
| `max_distance` (0.5) | splits one person across several entries | merges different people into one |
| `min_faces` (3) | more people to name, many appearing once | fewer, more confident people |

**Until a full detection pass has finished, a thin People page is coverage, not
tuning.** Changing `max_distance` or `min_faces` requires re-running the
clustering job over everything, so doing it while coverage is incomplete means
doing it twice and learning nothing. Fix coverage, then tune.

One related setting is off by default upstream and left off here:
`metadata.faces.import`. If the library came from Google Photos or Apple
Photos with face regions already embedded, enabling it seeds names without any
inference — but it is a one-way import of someone else's clustering decisions,
so it is a deliberate choice rather than a default.
