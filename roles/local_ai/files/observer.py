#!/usr/bin/env python3
"""Read-only system observer for Frey.

Phase 1 of docs/LOCAL_AI_AGENT_PLAN.md. This process reads; it cannot act.
There is no broker, no Docker socket, no shell and no action verb anywhere in
this file - deliberately, because the limits are meant to be a property of the
system rather than a rule a model is asked to honour.

What it does: polls Alertmanager for firing alerts, gathers supporting evidence
from Prometheus, Loki and the node-exporter textfile collectors, asks the local
model to explain it, and writes a Markdown incident report into its own drafts
directory. A report about a critical alert is handed to the existing alert
relay for notification, because this container has no egress of its own.

Everything it reads is read-only. The single thing it writes is a file under
DRAFTS_DIR, which is the only read-write mount it has.

Resilience matters more than completeness here: a monitoring component that
dies silently is worse than one that reports partial evidence, so every
external call is guarded and the main loop never exits on a handled error.
"""

import datetime
import json
import logging
import os
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

LOG_LEVEL = os.environ.get("OBSERVER_LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("observer")

NODE = os.environ.get("FREY_NODE", "frey")
PROM_URL = os.environ.get("PROM_URL", "http://prometheus:9090")
LOKI_URL = os.environ.get("LOKI_URL", "http://loki:3100")
ALERTMANAGER_URL = os.environ.get("ALERTMANAGER_URL", "http://alertmanager:9093")
MODEL_URL = os.environ.get("MODEL_URL", "http://model:8080")
RELAY_URL = os.environ.get("RELAY_URL", "http://alert-relay:8080")

DRAFTS_DIR = pathlib.Path(os.environ.get("DRAFTS_DIR", "/drafts"))
TEXTFILE_DIR = pathlib.Path(os.environ.get("TEXTFILE_DIR", "/textfile"))
NOTES_DIR = pathlib.Path(os.environ.get("NOTES_DIR", "/notes"))

POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "300"))
DAILY_HOUR = int(os.environ.get("DAILY_HOUR", "7"))
MODEL_TIMEOUT = int(os.environ.get("MODEL_TIMEOUT", "900"))
NOTIFY_SEVERITY = os.environ.get("NOTIFY_SEVERITY", "critical")

# A character budget on the evidence, because prompt processing is the real
# cost here and it is far slower than first assumed.
#
# Measured 2026-11-07 on this Pi: prompt processing runs at 9.25 tokens/s, not
# the ~20 estimated. An untrimmed evidence block came to roughly 5600 tokens,
# which is about TEN MINUTES of prompt processing before a single output token
# - and a report that arrives a quarter of an hour after the alert is close to
# useless. Roughly four characters per token, so this keeps the prompt near
# 1500 tokens and a whole report inside about four minutes.
EVIDENCE_BUDGET_CHARS = int(os.environ.get("EVIDENCE_BUDGET_CHARS", "6000"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "400"))

STATE_PATH = DRAFTS_DIR / ".observer-state.json"

# Fixed expressions, not model-generated ones. The model never composes a
# query: it is handed evidence and asked to explain it. That keeps this a
# classification problem, which a 4B can do, rather than an invention problem,
# which it cannot.
#
# Metric names below were checked against the live Prometheus label API before
# being written here. That matters more than it sounds: a query naming a
# metric that does not exist returns an empty result and raises no error
# anywhere, so a typo becomes a permanent blind spot that looks like good
# news. `frey_nvme_unsafe_shutdowns` and `frey_throttled` were both wrong -
# the real names carry suffixes - and nothing would ever have reported it.
# audit_queries() re-checks them at startup for the same reason.
PROM_QUERIES = {
    "targets_down": 'up == 0',
    # changes(), not increase(): start time is a gauge that steps when a
    # container is recreated, and increase() is for counters.
    "containers_restarting": 'changes(container_start_time_seconds[1h]) > 0',
    "root_fs_avail_bytes": 'node_filesystem_avail_bytes{mountpoint="/"}',
    "load1": 'node_load1',
    "cpu_temp_celsius": 'node_hwmon_temp_celsius',
    "unsafe_shutdowns": 'frey_nvme_unsafe_shutdowns_total',
    "throttled_now": 'frey_throttled_now',
    "throttled_ever": 'frey_throttled_occurred',
}

# Metric names referenced above, for the startup audit.
AUDITED_METRICS = (
    "up",
    "container_start_time_seconds",
    "node_filesystem_avail_bytes",
    "node_load1",
    "node_hwmon_temp_celsius",
    "frey_nvme_unsafe_shutdowns_total",
    "frey_throttled_now",
    "frey_throttled_occurred",
)


