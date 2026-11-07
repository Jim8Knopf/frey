#!/usr/bin/env python3
"""frey-broker - the only privileged thing the assistant can reach.

Phase 3 of docs/LOCAL_AI_AGENT_PLAN.md. Read verbs only; there is no write
verb in this file yet.

WHY IT IS A DIRECTORY AND NOT A SOCKET OR A PORT

The agent runs in a container on `internal: true` networks. Verified on
2026-11-07: it has no default route and cannot reach the host on any port -
which is deliberate, and is what makes its broad read access safe. So a
host-side HTTP broker is unreachable by construction, and mounting
docker.sock into the agent would hand it the thing this design exists to
withhold.

The channel is therefore a directory. The agent writes a request file; this
service, running on the host, validates it against an allowlist and writes a
response. The agent holds no socket, no port, no shell and no privilege.

WHY AN ALLOWLIST AND NOT A DENYLIST

A denylist of forbidden verbs fails open the moment someone adds a verb. This
dispatches on an exact dict lookup, so an unknown verb has nowhere to go. The
model cannot ask to restart the radios because no entry accepts it.

WHAT IT WILL NEVER DO

There is no verb here that changes anything. No restart, no systemctl start,
no docker, no ansible, no file write outside the response directory. When
write verbs arrive in phase 4 they arrive one at a time, each with a deadman
and a cooldown, and the refusal list in the unit file is enforced by systemd
rather than by this code.
"""

import glob
import json
import logging
import os
import pathlib
import re
import subprocess
import time
import uuid

