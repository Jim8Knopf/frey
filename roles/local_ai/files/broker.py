#!/usr/bin/env python3
"""frey-broker - the only privileged thing the assistant can reach.

Phases 3 and 4 of docs/LOCAL_AI_AGENT_PLAN.md.

WHAT THE AGENT CAN AND CANNOT DO

Read verbs the agent may call directly: unit_state, diagnostic,
container_logs, propose, proposal_status.

Write actions the agent may NEVER call: recreate_container,
restart_container, rerun_unit. They are not in VERBS at all. The only path to
one is a proposal that a human has approved by typing its id on the host, so
the write path has a person in it by construction rather than by policy.

That asymmetry is deliberate. Deterministic repair of the KNOWN faults is
already autonomous, in frey-self-heal, where a tuned alert rule matched a
symptom and the fix was written by hand. Here the model's judgement is the
thing being trusted - and it has already produced one confident, well
structured, entirely wrong diagnosis.

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

No verb and no action here touches networking, sshd, the firewall, the kernel
command line, or Ansible. Nothing reboots. Nothing writes a file outside the
broker's own queues. Those are absences, not refusals: the code to do them is
not here, and systemd's sandbox in the unit file enforces the rest.

Every executed action arms a deadman that frey-broker-supervisor enforces, so
this process cannot suppress its own failure by crashing or hanging.
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

# --- phase 4: proposals -----------------------------------------------------
#
# The model never invokes a write verb. It can only PROPOSE one, and a
# proposal does nothing until a human approves it by name on the host. So the
# write path has a person in it by construction, not by policy - which matters
# because the model's judgement is the thing being trusted here, and it has
# already produced one confident, well-structured, wrong diagnosis.
PROPOSALS_DIR = pathlib.Path(os.environ.get("BROKER_PROPOSALS_DIR", "/broker/proposals"))
APPROVED_DIR = pathlib.Path(os.environ.get("BROKER_APPROVED_DIR", "/broker/approved"))
DEADMAN_DIR = pathlib.Path(os.environ.get("BROKER_DEADMAN_DIR", "/broker/deadman"))

PROPOSAL_TTL_SECONDS = int(os.environ.get("BROKER_PROPOSAL_TTL", "86400"))

# Containers that may be recreated. Recreation is for a container whose fault
# is baked in at creation - stale DNS being the one real case - so this list
# is deliberately far narrower than the restart list.
RECREATE_ALLOWLIST = set(
    filter(None, (os.environ.get("BROKER_RECREATE") or "").split(","))
)
# Stateless containers only. Every SQLite- or database-backed service is
# absent, and so is the proxy, which would 404 everything at once.
RESTART_ALLOWLIST = set(
    filter(None, (os.environ.get("BROKER_RESTART") or "").split(","))
)
# Oneshot units that are idempotent by design and already run on timers, so
# running one early is indistinguishable from the timer firing.
RERUN_ALLOWLIST = set(
    filter(None, (os.environ.get("BROKER_RERUN") or "").split(","))
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


# --- write actions ----------------------------------------------------------
#
# These are NOT in VERBS. Nothing the agent can call reaches them: they are
# only ever executed from an approved proposal, which requires a human to have
# typed the proposal's id on the host. Each is idempotent, individually
# reviewed, and reversible by hand.


def action_recreate_container(args):
    name = str(args.get("container", ""))
    if name not in RECREATE_ALLOWLIST:
        return False, f"container not recreatable: {name!r}"
    # Recreate, not restart: the stale upstream is fixed at creation time, so
    # a restart would faithfully reproduce the fault.
    rm = subprocess.run(["docker", "rm", "-f", name], capture_output=True, text=True, timeout=120)
    if rm.returncode != 0:
        return False, f"docker rm failed: {rm.stderr.strip()[:300]}"
    # The owning unit brings it back with fresh DNS.
    up = subprocess.run(
        ["systemctl", "start", "frey-media-dns-upstream.service"],
        capture_output=True, text=True, timeout=180,
    )
    if up.returncode != 0:
        return False, f"recreate failed: {up.stderr.strip()[:300]}"
    return True, {"recreated": name}


def action_restart_container(args):
    name = str(args.get("container", ""))
    if name not in RESTART_ALLOWLIST:
        return False, f"container not restartable: {name!r}"
    # `docker restart`, never `docker kill -s HUP`: an API signal flags a
    # container manually-stopped, after which it silently fails to come back
    # at the next reboot.
    out = subprocess.run(
        ["docker", "restart", name], capture_output=True, text=True, timeout=180
    )
    if out.returncode != 0:
        return False, f"docker restart failed: {out.stderr.strip()[:300]}"
    return True, {"restarted": name}


def action_rerun_unit(args):
    unit = str(args.get("unit", ""))
    if unit not in RERUN_ALLOWLIST:
        return False, f"unit not rerunnable: {unit!r}"
    out = subprocess.run(
        ["systemctl", "start", unit], capture_output=True, text=True, timeout=180
    )
    if out.returncode != 0:
        return False, f"systemctl start failed: {out.stderr.strip()[:300]}"
    return True, {"reran": unit}


WRITE_ACTIONS = {
    "recreate_container": action_recreate_container,
    "restart_container": action_restart_container,
    "rerun_unit": action_rerun_unit,
}


def verb_propose(args):
    """Record a proposal. Executes nothing.

    Validation happens HERE as well as at execution time, so a proposal that
    could never be approved is rejected while the model is still in a position
    to be told why.
    """
    action = args.get("action") or {}
    if not isinstance(action, dict):
        return False, "action must be an object"
    verb = str(action.get("verb", ""))
    inner = action.get("args") or {}
    if not isinstance(inner, dict):
        inner = {}
    reason = str(args.get("reason", "")).strip()

    if verb not in WRITE_ACTIONS:
        return False, f"not a proposable action: {verb!r}"
    if len(reason) < 20:
        return False, "a proposal needs a reason of at least 20 characters"

    # Check the target against the same allowlist execution will use, so an
    # un-approvable proposal never reaches the phone.
    target_lists = {
        "recreate_container": ("container", RECREATE_ALLOWLIST),
        "restart_container": ("container", RESTART_ALLOWLIST),
        "rerun_unit": ("unit", RERUN_ALLOWLIST),
    }
    key, allowed = target_lists[verb]
    target = str(inner.get(key, ""))
    if target not in allowed:
        return False, f"{key} not permitted for {verb}: {target!r}"

    proposal_id = uuid.uuid4().hex[:8]
    record = {
        "id": proposal_id,
        "state": "pending",
        "verb": verb,
        "args": {key: target},
        "reason": reason[:1000],
        "created": time.time(),
        "notified": False,
    }
    try:
        (PROPOSALS_DIR / f"{proposal_id}.json").write_text(json.dumps(record, indent=1))
    except OSError as exc:
        return False, f"cannot record proposal: {exc}"
    log.info("proposal %s recorded: %s %s", proposal_id, verb, target)
    return True, {
        "proposal_id": proposal_id,
        "state": "pending",
        "approve_with": f"frey-broker-approve {proposal_id}",
        "note": "nothing runs until a human approves this on the host",
    }


def verb_proposal_status(args):
    proposal_id = str(args.get("proposal_id", ""))
    if not re.match(r"^[0-9a-f]{8}$", proposal_id):
        return False, "malformed proposal id"
    path = PROPOSALS_DIR / f"{proposal_id}.json"
    try:
        record = json.loads(path.read_text())
    except (OSError, ValueError):
        return False, f"no such proposal: {proposal_id}"
    return True, {
        k: record.get(k)
        for k in ("id", "state", "verb", "args", "created", "executed", "error")
    }


VERBS = {
    "unit_state": verb_unit_state,
    "diagnostic": verb_diagnostic,
    "container_logs": verb_container_logs,
    "propose": verb_propose,
    "proposal_status": verb_proposal_status,
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


def health_snapshot():
    """A number that should not get worse after a repair.

    Two counts, both cheap and both network-free: containers that ought to be
    running and are not, and alerts currently firing. Imported by the
    supervisor so "before" and "after" are measured by identical code - a
    deadman comparing two different definitions of health is worse than none.
    """
    stopped = None
    firing = None
    try:
        out = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.Names}}\t{{.State}}"],
            capture_output=True, text=True, timeout=30,
        )
        if out.returncode == 0:
            watched = RESTART_ALLOWLIST | RECREATE_ALLOWLIST | CONTAINER_ALLOWLIST
            stopped = 0
            for line in out.stdout.splitlines():
                name, _, state = line.partition("\t")
                if name in watched and state.strip() != "running":
                    stopped += 1
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        # CRITICAL alerts only, and this is load-bearing. A count of ALL
        # firing alerts tripped the deadman on its first real run: the total
        # went 2 -> 3 after re-running a metrics collector, which cannot
        # possibly cause an alert. On this Pi the warning tier flaps
        # constantly - the 5V rail hovers right at its threshold, container
        # memory is high because the model itself is 4 GiB - and the Watchdog
        # heartbeat alert fires permanently by design. Counting those makes
        # every action look harmful.
        #
        # Criticals are rare here and are what actually matters, so a new one
        # appearing right after a repair is a signal worth stopping for.
        #
        # Alertmanager has no host port, so it is reached from inside a
        # container that can - the same reason the rest of this stack does.
        out = subprocess.run(
            ["docker", "exec", "alert-relay", "python3", "-c",
             "import json,urllib.request;"
             "o=urllib.request.build_opener(urllib.request.ProxyHandler({}));"
             "a=json.load(o.open('http://alertmanager:9093/api/v2/alerts"
             "?active=true&silenced=false&inhibited=false',timeout=10));"
             "print(sum(1 for x in a if (x.get('labels') or {})"
             ".get('severity')=='critical'))"],
            capture_output=True, text=True, timeout=40,
        )
        if out.returncode == 0:
            firing = int(out.stdout.strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return {"stopped_containers": stopped, "critical_alerts": firing, "at": time.time()}


def execute_approved():
    """Run proposals a human has approved, and arm a deadman for each.

    Re-validates from scratch. The approval marker carries no action of its
    own - only an id - so approving cannot smuggle a different verb, and a
    proposal whose target has since been removed from the allowlist stops
    being executable.
    """
    try:
        markers = sorted(APPROVED_DIR.glob("*"))
    except OSError:
        return
    for marker in markers:
        proposal_id = marker.name
        if not re.match(r"^[0-9a-f]{8}$", proposal_id):
            marker.unlink(missing_ok=True)
            continue
        path = PROPOSALS_DIR / f"{proposal_id}.json"
        try:
            record = json.loads(path.read_text())
        except (OSError, ValueError):
            log.warning("approval for unknown proposal %s", proposal_id)
            marker.unlink(missing_ok=True)
            continue
        marker.unlink(missing_ok=True)

        if record.get("state") != "pending":
            log.warning("proposal %s is %s, not executing", proposal_id, record.get("state"))
            continue
        if disabled():
            log.warning("kill switch set; not executing proposal %s", proposal_id)
            continue

        handler = WRITE_ACTIONS.get(record.get("verb", ""))
        if handler is None:
            record["state"] = "refused"
            record["error"] = "verb is no longer a write action"
            path.write_text(json.dumps(record, indent=1))
            continue

        before = health_snapshot()
        log.info("executing approved proposal %s: %s %s",
                 proposal_id, record["verb"], record.get("args"))
        try:
            ok, payload = handler(record.get("args") or {})
        except Exception as exc:
            ok, payload = False, f"internal error: {exc}"

        record["state"] = "done" if ok else "failed"
        record["executed"] = time.time()
        if ok:
            record["result"] = payload
        else:
            record["error"] = str(payload)
        try:
            path.write_text(json.dumps(record, indent=1))
        except OSError:
            pass

        if ok:
            # Arm the deadman. The supervisor enforces it, so the broker
            # cannot suppress its own failure by crashing or hanging.
            try:
                (DEADMAN_DIR / f"{proposal_id}.json").write_text(json.dumps({
                    "proposal_id": proposal_id,
                    "verb": record["verb"],
                    "args": record.get("args"),
                    "armed_at": time.time(),
                    "before": before,
                }, indent=1))
                log.info("deadman armed for %s", proposal_id)
            except OSError as exc:
                log.error("could not arm deadman for %s: %s", proposal_id, exc)
        else:
            log.warning("proposal %s failed: %s", proposal_id, payload)


def sweep_old_proposals():
    now = time.time()
    for path in PROPOSALS_DIR.glob("*.json"):
        try:
            if now - path.stat().st_mtime > PROPOSAL_TTL_SECONDS:
                path.unlink(missing_ok=True)
        except OSError:
            continue


def sweep_old_responses():
    now = time.time()
    for path in RES_DIR.glob("*.json"):
        try:
            if now - path.stat().st_mtime > REQUEST_TTL_SECONDS:
                path.unlink(missing_ok=True)
        except OSError:
            continue


def main():
    for directory in (REQ_DIR, RES_DIR, STATE_DIR,
                      PROPOSALS_DIR, APPROVED_DIR, DEADMAN_DIR):
        try:
            directory.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass
    log.info(
        "broker starting: verbs=%s units=%d diagnostics=%d containers=%d "
        "write_actions=%s recreate=%d restart=%d rerun=%d",
        ",".join(sorted(VERBS)),
        len(UNIT_ALLOWLIST),
        len(DIAGNOSTIC_ALLOWLIST),
        len(CONTAINER_ALLOWLIST),
        ",".join(sorted(WRITE_ACTIONS)),
        len(RECREATE_ALLOWLIST),
        len(RESTART_ALLOWLIST),
        len(RERUN_ALLOWLIST),
    )
    last_sweep = 0.0
    while True:
        try:
            for path in sorted(REQ_DIR.glob("*.json")):
                handle(path)
            # Approved proposals are the only path to a write action.
            execute_approved()
            if time.time() - last_sweep > 60:
                sweep_old_responses()
                sweep_old_proposals()
                last_sweep = time.time()
        except Exception as exc:
            log.error("unhandled error in loop: %s", exc)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
