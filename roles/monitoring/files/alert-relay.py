#!/usr/bin/env python3
# =============================================================================
# frey-alert-relay - turn Alertmanager webhooks into phone notifications,
#                    and survive the van having no internet
#
# Managed by Ansible role: monitoring. Do not edit on the Pi.
# =============================================================================
#
# WHY THIS EXISTS
#
# Alertmanager can POST to a webhook, and ntfy accepts a POST, so on paper this
# file should not need to exist. It exists because of the van.
#
# When Alertmanager's notification fails - no uplink, or worse, a captive
# portal that accepts the connection and then answers nothing - the alert is
# simply gone. It retries for a while within the group interval and then moves
# on. And "parked off-grid for two days" is precisely when you most want to
# know that the NVMe started throwing errors on the first night.
#
# So this holds undelivered alerts on disk, with the time they really fired,
# and when an uplink appears it sends a short report of what was missed and
# then the alerts themselves. Alerts that broke AND fixed themselves while you
# were offline still get mentioned in the report - usually the most
# interesting kind, and completely invisible otherwise.
#
# It is also the dead man's switch. Prometheus sends a Watchdog alert every
# minute forever; this records that it arrived. If the Watchdog stops arriving,
# something in the monitoring chain is broken, and this says so - which is the
# one failure mode that otherwise goes unnoticed for weeks because everything
# looks quiet.
#
# DESIGN CONSTRAINTS, deliberately tight
#
#   Standard library only.  No pip, no requirements file, no build step. It
#                           runs the stock python image with this file
#                           bind-mounted. The component whose whole purpose is
#                           working when there is no internet must not need
#                           internet in order to start.
#   One file.               Nothing to package, nothing to version separately.
#   Crash-safe state.       Written tmp-then-rename, so a power cut mid-write
#                           cannot leave a truncated queue. In a van, power
#                           cuts are a normal event.
#
# RUN IT BY HAND
#
#   curl -s localhost:8080/healthz
#   curl -s localhost:8080/metrics
#   curl -s -XPOST localhost:8080/test          # send a real test notification
#   curl -s localhost:8080/queue                # what is being held, and why
#
# =============================================================================

import json
import logging
import os
import socket
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# -----------------------------------------------------------------------------
# Configuration, all from the environment so the compose file is the only place
# settings live.
# -----------------------------------------------------------------------------


def env(name, default=""):
    return os.environ.get(name, default).strip()


def env_int(name, default):
    try:
        return int(env(name) or default)
    except ValueError:
        return default


def env_bool(name, default=False):
    v = env(name).lower()
    if v in ("1", "true", "yes", "on"):
        return True
    if v in ("0", "false", "no", "off"):
        return False
    return default


NODE = env("FREY_NODE", "frey")
LISTEN = env("RELAY_LISTEN", "0.0.0.0:8080")

NTFY_SERVER = env("NTFY_SERVER", "https://ntfy.sh").rstrip("/")
NTFY_TOPIC = env("NTFY_TOPIC")
NTFY_TOKEN = env("NTFY_TOKEN")
NTFY_TIMEOUT = env_int("NTFY_TIMEOUT", 10)

PRIORITY = {
    "critical": env_int("PRIORITY_CRITICAL", 5),
    "warning": env_int("PRIORITY_WARNING", 2),
    "resolved": env_int("PRIORITY_RESOLVED", 2),
}
SEND_RESOLVED = {
    "critical": env_bool("SEND_RESOLVED_CRITICAL", True),
    "warning": env_bool("SEND_RESOLVED_WARNING", False),
}

QUEUE_ENABLED = env_bool("QUEUE_ENABLED", True)
RECONNECT_REPORT = env_bool("RECONNECT_REPORT", True)
MAX_FLUSH_MESSAGES = env_int("MAX_FLUSH_MESSAGES", 15)
MAX_AGE_HOURS = env_int("MAX_AGE_HOURS", 72)
RETRY_INTERVAL = env_int("RETRY_INTERVAL", 60)