def _get_json(url, timeout=15):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=timeout) as response:
        return json.load(response)


def _post_json(url, payload, timeout=30):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"}
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def load_state():
    try:
        return json.loads(STATE_PATH.read_text())
    except (OSError, ValueError):
        return {"seen": [], "last_daily": ""}


def save_state(state):
    try:
        STATE_PATH.write_text(json.dumps(state, indent=1))
    except OSError as exc:
        log.error("cannot write state: %s", exc)


def firing_alerts():
    """Firing alerts from Alertmanager.

    Polled rather than received as a webhook on purpose: adding a receiver to
    Alertmanager's routing would put this component in the path of the
    notifications Frey already depends on. Polling cannot break them.
    """
    url = f"{ALERTMANAGER_URL}/api/v2/alerts?active=true&silenced=false&inhibited=false"
    try:
        alerts = _get_json(url)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        log.warning("cannot read alertmanager: %s", exc)
        return []
    out = []
    for alert in alerts or []:
        labels = alert.get("labels") or {}
        out.append(
            {
                "alertname": labels.get("alertname", "UnnamedAlert"),
                "severity": labels.get("severity", "warning"),
                "instance": labels.get("instance") or labels.get("name") or "",
                "summary": (alert.get("annotations") or {}).get("summary", ""),
                "startsAt": alert.get("startsAt", ""),
            }
        )
    return out


def prometheus_evidence():
    evidence = {}
    for name, query in PROM_QUERIES.items():
        url = f"{PROM_URL}/api/v1/query?query={urllib.parse.quote(query)}"
        try:
            data = _get_json(url)
            results = (data.get("data") or {}).get("result") or []
        except (urllib.error.URLError, OSError, ValueError) as exc:
            log.warning("prometheus query %s failed: %s", name, exc)
            continue
        rows = []
        for item in results[:12]:
            metric = item.get("metric") or {}
            label = (
                metric.get("container_label_com_docker_compose_service")
                or metric.get("name")
                or metric.get("job")
                or metric.get("instance")
                or metric.get("sensor")
                or ""
            )
            value = (item.get("value") or ["", ""])[1]
            rows.append(f"{label}={value}")
        if rows:
            evidence[name] = rows
    return evidence


def loki_errors(minutes=60, limit=40):
    """Recent error-ish lines. Loki holds what the journal loses.

    When the NVMe leaves the PCIe bus the journal dies with the disk, so this
    is the only place that evidence survives - which is exactly when a report
    is most wanted.
    """
    end = time.time_ns()
    start = end - minutes * 60 * 1_000_000_000
    query = '{job=~".+"} |~ "(?i)(error|fatal|panic|refused|timeout|failed)"'
    url = (
        f"{LOKI_URL}/loki/api/v1/query_range?query={urllib.parse.quote(query)}"
        f"&start={start}&end={end}&limit={limit}&direction=backward"
    )
    try:
        data = _get_json(url, timeout=25)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        log.warning("cannot read loki: %s", exc)
        return []
    lines = []
    for stream in ((data.get("data") or {}).get("result") or []):
        name = (stream.get("stream") or {}).get("job", "?")
        for _ts, text in (stream.get("values") or [])[:10]:
            lines.append(f"[{name}] {text.strip()[:300]}")
    return lines[:limit]


def textfile_evidence():
    """The Pi-specific facts no exporter reports.

    Throttling, under-voltage, PMIC rails, NVMe SMART, AP clients, DHCP leases
    - all arrive as .prom files written by a host timer. Read directly because
    this is the seam the repo documents for exactly this kind of consumer.
    """
    out = []
    try:
        paths = sorted(TEXTFILE_DIR.glob("*.prom"))
    except OSError as exc:
        log.warning("cannot list textfile dir: %s", exc)
        return out
    for path in paths:
        try:
            for line in path.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    out.append(f"{path.name}: {line}")
        except OSError:
            continue
    return out[:120]


