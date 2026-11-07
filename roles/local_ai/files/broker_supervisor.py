#!/usr/bin/env python3
"""frey-broker-supervisor - notifies about proposals and enforces the deadman.

Phase 4 of docs/LOCAL_AI_AGENT_PLAN.md. Two jobs, both of which the broker
itself cannot do:

1. REACH THE PHONE. The broker runs with PrivateNetwork=yes and has no
   network at all, which is deliberate - its channel is a directory. So
   something else has to deliver, and keeping that here means it lives in the
   component with no model input and no privilege over containers. Delivery
   goes through the existing alert relay rather than straight to ntfy; see
   notify() for why that turned out to be both necessary and better.

2. ENFORCE THE DEADMAN. The broker arms one before every executed action and
   records the health it measured beforehand. This re-measures afterwards with
   the SAME code - health_snapshot is imported, not reimplemented, because a
   deadman comparing two different definitions of health is worse than none -
   and if health got worse it trips the kill switch and pushes a critical
   alert. Being a separate process is the point: the broker cannot suppress
   its own failure by crashing, hanging, or choosing not to look.

There is no automatic revert. A blind undo is itself an unattended action
taken while the system is already degraded, which is how one fault becomes
two. Every action the broker can take is reversible by hand, and the breaker
plus a named alert is what gets a human involved.
"""

import json
import logging
import os
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from broker import health_snapshot  # noqa: E402  (same code, by design)