WATCHDOG_ENABLED = env_bool("WATCHDOG_ENABLED", True)
WATCHDOG_STALE_SECONDS = env_int("WATCHDOG_STALE_MINUTES", 10) * 60
WATCHDOG_REPEAT_SECONDS = env_int("WATCHDOG_REPEAT_HOURS", 6) * 3600

MUTED = {a.strip() for a in env("MUTED_ALERTS").split(",") if a.strip()}
GRAFANA_URL = env("GRAFANA_URL").rstrip("/")

STATE_PATH = env("STATE_PATH", "/data/state.json")

logging.basicConfig(
    stream=sys.stdout,
    level=getattr(logging, env("RELAY_LOG_LEVEL", "info").upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("relay")

# ntfy tag shortcodes. Kept out of the title because ntfy carries the title in
# an HTTP header, and headers are not a safe place for non-ASCII.
TAGS = {
    "critical": "rotating_light",
    "warning": "warning",
    "resolved": "white_check_mark",
    "report": "satellite",
    "watchdog": "skull",
    "test": "wrench",
}


# -----------------------------------------------------------------------------
# State
#
# One JSON file holding the held-alert queue and a few timestamps. Written
# tmp-then-rename so it is never observed half-written.
#
# The queue is keyed by Alertmanager's fingerprint, which is what makes
# deduplication free: an alert that fires, resolves and fires again while the
# van is offline occupies one slot and reports the final truth, rather than
# arriving as three notifications about the same thing.
# -----------------------------------------------------------------------------

_lock = threading.Lock()

_state = {
    "queue": {},
    "last_watchdog": 0.0,
    "last_success": 0.0,
    "last_failure": 0.0,
    "last_watchdog_notice": 0.0,
    "offline_since": 0.0,
    "sent_total": 0,
    "failed_total": 0,
    "dropped_total": 0,
    "received_total": 0,
}


def load_state():
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as fh:
            saved = json.load(fh)
        if isinstance(saved, dict):
            for key, value in saved.items():
                if key in _state:
                    _state[key] = value
        log.info("state loaded: %d alert(s) held", len(_state["queue"]))
    except FileNotFoundError:
        log.info("no previous state; starting clean")
    except Exception as exc:  # a corrupt state file must not stop the relay
        log.warning("could not read state (%s); starting clean", exc)


def save_state():
    tmp = STATE_PATH + ".tmp"
    try:
        os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(_state, fh, indent=1, sort_keys=True)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, STATE_PATH)
    except Exception as exc:
        log.error("could not persist state: %s", exc)


# -----------------------------------------------------------------------------
# Sending
# -----------------------------------------------------------------------------

_ssl_context = ssl.create_default_context()


def ntfy_send(title, body, priority, tags, click=None):
    """POST one notification. Returns True on delivery, False on any failure.

    Every failure is the same failure as far as this is concerned - no uplink,
    a captive portal swallowing the request, DNS not resolving, ntfy returning
    500 - and the answer is always 'hold it and try later'. So there is no
    error taxonomy here on purpose.
    """
    if not NTFY_TOPIC:
        log.error("no ntfy topic configured; cannot notify")
        return False

    url = "%s/%s" % (NTFY_SERVER, urllib.parse.quote(NTFY_TOPIC))
    headers = {
        "Content-Type": "text/plain; charset=utf-8",
        # ntfy carries these in headers, which must be ASCII. Titles are built
        # from ASCII only; anything expressive goes in the body or the tags.
        "X-Title": ascii_only(title)[:200],
        "X-Priority": str(priority),
        "X-Tags": tags,
    }
    if click:
        headers["X-Click"] = click
    if NTFY_TOKEN:
        headers["Authorization"] = "Bearer %s" % NTFY_TOKEN

    request = urllib.request.Request(
        url, data=body.encode("utf-8"), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(
            request, timeout=NTFY_TIMEOUT, context=_ssl_context
        ) as response:
            ok = 200 <= response.status < 300
    except (urllib.error.URLError, urllib.error.HTTPError, socket.timeout, OSError) as exc:
        log.warning("ntfy send failed: %s", exc)
        ok = False
    except Exception as exc:
        log.warning("ntfy send failed: %s", exc)
        ok = False

    with _lock:
        if ok:
            _state["sent_total"] += 1
            _state["last_success"] = time.time()
            _state["offline_since"] = 0.0
        else:
            _state["failed_total"] += 1
            _state["last_failure"] = time.time()
            if not _state["offline_since"]:
                _state["offline_since"] = time.time()
    return ok


def ascii_only(text):
    """ntfy puts the title in an HTTP header; non-ASCII there is a 400."""
    return text.encode("ascii", "replace").decode("ascii")


# -----------------------------------------------------------------------------
# Formatting
# -----------------------------------------------------------------------------


def parse_time(value):
    """Alertmanager timestamps are RFC3339, sometimes with nanoseconds.

    fromisoformat does not accept 9 fractional digits, so the fraction is
    truncated to microseconds first. A timestamp that still will not parse
    becomes 'now' rather than an exception - a badly formatted date is not a
    reason to lose an alert.
    """
    if not value:
        return 0.0
    text = value.strip().replace("Z", "+00:00")
    if "." in text:
        head, _, tail = text.partition(".")
        digits = ""
        rest = ""
        for index, char in enumerate(tail):
            if char.isdigit():
                digits += char
            else:
                rest = tail[index:]
                break
        text = "%s.%s%s" % (head, digits[:6], rest)
    try:
        return datetime.fromisoformat(text).timestamp()
    except Exception:
        return time.time()


def human_duration(seconds):
    seconds = int(max(0, seconds))
    if seconds < 60:
        return "%ds" % seconds
    if seconds < 3600:
        return "%dm" % (seconds // 60)
    if seconds < 86400:
        return "%dh%02dm" % (seconds // 3600, (seconds % 3600) // 60)
    return "%dd%02dh" % (seconds // 86400, (seconds % 86400) // 3600)


def local_time(epoch):
    if not epoch:
        return "unknown"
    return datetime.fromtimestamp(epoch, tz=timezone.utc).astimezone().strftime(
        "%a %d %b %H:%M"
    )


def build_message(alert):
    """Turn one Alertmanager alert into the notification fields."""
    labels = alert.get("labels") or {}
    annotations = alert.get("annotations") or {}

    alertname = labels.get("alertname", "UnnamedAlert")
    severity = labels.get("severity", "warning")
    status = alert.get("status", "firing")
    fired_at = parse_time(alert.get("startsAt"))

    summary = annotations.get("summary") or alertname
    description = annotations.get("description") or ""

    # Where, in decreasing order of usefulness. `service` is set by the probe
    # job, `name` by cAdvisor, `mountpoint` and `device` by node-exporter.
    where = (
        labels.get("service")
        or labels.get("name")
        or labels.get("mountpoint")
        or labels.get("device")
        or labels.get("instance")
        or NODE
    )

    if status == "resolved":
        title = "RESOLVED: %s" % summary
        priority = PRIORITY["resolved"]
        tags = TAGS["resolved"]
    else:
        prefix = "CRITICAL" if severity == "critical" else "Warning"
        title = "%s: %s" % (prefix, summary)
        priority = PRIORITY.get(severity, PRIORITY["warning"])
        tags = TAGS.get(severity, TAGS["warning"])

    lines = []
    if description:
        lines.append(description)
    lines.append("")
    lines.append("where:  %s" % where)
    lines.append("alert:  %s (%s)" % (alertname, severity))
    lines.append("since:  %s" % local_time(fired_at))

    return {
        "fingerprint": alert.get("fingerprint") or "%s/%s" % (alertname, where),
        "alertname": alertname,
        "severity": severity,
        "status": status,
        "title": title,
        "body": "\n".join(lines),
        "priority": priority,
        "tags": tags,
        "click": GRAFANA_URL or None,
        "fired_at": fired_at,
        "where": where,
        "summary": summary,
    }


# -----------------------------------------------------------------------------
# Handling an incoming alert
# -----------------------------------------------------------------------------


def handle_alerts(payload):
    alerts = payload.get("alerts") or []
    with _lock:
        _state["received_total"] += len(alerts)

    for alert in alerts:
        labels = alert.get("labels") or {}
        alertname = labels.get("alertname", "")

        # The dead man's switch. Recorded, never notified.
        if alertname == "Watchdog":
            with _lock:
                _state["last_watchdog"] = time.time()
            continue

        if alertname in MUTED:
            log.info("muted: %s", alertname)
            continue

        message = build_message(alert)

        # A recovery notice is only worth sending for something that was loud
        # enough to interrupt you in the first place.
        if message["status"] == "resolved" and not SEND_RESOLVED.get(
            message["severity"], False
        ):
            # Still worth recording if it is sitting in the queue: it changes
            # the alert from "was broken when we went offline" to "broke and
            # fixed itself", which is what the reconnect report is for.
            with _lock:
                held = _state["queue"].get(message["fingerprint"])
                if held:
                    held["status"] = "resolved"
                    held["resolved_at"] = time.time()
                    save_state()
            continue

        deliver_or_hold(message)

    save_state()


def deliver_or_hold(message):
    """Send now if possible; otherwise hold it with the time it really fired."""
    with _lock:
        backlog = len(_state["queue"])

    # While a backlog exists, do not jump the queue: a new alert sent ahead of
    # held ones would arrive out of order and before the report explaining the
    # gap. The flusher will pick it up on its next pass, within a minute.
    if backlog == 0 and ntfy_send(
        message["title"],
        message["body"],
        message["priority"],
        message["tags"],
        message["click"],
    ):
        log.info("sent: %s (%s)", message["alertname"], message["status"])
        return

    if not QUEUE_ENABLED:
        log.warning("dropped (queue disabled): %s", message["alertname"])
        with _lock:
            _state["dropped_total"] += 1
        return

    with _lock:
        existing = _state["queue"].get(message["fingerprint"])
        if existing:
            # Same problem seen again. Keep when it was first held so the
            # report can say how long it has really been going on, and note
            # that it had been firing if it has now resolved.
            message["first_held_at"] = existing.get("first_held_at", time.time())
            message["was_firing"] = existing.get("was_firing", False) or (
                existing.get("status") == "firing"
            )
            message["seen"] = existing.get("seen", 1) + 1
        else:
            message["first_held_at"] = time.time()
            message["was_firing"] = message["status"] == "firing"
            message["seen"] = 1
        _state["queue"][message["fingerprint"]] = message
        held = len(_state["queue"])
    log.info("held: %s (%d waiting)", message["alertname"], held)


# -----------------------------------------------------------------------------
# Flushing when the uplink comes back
# -----------------------------------------------------------------------------


def flush_queue():
    """Try to deliver the backlog. One send decides whether we are online.

    There is no connectivity check here on purpose. `nmcli` says 'full' behind
    some captive portals, and a TCP connect succeeds to anything that answers
    the port. The only honest test of whether a notification can be delivered
    is to deliver one.
    """
    with _lock:
        if not _state["queue"]:
            return
        entries = list(_state["queue"].values())
        offline_since = _state["offline_since"]

    now = time.time()

    # Anything older than the cap is history rather than news, and delivering
    # it would push the things that still matter past the flood limit.
    fresh, stale = [], []
    for entry in entries:
        age = now - entry.get("first_held_at", now)
        (stale if age > MAX_AGE_HOURS * 3600 else fresh).append(entry)

    firing = [e for e in fresh if e.get("status") == "firing"]
    self_resolved = [
        e for e in fresh if e.get("status") == "resolved" and e.get("was_firing")
    ]

    # Loudest and oldest first: a critical that is still broken is what you
    # need to read before anything else.
    firing.sort(key=lambda e: (e.get("severity") != "critical", e.get("fired_at", 0)))

    if RECONNECT_REPORT:
        report = build_reconnect_report(
            offline_since, now, firing, self_resolved, stale
        )
        # The report is also the probe: if it will not send, we are still
        # offline and nothing is lost by stopping here.
        if not ntfy_send(
            report["title"], report["body"], report["priority"], TAGS["report"]
        ):
            log.info("still offline; %d alert(s) held", len(entries))
            return
    else:
        probe = firing[0] if firing else fresh[0]
        if not ntfy_send(
            probe["title"], probe["body"], probe["priority"], probe["tags"], probe["click"]
        ):
            log.info("still offline; %d alert(s) held", len(entries))
            return
        firing = [e for e in firing if e is not probe]

    delivered = []
    for entry in firing[:MAX_FLUSH_MESSAGES]:
        body = entry["body"] + "\n\nheld for %s while offline" % human_duration(
            now - entry.get("first_held_at", now)
        )
        if not ntfy_send(
            entry["title"], body, entry["priority"], entry["tags"], entry["click"]
        ):
            # Went offline again mid-flush. Keep whatever is left.
            break
        delivered.append(entry["fingerprint"])
        # ntfy.sh allows a burst but not an unlimited one, and this is not
        # urgent enough to argue with a rate limiter.
        time.sleep(0.5)

    with _lock:
        # Everything summarised in the report is accounted for, so it leaves
        # the queue even if it got no individual message of its own.
        for entry in self_resolved + stale:
            _state["queue"].pop(entry["fingerprint"], None)
        for fingerprint in delivered:
            _state["queue"].pop(fingerprint, None)
        if stale:
            _state["dropped_total"] += len(stale)
        remaining = len(_state["queue"])
        save_state()

    log.info(
        "flushed %d, summarised %d, dropped %d, %d still held",
        len(delivered),
        len(self_resolved),
        len(stale),
        remaining,
    )


def build_reconnect_report(offline_since, now, firing, self_resolved, stale):
    """The 'while you were offline' message.

    The self-resolved list is the reason this exists. A service that crash
    looped for six hours overnight and came back on its own leaves no trace
    anywhere else - Alertmanager has forgotten it, the dashboard shows green,
    and you would never know. Those are exactly the faults worth chasing
    before they become permanent.
    """
    duration = human_duration(now - offline_since) if offline_since else "a while"
    criticals = sum(1 for e in firing if e.get("severity") == "critical")

    lines = ["Offline for %s. Alerts held while the van had no uplink:" % duration, ""]

    if firing:
        lines.append(
            "STILL FIRING (%d, %d critical):" % (len(firing), criticals)
        )
        for entry in firing[:10]:
            lines.append(
                "  - %s: %s (since %s)"
                % (
                    entry.get("severity", "?"),
                    entry.get("summary", entry.get("alertname")),
                    local_time(entry.get("fired_at")),
                )
            )
        if len(firing) > 10:
            lines.append("  ... and %d more" % (len(firing) - 10))
        lines.append("")

    if self_resolved:
        lines.append("BROKE AND RECOVERED ON ITS OWN (%d):" % len(self_resolved))
        for entry in self_resolved[:10]:
            fired = entry.get("fired_at", 0)
            ended = entry.get("resolved_at", 0)
            window = human_duration(ended - fired) if ended and fired else "?"
            lines.append(
                "  - %s (%s, lasted %s)"
                % (
                    entry.get("summary", entry.get("alertname")),
                    local_time(fired),
                    window,
                )
            )
        if len(self_resolved) > 10:
            lines.append("  ... and %d more" % (len(self_resolved) - 10))
        lines.append("")
        lines.append("Nothing else records these. Worth a look in Grafana.")
        lines.append("")

    if stale:
        lines.append(
            "%d alert(s) older than %dh were discarded unread."
            % (len(stale), MAX_AGE_HOURS)
        )

    if not firing and not self_resolved and not stale:
        lines.append("Nothing still outstanding.")

    title = "Back online: %d held, %d critical" % (
        len(firing) + len(self_resolved),
        criticals,
    )
    return {
        "title": title,
        "body": "\n".join(lines).rstrip(),
        "priority": PRIORITY["critical"] if criticals else PRIORITY["warning"],
    }


# -----------------------------------------------------------------------------
# The dead man's switch
# -----------------------------------------------------------------------------


def check_watchdog():
    """Notice that Prometheus has stopped talking to us.

    Deliberately only armed once a Watchdog has been seen at least once, so a
    cold start - or a deploy that brings the relay up before Prometheus - does
    not announce a fault that does not exist.
    """
    if not WATCHDOG_ENABLED:
        return
    with _lock:
        last = _state["last_watchdog"]
        noticed = _state["last_watchdog_notice"]
    if not last:
        return
    age = time.time() - last
    if age < WATCHDOG_STALE_SECONDS:
        return
    if time.time() - noticed < WATCHDOG_REPEAT_SECONDS:
        return

    body = "\n".join(
        [
            "No Watchdog alert for %s." % human_duration(age),
            "",
            "Prometheus sends one every minute. Silence means the chain that",
            "would tell you about a real problem is broken, so treat anything",
            "quiet since then as unverified.",
            "",
            "On the Pi:",
            "  docker ps --filter label=frey.module=monitoring",
            "  docker logs --tail 50 prometheus",
            "  docker logs --tail 50 alertmanager",
        ]
    )
    if ntfy_send("CRITICAL: monitoring has gone quiet", body, PRIORITY["critical"], TAGS["watchdog"]):
        with _lock:
            _state["last_watchdog_notice"] = time.time()
            save_state()


# -----------------------------------------------------------------------------
# Background loop
# -----------------------------------------------------------------------------


def background():
    while True:
        try:
            if QUEUE_ENABLED:
                flush_queue()
            check_watchdog()
            save_state()
        except Exception as exc:
            log.error("background loop error: %s", exc)
        time.sleep(RETRY_INTERVAL)


# -----------------------------------------------------------------------------
# HTTP
# -----------------------------------------------------------------------------


def render_metrics():
    with _lock:
        queue = _state["queue"]
        oldest = min(
            (e.get("first_held_at", 0) for e in queue.values()), default=0
        )
        snapshot = dict(_state)

    held_critical = sum(
        1 for e in queue.values() if e.get("severity") == "critical"
    )
    lines = [
        "# HELP frey_alert_relay_up The relay is running.",
        "# TYPE frey_alert_relay_up gauge",
        "frey_alert_relay_up 1",
        "# HELP frey_alert_relay_queue_depth Alerts held for want of an uplink.",
        "# TYPE frey_alert_relay_queue_depth gauge",
        "frey_alert_relay_queue_depth %d" % len(queue),
        "# HELP frey_alert_relay_queue_critical Held alerts at critical severity.",
        "# TYPE frey_alert_relay_queue_critical gauge",
        "frey_alert_relay_queue_critical %d" % held_critical,
        "# HELP frey_alert_relay_queue_oldest_timestamp_seconds When the oldest held alert was first held.",
        "# TYPE frey_alert_relay_queue_oldest_timestamp_seconds gauge",
        "frey_alert_relay_queue_oldest_timestamp_seconds %.0f" % oldest,
        "# HELP frey_alert_relay_sent_total Notifications delivered.",
        "# TYPE frey_alert_relay_sent_total counter",
        "frey_alert_relay_sent_total %d" % snapshot["sent_total"],
        "# HELP frey_alert_relay_failed_total Notification attempts that failed.",
        "# TYPE frey_alert_relay_failed_total counter",
        "frey_alert_relay_failed_total %d" % snapshot["failed_total"],
        "# HELP frey_alert_relay_dropped_total Alerts discarded unread for age.",
        "# TYPE frey_alert_relay_dropped_total counter",
        "frey_alert_relay_dropped_total %d" % snapshot["dropped_total"],
        "# HELP frey_alert_relay_received_total Alerts received from Alertmanager.",
        "# TYPE frey_alert_relay_received_total counter",
        "frey_alert_relay_received_total %d" % snapshot["received_total"],
        "# HELP frey_alert_relay_last_success_timestamp_seconds Last successful delivery.",
        "# TYPE frey_alert_relay_last_success_timestamp_seconds gauge",
        "frey_alert_relay_last_success_timestamp_seconds %.0f" % snapshot["last_success"],
        # Exported alongside the success timestamp so that "is delivery broken
        # RIGHT NOW" is answerable. The lifetime counters cannot answer it:
        # they persist across restarts, so one bad afternoon leaves
        # failed_total permanently large and indistinguishable from an ongoing
        # outage. A last_failure NEWER than last_success is the signal.
        "# HELP frey_alert_relay_last_failure_timestamp_seconds Last failed delivery attempt.",
        "# TYPE frey_alert_relay_last_failure_timestamp_seconds gauge",
        "frey_alert_relay_last_failure_timestamp_seconds %.0f" % snapshot["last_failure"],
        "# HELP frey_alert_relay_last_watchdog_timestamp_seconds Last Watchdog alert received.",
        "# TYPE frey_alert_relay_last_watchdog_timestamp_seconds gauge",
        "frey_alert_relay_last_watchdog_timestamp_seconds %.0f" % snapshot["last_watchdog"],
        "",
    ]
    return "\n".join(lines)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "frey-alert-relay"

    def _respond(self, code, body, content_type="text/plain; charset=utf-8"):
        payload = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/healthz":
            self._respond(200, "ok\n")
        elif path == "/metrics":
            self._respond(200, render_metrics())
        elif path == "/queue":
            with _lock:
                body = json.dumps(_state["queue"], indent=1, sort_keys=True)
            self._respond(200, body + "\n", "application/json")
        else:
            self._respond(404, "not found\n")

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"

        if path == "/test":
            body = "\n".join(
                [
                    "This is a test notification from Frey on %s." % NODE,
                    "",
                    "If you can read it, the whole chain works: the relay can",
                    "reach ntfy, the topic is right, and your phone is",
                    "subscribed to it.",
                    "",
                    "node:  %s" % NODE,
                    "time:  %s" % local_time(time.time()),
                ]
            )
            ok = ntfy_send("Frey test notification", body, 3, TAGS["test"])
            save_state()
            self._respond(200 if ok else 502, "sent\n" if ok else "send failed\n")
            return

        if path != "/alert":
            self._respond(404, "not found\n")
            return

        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except Exception as exc:
            log.warning("unparseable webhook: %s", exc)
            self._respond(400, "bad json\n")
            return

        # Answer Alertmanager immediately and do the work after. A send that
        # waits out a 10-second timeout to a dead uplink would otherwise make
        # Alertmanager consider the webhook itself broken and retry it.
        self._respond(200, "accepted\n")
        try:
            handle_alerts(payload)
        except Exception as exc:
            log.error("error handling alerts: %s", exc)

    def log_message(self, fmt, *args):
        log.debug("http %s", fmt % args)


def main():
    if not NTFY_TOPIC:
        log.error(
            "NTFY_TOPIC is empty - nothing can be delivered. "
            "Check vault_ntfy_topic or the generated key file."
        )

    load_state()

    host, _, port = LISTEN.rpartition(":")
    server = ThreadingHTTPServer((host or "0.0.0.0", int(port)), Handler)
    server.daemon_threads = True

    threading.Thread(target=background, daemon=True, name="flusher").start()

    log.info(
        "frey-alert-relay listening on %s, ntfy %s, queue %s",
        LISTEN,
        NTFY_SERVER,
        "on" if QUEUE_ENABLED else "off",
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        save_state()


if __name__ == "__main__":
    main()
