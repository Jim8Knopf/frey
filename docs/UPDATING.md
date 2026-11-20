# Updating Frey

Everything Frey runs is version-pinned, in one file:
`inventory/group_vars/all/images.yml`. Updating is therefore always the same
three steps — find what moved, rewrite the pins, deploy the owning modules.

```bash
scripts/check-updates.py            # what has moved upstream
scripts/check-updates.py --apply    # rewrite the pins it just reported
ansible-playbook playbooks/site.yml --tags <the tags it printed>
```

`--apply` prints the exact `--tags` to use. It works them out from whichever
role reads the variable, so the answer cannot go stale the way a written-down
list would.

**Do this while you still have internet.** Pulling images is the one part that
needs an uplink, and the van is frequently somewhere that has none. The whole
point of pinning is that an unattended pull on campground WiFi can never hand
you a broken container with no connection left to fix it.

---

## What the checker will not do for you

It is deliberately conservative. Three things it refuses:

**It will not cross a major version.** A major is a migration, not a bump.
`--apply` skips those and lists them separately; `--allow-major` overrides it,
once you have read the release notes. The hazards this exists for are real and
already in the repo:

| Pin | Why a major is special |
| --- | --- |
| `media_versions.jellyfin` | 10.x → 12.x is a **one-way** database migration, and plugins must be uninstalled first (`roles/media_library/README.md`) |
| `media_versions.jellystat_db` | a new PostgreSQL major **refuses to start** on an old cluster's data |
| `identity_versions.authelia` | the config schema moves between minor releases; the role runs `authelia validate-config` before restarting anything |

**It will not touch a `hold` or a `watch`.** A `hold` is not decided by the
upstream version number at all — a date-stamped tag, a compound
`python+alpine` tag. A `watch` is reported but never applied, because knowing
a release exists is useful while the version number cannot tell you whether to
take it:

| Pin | Why you decide by hand |
| --- | --- |
| `local_ai_openwebui_version` | a minor bump can break `WEBUI_AUTH_TRUSTED_EMAIL_HEADER`. Frey has no second login, so that is a **lockout** from the window you would use to diagnose it |
| `local_ai_llama_version` | the build has to still map the served model's architecture and projector |
| `local_ai_hermes_version` | whether it is usable at all is a property of the release's prompt size, not its number |

**It will not confirm the tag can actually be pulled.** It compares against
each project's latest *release*, and a few projects tag releases differently
from the images they publish. Maintainerr has a v3 release and no v3 image;
cAdvisor skipped v0.53.0 and v0.54.0 entirely. Check before deploying:

```bash
docker manifest inspect ghcr.io/jorenn92/maintainerr:3.31.0
```

A pin it could not check is reported as such. A failed lookup is not a reason
to believe a pin is current.

---

## Adding a new image

One line, in `images.yml`, with an `# upstream:` marker saying where to look:

```yaml
media_versions:
  mynewthing: "1.2.3"  # upstream: github:owner/repo
```

| Marker | Means |
| --- | --- |
| `github:owner/repo` | latest GitHub release tag |
| `lsio:name` | linuxserver.io's published version |
| `dockerhub:repo` | newest semver-looking tag on Docker Hub |
| `watch <any of the above>` | report a new version, but never apply it |
| `hold - reason` | not checked at all; a human decides |

`tests/test_image_versions.py` fails the build if a pin has no marker, if the
marker names an unknown source, or if a `hold` does not say why. That test is
the point of the design: the four pins added before it existed — immich,
silverbullet and the two local_ai ones — were never checked by anything,
because adding a pin and remembering to register it somewhere else are two
separate acts and the second is easy to forget. Now there is no second act.

The same test also asserts that every pin is read by some role and that no
role references a pin that does not exist, so a pin left behind by a deleted
service fails CI too.

---

## How a bumped pin actually reaches the Pi

Worth knowing, because it explains why a plain deploy is enough.

Each role pulls its images **explicitly** first, with
`docker_image_pull: pull: not_present`, and only then runs compose with
`pull: never`. So:

- **You changed a pin.** The new tag is not on disk, the explicit pre-pull
  fetches it, compose starts it. A plain deploy is all you need.
- **You did not change a pin.** Nothing is pulled at all, and no registry is
  contacted. This is deliberate: on 2026-11-01 a registry round trip failed a
  whole deploy for an image that was *already present and healthy*, because
  the van was behind a captive portal, which looks online to a route table and
  is not.

To force a re-pull of a tag that has **not** changed — a repaired upstream
image, say — the media and monitoring modules take an explicit flag:

```bash
ansible-playbook playbooks/site.yml --tags media_update -e media_update=true
ansible-playbook playbooks/site.yml --tags monitoring -e monitoring_update=true
```

---

## Confirming it worked

The acceptance test for any change in this repo:

1. **Run it twice. The second run must report `0 changed`.**
2. Then run the matching check script. "The container is up" is not evidence
   the thing works, which is the whole point of these:

```bash
scripts/monitoring-check.sh      # every target up, rules loaded, collectors fresh
scripts/identity-check.sh        # assert SSO is actually enforcing
scripts/immich-check.sh
scripts/silverbullet-check.sh
scripts/local-ai-check.sh
```

If a service comes back 404 rather than 502 after an update, check container
*health* before you touch Traefik labels: Traefik deletes the routers of an
unhealthy container, and for the acquisition stack those labels live on
gluetun.

---

## The parts that are not automated

**OS packages.** Nothing in this repo runs `apt upgrade`, and that is on
purpose. The Pi has no Ethernet port and no console — both ways in are radios,
so a kernel, firmware, `wpa_supplicant` or NetworkManager update that breaks a
radio does not degrade the system, it bricks it until someone drives to it. Do
it deliberately, and ideally while you can physically reach the Pi:

```bash
ssh frey@10.20.0.1
sudo apt update && sudo apt full-upgrade
# then reboot and confirm BOTH radios came back before you leave
```

Remember that a setting correct on disk is not a setting the kernel is
running: `pciex1_gen=1` sat in `config.txt` for a day while every boot still
trained at 5 GT/s, because the Pi had not rebooted.

**Ansible collections.** `requirements.yml` lists four collections and pins
none of them, so what you get depends on when you ran the install:

```bash
ansible-galaxy install -r requirements.yml --upgrade
```

That is an inconsistency with the rest of the project, which pins everything —
worth fixing by pinning them to the versions currently in use, but it needs the
versions read off a working machine first.

---

## See also

- `inventory/group_vars/all/images.yml` — the pins themselves, each with its
  upstream source and any migration warning
- `docs/MEDIA.md` — the media stack's own notes on quality profiles and the VPN
- `roles/media_library/README.md` — the Jellyfin 10 → 12 migration
- `CLAUDE.md` — the constraint that shapes all of this, and the traps
