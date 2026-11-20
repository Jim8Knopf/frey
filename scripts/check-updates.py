#!/usr/bin/env python3
"""Compare every container image against upstream, and optionally bump it.

inventory/group_vars/all/images.yml holds one line per image, registry and
tag together, and `frey_images` is the only place an image is named. This
script reads that file, asks each image's upstream where it is now, and can
rewrite the tags in place.

It replaced two overlapping checkers that each knew about some of the images
and neither knew about eleven: a media-only shell script, and an 88-line
Python block inside scripts/monitoring-check.sh with its own registry of ten
repositories. The cause was that the upstream source lived in the script while
the image lived in images.yml, so adding one meant editing two files and
forgetting the second produced silence rather than an error.

The source now lives on the image's own line as an `# upstream:` marker, and
tests/test_image_versions.py fails the build if one is missing.

    scripts/check-updates.py                # what has moved
    scripts/check-updates.py --apply        # rewrite the tags that moved
    scripts/check-updates.py --offline      # no network: images and owners
    scripts/check-updates.py --only jelly   # one image, or any name substring

Only the TAG is ever rewritten; the registry path, the marker and any prose on
the line survive untouched.

Nothing is deployed. --apply edits one file; it tells you what to run next.

Needs internet for anything but --offline. Run it before you leave a place
that has some.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - CI installs PyYAML
    sys.exit("python3 yaml module is required (pip install pyyaml)")

ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "inventory/group_vars/all/images.yml"
REGISTRY = ROOT / "inventory/group_vars/all/main.yml"

USER_AGENT = {"User-Agent": "frey-check-updates"}
TIMEOUT = 30

# A pin line: `  name: "tag"  # upstream: <marker>`, at any indent, with the
# marker optional so a missing one can be reported rather than crash.
PIN_RE = re.compile(
    r'^(?P<indent>\s*)(?P<key>[a-z0-9_]+):\s*'
    r'(?P<quote>["\']?)(?P<value>[^"\'#\s]+)(?P=quote)'
    r'(?:\s*#\s*upstream:\s*(?P<marker>.*?))?\s*$'
)
# A top-level mapping that opens a group of pins, e.g. `media_versions:`.
GROUP_RE = re.compile(r'^(?P<key>[a-z0-9_]+):\s*$')


# --------------------------------------------------------------------------
# Reading the pins
# --------------------------------------------------------------------------
def split_image(reference):
    """"repo:tag[@sha256:...]" -> (repo, tag, digest).

    The tag is everything after the LAST colon that is not inside a digest and
    not part of a registry host:port. A reference with no tag at all yields "".
    """
    digest = ""
    body = reference or ""
    if "@" in body:
        body, _, digest = body.partition("@")
    repo, sep, tail = body.rpartition(":")
    if not sep or "/" in tail:
        # No tag: either no colon at all, or the colon belonged to a
        # registry host:port and what followed was a path.
        return body, "", digest
    return repo, tail, digest


def join_image(repo, tag, digest=""):
    out = f"{repo}:{tag}" if tag else repo
    return f"{out}@{digest}" if digest else out


class Pin:
    """One image entry, and where its line is so --apply can rewrite it."""

    def __init__(self, name, value, marker, lineno, group):
        self.name = name          # "jellyfin"
        self.image = value        # "lscr.io/linuxserver/jellyfin:12.3ubu2604-ls56"
        self.repo, self.value, self.digest = split_image(value)
        # self.value is the TAG - what is compared against upstream. Named
        # `value` because every comparison helper below speaks in tags.
        self.marker = marker      # "lsio:prowlarr" or "hold - reason" or None
        self.lineno = lineno      # 0-based index into the file's lines
        self.group = group        # "frey_images"
        self.latest = None        # upstream version as upstream spells it
        self.proposed = None      # that version respelled in this pin's shape
        self.state = "unknown"    # held | current | behind | major | unknown
        self.detail = ""

    @property
    def proposed_image(self):
        """The full reference --apply would write."""
        if not self.proposed:
            return self.image
        return join_image(self.repo, self.proposed, self.digest)

    @property
    def no_apply(self):
        """`watch` pins are reported but never rewritten by --apply.

        For a pin where knowing a release exists is useful but the version
        number cannot tell you whether to take it - the served model still has
        to be mapped, the login header still has to auto-register.
        """
        return bool(self.marker) and self.marker.strip().startswith("watch ")

    @property
    def _body(self):
        marker = (self.marker or "").strip()
        if marker.startswith("watch "):
            return marker[len("watch "):].strip()
        return marker

    @property
    def resolver(self):
        if not self.marker:
            return None
        return self._body.split(":", 1)[0].split(" ", 1)[0].strip()

    @property
    def locator(self):
        body = self._body
        if ":" not in body:
            return ""
        return body.split(":", 1)[1].strip()


def read_pins(path=IMAGES):
    """Parse images.yml line by line, keeping line numbers and markers.

    Deliberately not yaml.safe_load: that discards the comments the upstream
    markers live in and the line numbers --apply needs. The parsed values are
    cross-checked against safe_load in tests/test_image_versions.py, so this
    looser parse cannot drift from what Ansible actually reads.
    """
    lines = path.read_text().splitlines()
    pins, group = [], ""
    for i, line in enumerate(lines):
        if not line.strip() or line.lstrip().startswith("#") or line.startswith("---"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            group = ""
            m = GROUP_RE.match(line)
            if m:
                group = m.group("key")
                continue
        m = PIN_RE.match(line)
        if not m:
            continue
        key = m.group("key")
        # Everything lives under the single `frey_images:` mapping, so the
        # group name adds nothing to a pin's identity - "jellyfin" reads
        # better than "frey_images.jellyfin" in a table and in --only.
        name = key if group in ("", "frey_images") else f"{group}.{key}"
        marker = (m.group("marker") or "").strip() or None
        pins.append(Pin(name, m.group("value"), marker, i, group if indent else ""))
    return lines, pins


# --------------------------------------------------------------------------
# Version shapes
# --------------------------------------------------------------------------
LS_SUFFIX = re.compile(r'-ls\d+$')


def split_shape(tag):
    """Split a tag into (prefix, core, ls_suffix).

    The prefix is everything before the first digit - "version-v", "v",
    "server-" or "". Keeping it is what lets an upstream version be respelled
    in the pin's own convention: linuxserver's "v1.6.2-ls123" has to become
    "version-v1.6.2" for bazarr but "version-5.3.0_v2.1.2" for qbittorrent,
    and the difference is entirely in the pin, not upstream.
    """
    tag = tag or ""
    ls = ""
    m = LS_SUFFIX.search(tag)
    if m:
        ls, tag = m.group(0), tag[: m.start()]
    m = re.search(r'\d', tag)
    if not m:
        return tag, "", ls
    return tag[: m.start()], tag[m.start():], ls


def core_of(tag):
    """The comparable version body: no leading v, no linuxserver build suffix."""
    _, core, _ = split_shape(LS_SUFFIX.sub("", tag or ""))
    return core


def respell(pinned, upstream):
    """Write `upstream` the way `pinned` is written."""
    prefix, _, pin_ls = split_shape(pinned)
    _, up_core, up_ls = split_shape(upstream)
    # A pin that carries linuxserver's build suffix wants upstream's too;
    # one that does not (qbittorrent, prowlarr) must not grow one.
    return prefix + up_core + (up_ls if pin_ls else "")


def numeric_parts(core):
    out = []
    for chunk in re.split(r'[.\-_]', core or ""):
        m = re.match(r'\d+', chunk)
        if not m:
            break
        out.append(int(m.group(0)))
    return out


def compare(pinned, upstream):
    """Classify the pin against upstream: current, behind, or major."""
    p, u = core_of(pinned), core_of(upstream)
    if not p or not u:
        return "unknown"
    if p == u:
        return "current"
    # A deliberately short pin tracks a line that moves on its own: "1"
    # against upstream 1.10.8 is correct, not stale.
    if u.startswith(p + "."):
        return "current"
    pn, un = numeric_parts(p), numeric_parts(u)
    if pn and un and un[0] != pn[0]:
        return "major"
    if pn and un and un < pn:
        # Pinned ahead of the latest release: a prerelease, or upstream
        # publishing images the release feed does not know about.
        return "current"
    return "behind"


# --------------------------------------------------------------------------
# Upstream lookups
# --------------------------------------------------------------------------
def get_json(url):
    req = urllib.request.Request(url, headers=USER_AGENT)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp)


_LSIO_CACHE = {}


def lsio_versions():
    if not _LSIO_CACHE:
        try:
            data = get_json(
                "https://api.linuxserver.io/api/v1/images?include_config=false"
            )
            for img in data["data"]["repositories"]["linuxserver"]:
                _LSIO_CACHE[img["name"]] = img.get("version")
        except Exception:  # noqa: BLE001 - a failed lookup is reported, not raised
            _LSIO_CACHE["__failed__"] = True
    return _LSIO_CACHE


def resolve(pin):
    """Fill in pin.latest. Returns an error string, or "" on success."""
    kind = pin.resolver
    try:
        if kind == "github":
            pin.latest = get_json(
                "https://api.%s.com/repos/%s/releases/latest"
                % ("github", pin.locator)
            ).get("tag_name")
            if not pin.latest:
                return "no release tag"
        elif kind == "lsio":
            versions = lsio_versions()
            if versions.get("__failed__"):
                return "linuxserver API unreachable"
            pin.latest = versions.get(pin.locator)
            if not pin.latest:
                return "not in the linuxserver image list"
        elif kind == "dockerhub":
            data = get_json(
                "https://hub.docker.com/v2/repositories/%s/tags"
                "?page_size=100&ordering=last_updated" % pin.locator
            )
            best = None
            for tag in data.get("results", []):
                name = tag.get("name", "")
                if not re.fullmatch(r'v?\d+(\.\d+)*', name):
                    continue
                key = numeric_parts(core_of(name))
                if best is None or key > best[0]:
                    best = (key, name)
            if not best:
                return "no semver-looking tag found"
            pin.latest = best[1]
        else:
            return "unknown resolver %r" % kind
    except urllib.error.HTTPError as exc:
        return "HTTP %s" % exc.code
    except Exception as exc:  # noqa: BLE001 - network, DNS, JSON shape
        return type(exc).__name__
    return ""


# --------------------------------------------------------------------------
# Who deploys this pin
# --------------------------------------------------------------------------
def module_tags():
    """module name -> (role, tags) from the registry in main.yml."""
    data = yaml.safe_load(REGISTRY.read_text()) or {}
    available = (((data.get("frey") or {}).get("modules") or {}).get("available")) or {}
    by_role = {}
    for module, spec in available.items():
        by_role[spec.get("role", module)] = (module, spec.get("tags") or [module])
    return by_role


def owners(pins):
    """pin name -> sorted list of deploy tags, found by who reads the variable.

    Derived rather than configured: the pin's owning role is whichever role
    mentions the variable, so this cannot fall out of date the way a hand-kept
    mapping would.
    """
    by_role = module_tags()
    searchable = {}
    for role_dir in sorted((ROOT / "roles").iterdir()):
        if not role_dir.is_dir():
            continue
        blob = []
        for path in role_dir.rglob("*"):
            if path.is_file() and path.suffix in (".yml", ".yaml", ".j2"):
                try:
                    blob.append(path.read_text())
                except OSError:
                    continue
        searchable[role_dir.name] = "\n".join(blob)

    result = {}
    for pin in pins:
        needle = "frey_images.%s" % pin.name
        tags = set()
        for role, blob in searchable.items():
            if needle in blob:
                _, role_tags = by_role.get(role, (role, [role]))
                tags.update(role_tags)
        result[pin.name] = sorted(tags)
    return result


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------
MARK = {
    "behind": "->",
    "major": "!!",
    "current": "  ",
    "held": "::",
    "unknown": " ?",
}


def report(pins, deploy, show_current):
    width = max((len(p.name) for p in pins), default=10)
    vwidth = min(max((len(p.image) for p in pins), default=10), 58)
    print()
    print("%s  %s     upstream" % ("image".ljust(width), "deployed".ljust(vwidth)))
    print("-" * (width + vwidth + 30))
    for pin in pins:
        if pin.state == "current" and not show_current:
            continue
        shown = {
            "behind": lambda: pin.proposed + (
                "  (watch - apply by hand)" if pin.no_apply else ""),
            "major": lambda: "%s  (MAJOR)" % pin.proposed,
            "current": lambda: "up to date",
            "held": lambda: "held - %s" % pin.detail,
            "unknown": lambda: "could not check: %s" % pin.detail,
        }[pin.state]()
        print("%s  %s  %s %s" % (
            pin.name.ljust(width), pin.image.ljust(vwidth), MARK[pin.state], shown))

    behind = [p for p in pins if p.state == "behind" and not p.no_apply]
    watched = [p for p in pins if p.state == "behind" and p.no_apply]
    major = [p for p in pins if p.state == "major"]
    unknown = [p for p in pins if p.state == "unknown"]

    print()
    if behind:
        tags = sorted({t for p in behind for t in deploy.get(p.name, [])})
        print("%d pin(s) have a newer upstream version." % len(behind))
        print("  apply:  scripts/check-updates.py --apply")
        if tags:
            print("  deploy: ansible-playbook playbooks/site.yml --tags %s"
                  % ",".join(tags))
        else:
            print("  deploy: no owning role found for those pins")
    if watched:
        print()
        print("%d `watch` pin(s) moved. --apply will not touch these - the"
              % len(watched))
        print("  version number alone cannot say whether to take them:")
        for pin in watched:
            print("    %s %s -> %s" % (pin.name, pin.image, pin.proposed_image))
        print("  Read the release notes and the comment above the pin, then")
        print("  edit inventory/group_vars/all/images.yml by hand.")
    if major:
        print()
        print("%d pin(s) have a new MAJOR version. --apply will not touch these:"
              % len(major))
        for pin in major:
            print("    %s %s -> %s" % (pin.name, pin.image, pin.proposed_image))
        print("  A major is a migration, not a bump. Read the release notes,")
        print("  then edit images.yml by hand, or pass --allow-major.")
    if unknown:
        print()
        print("%d pin(s) could not be checked - a failed lookup is not a"
              % len(unknown))
        print("  reason to believe a pin is current.")
    if not behind and not watched and not major and not unknown:
        print("Everything checked is on its latest known version.")
    print()
    print("Upstream is the project's latest RELEASE. A few projects tag releases")
    print("differently from their published images, so confirm the tag exists")
    print("before deploying:  docker manifest inspect <image>:<tag>")
    print()


def apply_changes(lines, pins, allow_major):
    """Rewrite pin values in `lines`, leaving every comment untouched.

    Mutates `lines` and returns the pins it changed. Deliberately does not
    touch the file: the caller writes it, so this is testable without a test
    being able to rewrite the real images.yml.
    """
    changed = []
    for pin in pins:
        if pin.no_apply:
            continue
        if pin.state == "behind" or (pin.state == "major" and allow_major):
            line = lines[pin.lineno]
            # Replace only the TAG inside the quoted reference, so the
            # registry path, the trailing `# upstream:` marker and any prose
            # on the line survive exactly as written.
            new_line, count = re.subn(
                r'(%s:\s*["\']?)%s(["\']?)' % (
                    re.escape(pin.name), re.escape(pin.image)),
                lambda m: m.group(1) + pin.proposed_image + m.group(2),
                line, count=1,
            )
            if count != 1:
                print("refusing to rewrite %s: its line did not match cleanly"
                      % pin.name, file=sys.stderr)
                continue
            lines[pin.lineno] = new_line
            changed.append(pin)
    return changed


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Check, and optionally bump, every pinned image version.")
    ap.add_argument("--apply", action="store_true",
                    help="rewrite pins that are behind, in images.yml")
    ap.add_argument("--allow-major", action="store_true",
                    help="with --apply, also bump across a major version")
    ap.add_argument("--offline", action="store_true",
                    help="no network: list pins, markers and owning tags")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--only", metavar="TEXT",
                    help="only pins whose dotted name contains TEXT")
    ap.add_argument("--all", action="store_true",
                    help="also list pins that are already up to date")
    args = ap.parse_args(argv)

    try:
        lines, pins = read_pins()
    except OSError as exc:
        sys.exit("cannot read %s: %s" % (IMAGES, exc))
    if not pins:
        sys.exit("no pins found in %s" % IMAGES)

    if args.only:
        pins = [p for p in pins if args.only in p.name]
        if not pins:
            sys.exit("no pin matches %r" % args.only)

    deploy = owners(pins)

    missing = [p.name for p in pins if not p.marker]
    for pin in pins:
        if not pin.marker:
            pin.state, pin.detail = "unknown", "no `# upstream:` marker"
        elif pin.resolver == "hold":
            pin.state = "held"
            pin.detail = pin.marker.partition("-")[2].strip() or "set by hand"

    if args.offline:
        if args.json:
            print(json.dumps([
                {"image": p.name, "reference": p.image, "tag": p.value,
                 "upstream": p.marker,
                 "deploy_tags": deploy.get(p.name, [])} for p in pins], indent=2))
        else:
            width = max(len(p.name) for p in pins)
            iwidth = min(max(len(p.image) for p in pins), 62)
            print()
            for pin in pins:
                print("%s  %-*s  %-52s  %s" % (
                    pin.name.ljust(width), iwidth, pin.image,
                    pin.marker or "NO MARKER",
                    ",".join(deploy.get(pin.name, [])) or "-"))
            print("\n%d pins." % len(pins))
        return 1 if missing else 0

    checkable = [p for p in pins if p.state != "held" and p.marker]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for pin, err in zip(checkable, pool.map(resolve, checkable)):
            if err:
                pin.state, pin.detail = "unknown", err
                continue
            pin.proposed = respell(pin.value, pin.latest)
            pin.state = compare(pin.value, pin.latest)
            if pin.state == "unknown":
                pin.detail = "cannot compare %r with %r" % (pin.value, pin.latest)

    if args.json:
        print(json.dumps([
            {"image": p.name, "reference": p.image, "tag": p.value,
             "upstream_latest": p.latest, "proposed_tag": p.proposed,
             "proposed_reference": p.proposed_image if p.proposed else None,
             "state": p.state, "detail": p.detail,
             "deploy_tags": deploy.get(p.name, [])} for p in pins], indent=2))
    else:
        report(pins, deploy, show_current=args.all)

    if args.apply:
        changed = apply_changes(lines, pins, args.allow_major)
        if not changed:
            print("Nothing to apply.")
            return 0
        IMAGES.write_text("\n".join(lines) + "\n")
        tags = sorted({t for p in changed for t in deploy.get(p.name, [])})
        print("Rewrote %d pin(s) in %s:"
              % (len(changed), IMAGES.relative_to(ROOT)))
        for pin in changed:
            print("    %s  %s -> %s" % (pin.name, pin.image, pin.proposed_image))
        print()
        print("Review the diff, then deploy:")
        print("    git diff -- %s" % IMAGES.relative_to(ROOT))
        print("    ansible-playbook playbooks/site.yml --tags %s" % ",".join(tags))
        print()
        print("Deploy twice. The second run must report 0 changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