LOG_LEVEL = os.environ.get("BROKER_LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("broker")

REQ_DIR = pathlib.Path(os.environ.get("BROKER_REQ_DIR", "/broker/req"))
RES_DIR = pathlib.Path(os.environ.get("BROKER_RES_DIR", "/broker/res"))
STATE_DIR = pathlib.Path(os.environ.get("BROKER_STATE_DIR", "/run/frey-broker"))
KILL_SWITCH = pathlib.Path(os.environ.get("BROKER_KILL_SWITCH", "/etc/frey/broker-disabled"))
DOCKER_ROOT = pathlib.Path(os.environ.get("BROKER_DOCKER_ROOT", "/var/lib/docker/containers"))

POLL_SECONDS = float(os.environ.get("BROKER_POLL_SECONDS", "2"))
MAX_PER_MINUTE = int(os.environ.get("BROKER_MAX_PER_MINUTE", "30"))
MAX_LOG_LINES = int(os.environ.get("BROKER_MAX_LOG_LINES", "200"))
MAX_RESPONSE_BYTES = int(os.environ.get("BROKER_MAX_RESPONSE_BYTES", "65536"))
REQUEST_TTL_SECONDS = int(os.environ.get("BROKER_REQUEST_TTL", "600"))

# Allowlists, rendered from Ansible variables. Empty by default is the point:
# this fails closed.
UNIT_ALLOWLIST = set(
    filter(None, (os.environ.get("BROKER_UNITS") or "").split(","))
)
DIAGNOSTIC_ALLOWLIST = {}
for entry in filter(None, (os.environ.get("BROKER_DIAGNOSTICS") or "").split(",")):
    # name=/absolute/path arg
    if "=" in entry:
        name, _, command = entry.partition("=")
        DIAGNOSTIC_ALLOWLIST[name.strip()] = command.strip().split()
CONTAINER_ALLOWLIST = set(
    filter(None, (os.environ.get("BROKER_CONTAINERS") or "").split(","))
)

_recent = []


def rate_limited():
    """Bound the blast radius of a loop, whatever is causing it."""
    now = time.time()
    _recent[:] = [t for t in _recent if now - t < 60]
    if len(_recent) >= MAX_PER_MINUTE:
        return True
    _recent.append(now)
    return False


def disabled():
    return KILL_SWITCH.exists()


# --- verbs ------------------------------------------------------------------
#
# Each returns (ok, payload). None of them changes anything.


def verb_unit_state(args):
    """systemd state for one allowlisted unit.

    The agent cannot reach the host at all, so this is the only way it learns
    whether a timer actually ran. `systemctl show` is read-only.
    """
    unit = str(args.get("unit", ""))
    if unit not in UNIT_ALLOWLIST:
        return False, f"unit not in allowlist: {unit!r}"
    fields = (
        "Id,LoadState,ActiveState,SubState,UnitFileState,"
        "ExecMainStatus,Result,ActiveEnterTimestamp,InactiveEnterTimestamp"
    )
    try:
        out = subprocess.run(
            ["systemctl", "show", unit, "--property", fields, "--no-pager"],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"systemctl failed: {exc}"
    state = {}
    for line in out.stdout.splitlines():
        key, _, value = line.partition("=")
        if key:
            state[key] = value
    return True, state


def verb_diagnostic(args):
    """Output of one allowlisted, read-only diagnostic command.

    These already exist and already have read-only `status` verbs - they are
    what a human would run by hand first. The command line comes from the
    allowlist, never from the request, so the request cannot smuggle
    arguments.
    """
    name = str(args.get("name", ""))
    command = DIAGNOSTIC_ALLOWLIST.get(name)
    if not command:
        return False, f"diagnostic not in allowlist: {name!r}"
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"{name} failed: {exc}"
    return True, {
        "command": " ".join(command),
        "exit_code": out.returncode,
        "stdout": out.stdout[-MAX_RESPONSE_BYTES:],
        "stderr": out.stderr[-4096:],
    }


_ID_RE = re.compile(r"^[0-9a-f]{12,64}$")


def verb_container_logs(args):
    """Tail one allowlisted container's log, read straight off disk.

    Deliberately NOT `docker logs` and deliberately no Docker socket: reading
    the json file needs nothing but root and a path, so the broker gains no
    ability to start, stop or exec anything. It also still works when Loki -
    which normally carries these lines - is itself the thing that broke.

    Docker's json logs can contain NUL-byte holes after an unclean shutdown,
    which is what frey-log-repair exists to fix, so decoding has to tolerate
    damage rather than raise.
    """
    name = str(args.get("container", ""))
    if name not in CONTAINER_ALLOWLIST:
        return False, f"container not in allowlist: {name!r}"
    try:
        lines = min(int(args.get("lines", 50)), MAX_LOG_LINES)
    except (TypeError, ValueError):
        lines = 50

    # Resolve the container id without Docker: config.v2.json carries the name.
    target = None
    for config in glob.glob(str(DOCKER_ROOT / "*" / "config.v2.json")):
        container_id = pathlib.Path(config).parent.name
        if not _ID_RE.match(container_id):
            continue
        try:
            with open(config, "rb") as handle:
                blob = handle.read()
        except OSError:
            continue
        if f'"Name":"/{name}"'.encode() in blob.replace(b" ", b""):
            target = pathlib.Path(config).parent
            break
    if target is None:
        return False, f"no container directory found for {name!r}"

    collected = []
    for path in sorted(target.glob("*-json.log*")):
        try:
            with open(path, "rb") as handle:
                raw = handle.read()[-2_000_000:]
        except OSError:
            continue
        for chunk in raw.split(b"\n"):
            if not chunk.strip(b"\x00 \t"):
                continue
            try:
                entry = json.loads(chunk.replace(b"\x00", b"").decode("utf-8", "replace"))
            except ValueError:
                continue
            text = (entry.get("log") or "").rstrip("\n")
            if text:
                collected.append(text)
    tail = collected[-lines:]
    return True, {"container": name, "lines": len(tail), "log": tail}


VERBS = {
    "unit_state": verb_unit_state,
    "diagnostic": verb_diagnostic,
    "container_logs": verb_container_logs,
}


# --- request loop -----------------------------------------------------------


def respond(request_id, ok, payload, verb=None):
    body = {
        "id": request_id,
        "verb": verb,
        "ok": bool(ok),
        "at": time.time(),
    }
    if ok:
        body["result"] = payload
    else:
        body["error"] = str(payload)
    text = json.dumps(body, default=str)
    if len(text) > MAX_RESPONSE_BYTES:
        body.pop("result", None)
        body["ok"] = False
        body["error"] = "response exceeded the size budget"
        text = json.dumps(body)
    # Write then rename, so a reader never sees a half-written response.
    tmp = RES_DIR / f".{request_id}.partial"
    try:
        tmp.write_text(text)
        tmp.rename(RES_DIR / f"{request_id}.json")
    except OSError as exc:
        log.error("cannot write response %s: %s", request_id, exc)


def handle(path):
    request_id = path.stem
    if not re.match(r"^[A-Za-z0-9_-]{1,64}$", request_id):
        log.warning("ignoring request with a suspicious name: %s", path.name)
        path.unlink(missing_ok=True)
        return
    try:
        request = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        respond(request_id, False, f"unreadable request: {exc}")
        path.unlink(missing_ok=True)
        return
    finally:
        pass

    verb = str(request.get("verb", ""))
    args = request.get("args") or {}
    if not isinstance(args, dict):
        args = {}

    path.unlink(missing_ok=True)

    if disabled():
        log.warning("kill switch set; refusing %s", verb)
        respond(request_id, False, "broker disabled by kill switch", verb)
        return
    if rate_limited():
        log.warning("rate limited; refusing %s", verb)
        respond(request_id, False, "rate limit exceeded", verb)
        return

    # An exact lookup. An unknown verb has nowhere to go - which is how the
    # forbidden actions are absent rather than merely refused.
    handler = VERBS.get(verb)
    if handler is None:
        log.warning("unknown verb refused: %r", verb)
        respond(request_id, False, f"unknown verb: {verb!r}", verb)
        return

    log.info("verb=%s args=%s", verb, json.dumps(args, default=str)[:200])
    try:
        ok, payload = handler(args)
    except Exception as exc:  # a verb must never take the broker down
        log.error("verb %s raised: %s", verb, exc)
        ok, payload = False, f"internal error: {exc}"
    if not ok:
        log.warning("verb=%s refused: %s", verb, payload)
    respond(request_id, ok, payload, verb)


def sweep_old_responses():
    now = time.time()
    for path in RES_DIR.glob("*.json"):
        try:
            if now - path.stat().st_mtime > REQUEST_TTL_SECONDS:
                path.unlink(missing_ok=True)
        except OSError:
            continue


def main():
    for directory in (REQ_DIR, RES_DIR, STATE_DIR):
        try:
            directory.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass
    log.info(
        "broker starting: verbs=%s units=%d diagnostics=%d containers=%d",
        ",".join(sorted(VERBS)),
        len(UNIT_ALLOWLIST),
        len(DIAGNOSTIC_ALLOWLIST),
        len(CONTAINER_ALLOWLIST),
    )
    last_sweep = 0.0
    while True:
        try:
            for path in sorted(REQ_DIR.glob("*.json")):
                handle(path)
            if time.time() - last_sweep > 60:
                sweep_old_responses()
                last_sweep = time.time()
        except Exception as exc:
            log.error("unhandled error in loop: %s", exc)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