SYSTEM_PROMPT = """You are a monitoring assistant for a Raspberry Pi named \
Frey that runs a private network inside a van. You are given evidence \
gathered from Prometheus, Loki and host collectors. Explain what is most \
likely wrong and what a human should check.

Rules you must follow:
- Use ONLY the evidence given. Never invent a metric, log line or number.
- If the evidence does not support a conclusion, say so plainly.
- Separate what the evidence shows from what you are guessing.
- Prefer naming the single most likely cause, then one alternative.
- Do not propose commands that change networking, SSH, the firewall or \
run a deploy. Those cannot be done and suggesting them is harmful.
- Be concise. Output GitHub-flavoured Markdown. No preamble.

Hard-won facts about THIS machine. They override your priors, and the first \
two are mistakes a previous report actually made:

- `status="none"` on a container means NO HEALTHCHECK IS DEFINED. It is not \
an unknown state, not a fault, and not evidence of instability. Most \
containers here have no healthcheck. Never build a diagnosis on it.
- The NVMe dropouts on this machine are a PCIe TRANSPORT fault. Power was \
investigated and ruled out, and so was APST - both were wrong answers. Do \
NOT attribute unsafe shutdowns or NVMe resets to the power supply or to a \
sagging rail. The kernel's "faulty power saving mode" line is boilerplate on \
every reset, not a diagnosis.
- The unsafe-shutdown count is a CUMULATIVE lifetime total from the drive's \
own SMART data. A non-zero value is history, not a live event, and it does \
not mean anything happened today.
- A sagging 5V rail below 4.95V is a warning, not an emergency; the critical \
threshold is 4.80V. Report the number, do not escalate it.
- All containers failing DNS at once is usually the media resolver pointing \
at a departed venue's DNS, not an application fault.
- A Pi that answers ping but refuses SSH may have lost its NVMe rather than \
be locked out. An empty journal after a freeze is evidence, not a gap.
- High load alone is expected while the local model is generating; it uses \
two cores by design."""


def ask_model(title, evidence_text):
    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"{title}\n\n{evidence_text}"},
        ],
        "max_tokens": MAX_TOKENS,
        "stream": False,
    }
    try:
        raw = _post_json(
            f"{MODEL_URL}/v1/chat/completions", payload, timeout=MODEL_TIMEOUT
        )
        data = json.loads(raw)
        return (data["choices"][0]["message"]["content"] or "").strip()
    except (urllib.error.URLError, OSError, ValueError, KeyError, IndexError) as exc:
        log.error("model call failed: %s", exc)
        return None


def runbook():
    """Operator guidance from the notes space, if any.

    This is the one use of the read-only notes mount that earns its place in a
    health reporter: a page you maintain, in your own words, describing what to
    check first. It is handed to the model as instructions from you, which is
    far more valuable than anything the model knows about Frey - and it means
    the triage advice improves when you write, not when the model changes.

    Absent file is normal and silent: the observer works without it.
    """
    name = os.environ.get("RUNBOOK_PAGE", "")
    if not name:
        return ""
    path = NOTES_DIR / name
    try:
        # Keep it inside the mount even if the configured name contains "..".
        resolved = path.resolve()
        if not str(resolved).startswith(str(NOTES_DIR.resolve())):
            log.warning("runbook page escapes the notes mount; ignoring")
            return ""
        return resolved.read_text()[:4000]
    except OSError:
        return ""


def build_evidence(alerts):
    parts = []
    guidance = runbook()
    if guidance:
        parts.append("## Operator runbook (written by the administrator)")
        parts.append(guidance)
        parts.append("")
    if alerts:
        parts.append("## Firing alerts")
        for alert in alerts:
            parts.append(
                f"- {alert['alertname']} ({alert['severity']}) "
                f"{alert['instance']} {alert['summary']}".rstrip()
            )
    metrics = prometheus_evidence()
    if metrics:
        parts.append("\n## Metrics")
        for name, rows in metrics.items():
            parts.append(f"- {name}: {', '.join(rows)}")
    host = textfile_evidence()
    if host:
        parts.append("\n## Host collectors")
        parts.extend(f"- {line}" for line in host)
    logs = loki_errors()
    if logs:
        parts.append("\n## Recent log lines")
        parts.extend(f"- {line}" for line in logs)

    return "\n".join(parts)


def trim_for_model(text):
    """Cut the evidence down to what the model can read in reasonable time.

    Only the model's copy is trimmed. The report records the full set, so
    nothing is lost - which is what makes the note below honest rather than a
    silent truncation that makes a report look more complete than it is.

    Trimmed from the end because that costs least: alerts and metrics come
    first and are what the assessment turns on, while log lines are the long
    tail.
    """
    if len(text) <= EVIDENCE_BUDGET_CHARS:
        return text
    kept = text[:EVIDENCE_BUDGET_CHARS].rsplit("\n", 1)[0]
    dropped = len(text) - len(kept)
    log.info("evidence trimmed by %d characters for the model", dropped)
    return (
        kept
        + f"\n\n[evidence trimmed: {dropped} characters dropped so prompt "
        "processing stays within a few minutes. The full set is recorded in "
        "the report under this assessment.]"
    )