logging.basicConfig(
    level=getattr(logging, os.environ.get("BROKER_LOG_LEVEL", "INFO").upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("broker-supervisor")

NODE = os.environ.get("FREY_NODE", "frey")
PROPOSALS_DIR = pathlib.Path(os.environ.get("BROKER_PROPOSALS_DIR", "/broker/proposals"))
DEADMAN_DIR = pathlib.Path(os.environ.get("BROKER_DEADMAN_DIR", "/broker/deadman"))
KILL_SWITCH = pathlib.Path(os.environ.get("BROKER_KILL_SWITCH", "/etc/frey/broker-disabled"))

RELAY_CONTAINER = os.environ.get("RELAY_CONTAINER", "alert-relay")
RELAY_PORT = os.environ.get("RELAY_PORT", "8080")

# How long after an action to judge it. Long enough for a restarted container
# to come back and for Prometheus to scrape it again, short enough that a
# genuinely harmful action is caught while you might still be awake.
GRACE_SECONDS = int(os.environ.get("BROKER_DEADMAN_GRACE", "180"))
APPROVE_COMMAND = os.environ.get("BROKER_APPROVE_COMMAND", "frey-broker-approve")


def notify(title, body, severity="warning"):
    """Deliver through the existing alert relay, not straight to ntfy.

    Two reasons, and the first is what forced it: the ntfy topic is GENERATED
    into /opt/frey/appdata/monitoring/.monitoring-keys.json rather than stored
    in the vault, so it is not available from inventory - and that file is
    deliberately InaccessiblePaths here, because it is credential material.
    Reading it would mean punching a hole for a secret.

    The second reason is better anyway: the relay already owns ntfy delivery
    AND holds undelivered messages on disk with the time they really fired,
    flushing them when an uplink appears. In a van that is most of the value.
    So this hands it an Alertmanager-shaped payload, exactly as the observer
    does, and inherits all of it.

    Reached by `docker exec` because the relay has no host port - nothing in
    monitoring is reachable from the host by address.
    """
    payload = {
        "alerts": [{
            "status": "firing",
            "labels": {
                "alertname": "FreyBrokerProposal" if severity == "warning"
                             else "FreyBrokerDeadmanTripped",
                "severity": severity,
                "service": "local-ai-broker",
            },
            "annotations": {"summary": title, "description": body[:1500]},
        }]
    }
    try:
        out = subprocess.run(
            ["docker", "exec", "-i", RELAY_CONTAINER, "python3", "-c",
             "import json,sys,urllib.request;"
             "d=sys.stdin.read().encode();"
             "r=urllib.request.Request('http://127.0.0.1:%s/alert',data=d,"
             "headers={'Content-Type':'application/json'});"
             "o=urllib.request.build_opener(urllib.request.ProxyHandler({}));"
             "o.open(r,timeout=15).read()" % RELAY_PORT],
            input=json.dumps(payload), capture_output=True, text=True, timeout=60,
        )
        if out.returncode == 0:
            return True
        log.warning("relay rejected the notification: %s", out.stderr.strip()[:200])
        return False
    except (OSError, subprocess.SubprocessError) as exc:
        # The relay being unreachable is a real fault, but not this
        # component's to fix. The proposal stays un-notified and is offered
        # again on the next run.
        log.warning("cannot reach the alert relay: %s", exc)
        return False


def announce_proposals():
    for path in sorted(PROPOSALS_DIR.glob("*.json")):
        try:
            record = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if record.get("state") != "pending" or record.get("notified"):
            continue
        target = " ".join(f"{k}={v}" for k, v in (record.get("args") or {}).items())
        body = "\n".join([
            f"The assistant proposes: {record.get('verb')} {target}".rstrip(),
            "",
            "Why it says so:",
            str(record.get("reason", ""))[:500],
            "",
            "Nothing has run. To allow it, on the Pi:",
            f"  sudo {APPROVE_COMMAND} {record.get('id')}",
            "",
            "Ignore this message to decline; it expires on its own.",
        ])
        if notify(f"Frey proposal {record.get('id')}", body, severity="warning"):
            record["notified"] = True
            try:
                path.write_text(json.dumps(record, indent=1))
            except OSError:
                pass
            log.info("announced proposal %s", record.get("id"))


def worse(before, after):
    """Did health regress? Unknown counts never count as a regression.

    A missing measurement means the probe failed, not that something broke,
    and tripping the breaker on a failed probe would make every uplink outage
    look like a bad repair.
    """
    for key in ("stopped_containers", "critical_alerts"):
        a, b = before.get(key), after.get(key)
        if isinstance(a, int) and isinstance(b, int) and b > a:
            return True, f"{key} rose from {a} to {b}"
    return False, ""


def enforce_deadman():
    now = time.time()
    for path in sorted(DEADMAN_DIR.glob("*.json")):
        try:
            record = json.loads(path.read_text())
        except (OSError, ValueError):
            path.unlink(missing_ok=True)
            continue
        if now - record.get("armed_at", 0) < GRACE_SECONDS:
            continue

        after = health_snapshot()
        regressed, why = worse(record.get("before") or {}, after)
        target = " ".join(f"{k}={v}" for k, v in (record.get("args") or {}).items())
        label = f"{record.get('verb')} {target}".strip()

        if regressed:
            # Trip the breaker FIRST, then tell someone. If the notification
            # fails because there is no uplink, the agent must still be
            # stopped - the order matters.
            try:
                KILL_SWITCH.parent.mkdir(parents=True, exist_ok=True)
                KILL_SWITCH.write_text(
                    f"tripped {time.strftime('%Y-%m-%dT%H:%M:%S')} after "
                    f"{label}: {why}\n"
                )
            except OSError as exc:
                log.error("COULD NOT TRIP THE KILL SWITCH: %s", exc)
            log.error("deadman tripped after %s: %s", label, why)
            notify(
                "Frey self-repair made things worse",
                "\n".join([
                    f"Action: {label}",
                    f"Proposal: {record.get('proposal_id')}",
                    f"Regression: {why}",
                    "",
                    "The broker is now disabled and will refuse every verb.",
                    "Nothing was reverted automatically - undo by hand if needed.",
                    "",
                    "To re-enable once you are satisfied:",
                    f"  sudo rm {KILL_SWITCH}",
                ]),
                severity="critical",
            )
        else:
            log.info("deadman disarmed after %s (health did not regress)", label)
        path.unlink(missing_ok=True)


def main():
    for directory in (PROPOSALS_DIR, DEADMAN_DIR):
        try:
            directory.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass
    announce_proposals()
    enforce_deadman()


if __name__ == "__main__":
    main()
