#!/usr/bin/env bash
# =============================================================================
# media-check-updates.sh - compare pinned media image versions against upstream
# =============================================================================
#
# Reads media_versions from inventory/group_vars/all/images.yml and reports what
# has moved upstream, so updating is "read this list, edit that one file"
# instead of hunting through roles and registries.
#
# Nothing is changed. The output is advice.
#
#   ./scripts/media-check-updates.sh
#
# Then edit inventory/group_vars/all/images.yml and apply:
#
#   ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
#     --tags media --vault-password-file .vault_pass
#
# Needs internet, obviously. Run it before you leave a place that has some.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARS_FILE="${REPO_ROOT}/inventory/group_vars/all/images.yml"

if [ ! -r "${VARS_FILE}" ]; then
  echo "cannot read ${VARS_FILE}" >&2
  exit 1
fi

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

python3 - "$VARS_FILE" <<'PYTHON'
import json
import sys
import urllib.error
import urllib.request

try:
    import yaml
except ImportError:
    sys.exit("python3 yaml module is required (pip install pyyaml)")

versions = (yaml.safe_load(open(sys.argv[1])) or {}).get("media_versions", {})
if not versions:
    sys.exit("no media_versions found in " + sys.argv[1])


def get_json(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


# linuxserver.io publishes the authoritative current version for its images.
def lsio_latest():
    try:
        data = get_json("https://api.linuxserver.io/api/v1/images?include_config=false")
        return {
            img["name"]: img.get("version")
            for img in data["data"]["repositories"]["linuxserver"]
        }
    except Exception:
        return {}


def gh_latest(repo):
    try:
        return get_json(f"https://api.github.com/repos/{repo}/releases/latest").get("tag_name")
    except Exception:
        return None


def hub_latest(repo):
    """Newest semver-looking tag on Docker Hub."""
    try:
        data = get_json(
            f"https://hub.docker.com/v2/repositories/{repo}/tags?page_size=100&ordering=last_updated"
        )
    except Exception:
        return None
    import re

    best = None
    for tag in data.get("results", []):
        name = tag["name"]
        if not re.fullmatch(r"v?\d+(\.\d+)*", name):
            continue
        key = [int(p) for p in name.lstrip("v").split(".")]
        if best is None or key > best[0]:
            best = (key, name)
    return best[1] if best else None


def strip_ls(version):
    """Drop linuxserver's own -lsNNN build suffix."""
    import re

    return re.sub(r"-ls\d+$", "", version or "")


def norm(version):
    return (version or "").removeprefix("version-").lstrip("v")


def same_version(pinned, latest):
    """Is `pinned` already tracking `latest`?

    A deliberately short pin is not out of date. Tags like "1" or "v3" track
    a major line and move on their own, so "1" against upstream 1.10.8 is
    correct, not stale - only a longer, differing version is a real update.
    """
    # Strip the -lsNNN build suffix from BOTH sides: a pin may carry it too
    # (jellyfin is pinned as "12.3ubu2604-ls56"), and comparing a stripped
    # upstream against an unstripped pin never matches.
    p, l = norm(strip_ls(pinned)), norm(strip_ls(latest))
    if not p or not l:
        return False
    if p == l:
        return True
    # pinned is a shorter prefix on a version-component boundary -> tracking
    return l.startswith(p + ".")


# name in media_versions -> how to find its current upstream version
LSIO = {"jellyfin", "prowlarr", "sonarr", "radarr", "lidarr", "bazarr", "qbittorrent"}
GITHUB = {
    "navidrome": "navidrome/navidrome",
    "audiobookshelf": "advplyr/audiobookshelf",
    "seerr": "seerr-team/seerr",
    "maintainerr": "jorenn92/Maintainerr",
    "jellystat": "CyferShepard/Jellystat",
    "recyclarr": "recyclarr/recyclarr",
    "cleanuparr": "Cleanuparr/Cleanuparr",
    "unpackerr": "Unpackerr/unpackerr",
    "byparr": "ThePhaseless/Byparr",
    "gluetun": "qdm12/gluetun",
}
HUB = {
    "chaptarr": "chaptarr/chaptarr",
    "audiobookrequest": "markbeep/audiobookrequest",
    "dnsmasq": "dockurr/dnsmasq",
}
SKIP = {
    "jellystat_db": "PostgreSQL major upgrades need a migration, not a bump - check deliberately",
}

lsio = lsio_latest()
rows, notes = [], []

for name in sorted(versions):
    pinned = str(versions[name])
    if name in SKIP:
        notes.append(f"{name}: pinned {pinned} - {SKIP[name]}")
        continue
    if name in LSIO:
        latest = lsio.get(name)
        # linuxserver reports "<upstream>-lsNNN", where -lsNNN is their own
        # build number. Compare only the upstream part, or every image looks
        # permanently out of date.
        current = latest
        same = latest is not None and same_version(pinned, strip_ls(latest))
    elif name in GITHUB:
        latest = gh_latest(GITHUB[name])
        current = latest
        same = latest is not None and same_version(pinned, latest)
    elif name in HUB:
        latest = hub_latest(HUB[name])
        current = latest
        same = latest is not None and same_version(pinned, latest)
    else:
        notes.append(f"{name}: no upstream source configured in this script")
        continue
    rows.append((name, pinned, current, same))

width = max((len(r[0]) for r in rows), default=10)
print()
print(f"{'service'.ljust(width)}  {'pinned'.ljust(26)}  upstream")
print("-" * (width + 56))
outdated = 0
unknown = 0
for name, pinned, latest, same in rows:
    if latest is None:
        mark, shown = "  ?", "could not check"
        unknown += 1
    elif same:
        mark, shown = "   ", "up to date"
    else:
        mark, shown = " ->", str(latest)
        outdated += 1
    print(f"{name.ljust(width)}  {pinned.ljust(26)} {mark} {shown}")

print()
if outdated:
    print(f"{outdated} image(s) have a newer upstream version.")
    print("For a linuxserver image, the tag is 'version-' + the upstream version shown.")
    print("Upstream here is the project's latest RELEASE; a few projects tag")
    print("releases differently from their published images, so check the tag")
    print("exists before applying:  docker manifest inspect <image>:<tag>")
    print()
    print("Edit:  inventory/group_vars/all/images.yml")
    print("Apply: ansible-playbook -i inventory/hosts.yml playbooks/site.yml \\")
    print("         --tags media --vault-password-file .vault_pass")
elif not unknown:
    print("All checked images are on their latest known versions.")
else:
    print("No updates found among checked images; some checks failed.")
if unknown:
    print(f"{unknown} image(s) could not be checked.")
for note in notes:
    print("note: " + note)
print()
PYTHON