def write_report(kind, title, evidence_text, answer):
    stamp = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    path = DRAFTS_DIR / f"{stamp}-{kind}.md"
    body = [
        f"# {title}",
        "",
        f"Generated {datetime.datetime.now().isoformat(timespec='seconds')} on {NODE}.",
        "",
        "This is a draft written by a local 4B model from the evidence below.",
        "Treat it as a starting point and verify every claim before acting.",
        "",
        "## Assessment",
        "",
        answer or "_The model did not answer; the evidence is still recorded below._",
        "",
        "## Evidence given to the model",
        "",
        "```text",
        evidence_text or "(none collected)",
        "```",
        "",
    ]
    try:
        path.write_text("\n".join(body))
        log.info("wrote %s", path)
        return path
    except OSError as exc:
        log.error("cannot write report: %s", exc)
        return None


def notify(title, path, severity):
    """Notify through the existing alert relay.

    This container has no egress, which is what makes its broad read access
    safe. The relay already owns ntfy delivery and holds undelivered messages
    on disk until an uplink appears, so handing it a synthesised alert reuses
    all of that rather than punching a hole in the network boundary.
    """
    payload = {
        "alerts": [
            {
                "status": "firing",
                "labels": {
                    "alertname": "FreyObserverReport",
                    "severity": severity,
                    "service": "local-ai-observer",
                },
                "annotations": {
                    "summary": title,
                    "description": f"Incident report written to {path.name}"
                    if path
                    else "Report generation failed",
                },
            }
        ]
    }
    try:
        _post_json(f"{RELAY_URL}/alert", payload)
        log.info("notified relay")
    except (urllib.error.URLError, OSError) as exc:
        log.warning("cannot reach relay: %s", exc)


def run_once(state):
    now = datetime.datetime.now()
    alerts = firing_alerts()

    # Only unseen alerts trigger a report, so a long-running alert does not
    # regenerate one on every poll.
    key = sorted({f"{a['alertname']}/{a['instance']}" for a in alerts})
    unseen = [k for k in key if k not in state.get("seen", [])]

    if unseen:
        log.info("new firing alerts: %s", ", ".join(unseen))
        evidence = build_evidence(alerts)
        names = ", ".join(sorted({a["alertname"] for a in alerts}))
        title = f"Incident report: {names}"
        answer = ask_model(title, trim_for_model(evidence))
        path = write_report("incident", title, evidence, answer)
        if any(a["severity"] == NOTIFY_SEVERITY for a in alerts):
            notify(title, path, NOTIFY_SEVERITY)
        state["seen"] = key
        save_state(state)
    elif key != state.get("seen", []):
        # Alerts resolved; remember the new set without generating a report.
        state["seen"] = key
        save_state(state)

    today = now.strftime("%Y-%m-%d")
    if now.hour >= DAILY_HOUR and state.get("last_daily") != today:
        log.info("writing daily summary")
        evidence = build_evidence(alerts)
        title = f"Daily health summary for {today}"
        answer = ask_model(title, trim_for_model(evidence))
        write_report("daily", title, evidence, answer)
        state["last_daily"] = today
        save_state(state)


def audit_queries():
    """Warn about metric names Prometheus does not know.

    An absent metric returns an empty result and raises no error, so a rename
    upstream turns a check into a permanent blind spot that reads as good news.
    This cannot distinguish "empty because healthy" from "empty because gone",
    which is exactly why the names are audited directly instead.
    """
    try:
        data = _get_json(f"{PROM_URL}/api/v1/label/__name__/values", timeout=20)
        known = set(data.get("data") or [])
    except (urllib.error.URLError, OSError, ValueError) as exc:
        log.warning("cannot audit metric names: %s", exc)
        return
    if not known:
        return
    missing = [m for m in AUDITED_METRICS if m not in known]
    if missing:
        log.warning("metrics absent from Prometheus, checks are blind: %s", missing)
    else:
        log.info("all %d audited metric names exist", len(AUDITED_METRICS))


def main():
    log.info(
        "observer starting: poll=%ss daily_hour=%s drafts=%s",
        POLL_SECONDS,
        DAILY_HOUR,
        DRAFTS_DIR,
    )
    audit_queries()
    state = load_state()
    while True:
        try:
            run_once(state)
        except Exception as exc:  # never let the loop die
            log.error("unhandled error in cycle: %s", exc)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
