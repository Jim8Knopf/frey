#!/usr/bin/env bash
# =============================================================================
# monitoring-check.sh - assert the monitoring is actually monitoring
# =============================================================================
#
# Monitoring that has quietly stopped working is worse than none, because you
# believe you are covered. This checks the things that break silently:
#
#   1. Every container in the stack is running.
#   2. Every scrape target is up. A target that is down means whatever it
#      measures is unmonitored AND every alert depending on it has stopped
#      evaluating - which is the part people miss.
#   3. The alert rules actually loaded, and none of them is in an error state.
#   4. The host collectors are still writing. A stalled collector does not
#      zero its metrics, it FREEZES them, so the dashboards keep showing the
#      last value they saw. This is the nastiest failure mode in the stack.
#   5. The notification relay can reach ntfy - or is deliberately holding a
#      queue because the van has no uplink, which is correct behaviour.
#   6. Logs are still arriving in Loki.
#
# It also prints whatever is firing right now.
#
#   scripts/monitoring-check.sh              # check
#   scripts/monitoring-check.sh --test       # ...and send a test notification
#   scripts/monitoring-check.sh --updates    # ...and compare pinned versions
#
# Nothing here is published on a host port - and ufw blocks a Docker bridge
# from reaching the host anyway - so every query goes over SSH and through the
# containers. That is also why this cannot be run from a phone.
#
# Exits non-zero if any assertion fails, so it is usable from a cron job.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_USER="${PI_USER:-ansible}"
PI_KEY="${PI_KEY:-$HOME/.ssh/id_rsa_ansible}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/opt/frey/metrics/textfile}"

DO_TEST=0
DO_UPDATES=0
for arg in "$@"; do
  case "$arg" in
    --test) DO_TEST=1 ;;
    --updates) DO_UPDATES=1 ;;
    -h | --help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

fails=0
pass() { printf '  \033[32mok\033[0m    %-44s %s\n' "$1" "${2:-}"; }
warn() { printf '  \033[33mwarn\033[0m  %-44s %s\n' "$1" "${2:-}"; }
fail() { printf '  \033[31mFAIL\033[0m  %-44s %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

ssh_pi() {
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      -i "${PI_KEY}" "${PI_USER}@${PI_ADDR}" "$@" 2>/dev/null
}

# Query a container's own HTTP endpoint from inside it. Nothing publishes a
# port, so this is the only route in.
curl_in() {
  local container="$1" url="$2"
  ssh_pi "sudo docker exec ${container} wget -q -O - --timeout=10 '${url}'"
}

echo
echo "Frey monitoring check  (${PI_USER}@${PI_ADDR})"
echo

if ! ssh_pi true; then
  echo "  Cannot reach the Pi over SSH at ${PI_ADDR}."
  echo "  Join FreyHub, or set PI_ADDR to the uplink address."
  echo
  exit 1
fi

# -----------------------------------------------------------------------------
echo "Containers"
# -----------------------------------------------------------------------------
running="$(ssh_pi "sudo docker ps --filter label=frey.module=monitoring --format '{{.Names}}'")"
expected="prometheus alertmanager alert-relay node-exporter cadvisor blackbox loki alloy grafana"

for container in ${expected}; do
  if grep -qx "${container}" <<< "${running}"; then
    state="$(ssh_pi "sudo docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' ${container}")"
    case "${state}" in
      *unhealthy*) fail "${container}" "${state}" ;;
      *) pass "${container}" "${state}" ;;
    esac
  else
    # Components can legitimately be switched off in monitoring.yml, so a
    # missing container is a warning unless it is one of the three that make
    # alerting work at all.
    case "${container}" in
      prometheus | alertmanager | alert-relay) fail "${container}" "not running" ;;
      *) warn "${container}" "not running (disabled in monitoring.yml?)" ;;
    esac
  fi
done

# -----------------------------------------------------------------------------
echo
echo "Scrape targets"
# -----------------------------------------------------------------------------
targets="$(curl_in prometheus 'http://127.0.0.1:9090/api/v1/targets?state=any')"
if [[ -z "${targets}" ]]; then
  fail "prometheus api" "no response"
else
  # The JSON goes in as an argument, not on stdin: stdin is the script itself.
  if python3 - "${targets}" <<'PYTHON'
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception as exc:
    print("  \033[31mFAIL\033[0m  targets api%34s%s" % ("", exc))
    sys.exit(1)
active = data.get("data", {}).get("activeTargets", [])
bad = [t for t in active if t.get("health") != "up"]
for t in sorted(active, key=lambda t: t["labels"].get("job", "")):
    job = t["labels"].get("job", "?")
    inst = t["labels"].get("instance", "?")
    if t.get("health") == "up":
        print("  \033[32mok\033[0m    %-44s %s" % (job, inst))
    else:
        print("  \033[31mFAIL\033[0m  %-44s %s  %s"
              % (job, inst, (t.get("lastError") or "")[:70]))
sys.exit(1 if bad else 0)
PYTHON
  then
    :
  else
    fails=$((fails + 1))
  fi
fi

# -----------------------------------------------------------------------------
echo
echo "Alert rules"
# -----------------------------------------------------------------------------
rules="$(curl_in prometheus 'http://127.0.0.1:9090/api/v1/rules')"
if [[ -z "${rules}" ]]; then
  fail "rules api" "no response"
else
  summary="$(python3 - "${rules}" <<'PYTHON'
import json, sys
data = json.loads(sys.argv[1])
groups = data.get("data", {}).get("groups", [])
rules = [r for g in groups for r in g.get("rules", [])]
alerting = [r for r in rules if r.get("type") == "alerting"]
broken = [r for r in alerting if r.get("health") not in ("ok", "unknown")]
firing = [r for r in alerting if r.get("state") == "firing"
          and r.get("labels", {}).get("severity") != "none"]
watchdog = [r for r in alerting if r.get("name") == "Watchdog"]
print("%d|%d|%d|%d|%d" % (len(groups), len(alerting), len(broken), len(firing), len(watchdog)))
for r in broken:
    print("BROKEN %s: %s" % (r.get("name"), (r.get("lastError") or "")[:80]))
for r in firing:
    for a in r.get("alerts", []):
        print("FIRING %s %s: %s" % (a.get("labels", {}).get("severity", "?"),
                                    r.get("name"),
                                    a.get("annotations", {}).get("summary", "")[:70]))
PYTHON
)"
  counts="$(head -n1 <<<"${summary}")"
  IFS='|' read -r n_groups n_alerting n_broken n_firing n_watchdog <<<"${counts}"

  if (( n_alerting > 0 )); then
    pass "rules loaded" "${n_alerting} alerts in ${n_groups} groups"
  else
    fail "rules loaded" "no alerting rules - check promtool output"
  fi

  if (( n_broken > 0 )); then
    fail "rule evaluation" "${n_broken} rule(s) erroring"
  else
    pass "rule evaluation" "no errors"
  fi

  # The dead man's switch must exist, or the relay can never notice that the
  # monitoring chain has gone quiet.
  if (( n_watchdog > 0 )); then
    pass "dead man's switch" "Watchdog rule present"
  else
    fail "dead man's switch" "no Watchdog rule - a dead Prometheus would be silent"
  fi

  if (( n_firing > 0 )); then
    echo
    echo "Firing now"
    grep '^FIRING' <<<"${summary}" | sed 's/^FIRING /  /'
  fi
  grep '^BROKEN' <<<"${summary}" | sed 's/^BROKEN /  /' || true
fi

# -----------------------------------------------------------------------------
echo
echo "Host collectors"
# -----------------------------------------------------------------------------
# Freshness, not existence. A collector that has stopped leaves its file in
# place with stale contents, which every dashboard will then present as current.
collector_ages="$(ssh_pi "sudo find ${TEXTFILE_DIR} -name '*.prom' -printf '%f %T@\n' 2>/dev/null")"
if [[ -z "${collector_ages}" ]]; then
  fail "textfile metrics" "nothing in ${TEXTFILE_DIR}"
else
  now="$(ssh_pi 'date +%s')"
  while read -r file mtime; do
    [[ -z "${file}" ]] && continue
    age=$(( now - ${mtime%.*} ))
    if (( age > 600 )); then
      fail "${file}" "last written ${age}s ago - metrics are frozen"
    elif (( age > 180 )); then
      warn "${file}" "last written ${age}s ago"
    else
      pass "${file}" "${age}s old"
    fi
  done <<<"${collector_ages}"
fi

timer_state="$(ssh_pi 'systemctl is-active frey-metrics.timer')"
[[ "${timer_state}" == "active" ]] \
  && pass "frey-metrics.timer" "active" \
  || fail "frey-metrics.timer" "${timer_state:-unknown}"

watchdog_state="$(ssh_pi 'systemctl is-active frey-monitor-watchdog.timer')"
[[ "${watchdog_state}" == "active" ]] \
  && pass "frey-monitor-watchdog.timer" "active" \
  || warn "frey-monitor-watchdog.timer" "${watchdog_state:-unknown}"

# -----------------------------------------------------------------------------
echo
echo "Notification delivery"
# -----------------------------------------------------------------------------
relay="$(curl_in alert-relay 'http://127.0.0.1:8080/metrics')"
if [[ -z "${relay}" ]]; then
  fail "alert relay" "not answering - nothing can reach your phone"
else
  relay_metric() { awk -v k="$1" '$1 == k { print $2; exit }' <<<"${relay}"; }
  now="$(ssh_pi 'date +%s')"

  queue="$(relay_metric frey_alert_relay_queue_depth)"
  sent="$(relay_metric frey_alert_relay_sent_total)"
  failed="$(relay_metric frey_alert_relay_failed_total)"
  last_wd="$(relay_metric frey_alert_relay_last_watchdog_timestamp_seconds)"

  pass "alert relay" "sent ${sent:-0}, failed ${failed:-0}"

  if [[ -n "${last_wd}" ]] && (( ${last_wd%.*} > 0 )); then
    wd_age=$(( now - ${last_wd%.*} ))
    if (( wd_age > 600 )); then
      fail "heartbeat from Prometheus" "${wd_age}s ago - the alerting chain is broken"
    else
      pass "heartbeat from Prometheus" "${wd_age}s ago"
    fi
  else
    warn "heartbeat from Prometheus" "none yet (normal for a few minutes after deploy)"
  fi

  if [[ -n "${queue}" ]] && (( ${queue%.*} > 0 )); then
    # Not a failure. This is the queue doing its job, and the alerts will
    # arrive with a 'while you were offline' report when there is an uplink.
    warn "held alerts" "${queue%.*} waiting for an uplink (they are not lost)"
  else
    pass "held alerts" "none"
  fi
fi

# -----------------------------------------------------------------------------
if grep -qx "loki" <<< "${running}"; then
  echo
  echo "Logs"
  ingested="$(curl_in prometheus 'http://127.0.0.1:9090/api/v1/query?query=sum(rate(loki_distributor_bytes_received_total%5B30m%5D))')"
  rate_value="$(python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    r = d['data']['result']
    print(float(r[0]['value'][1]) if r else 0.0)
except Exception:
    print(-1)
" <<<"${ingested}")"
  if [[ "${rate_value}" == "-1" ]]; then
    warn "log ingestion" "could not query"
  elif python3 -c "import sys; sys.exit(0 if float('${rate_value}') > 0 else 1)"; then
    pass "log ingestion" "$(printf '%.0f' "${rate_value}") B/s into Loki"
  else
    fail "log ingestion" "nothing arriving - 21 containers do not fall silent"
  fi
fi

# -----------------------------------------------------------------------------
if (( DO_TEST )); then
  echo
  echo "Test notification"
  if ssh_pi "sudo docker exec alert-relay python3 -c \"
import urllib.request
r = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8080/test', method='POST'), timeout=20)
print(r.read().decode().strip())
\"" | grep -q sent; then
    pass "ntfy delivery" "sent - check your phone"
  else
    fail "ntfy delivery" "could not deliver (no uplink, or the topic/token is wrong)"
  fi
fi

# -----------------------------------------------------------------------------
if (( DO_UPDATES )); then
  echo
  echo "Image versions"
  python3 - "${REPO_ROOT}/inventory/group_vars/all/monitoring.yml" <<'PYTHON'
import json, re, sys, urllib.error, urllib.request

try:
    import yaml
except ImportError:
    sys.exit("  python3 yaml module is required (pip install pyyaml)")

pinned = (yaml.safe_load(open(sys.argv[1])) or {}).get("monitoring_versions", {})
if not pinned:
    sys.exit("  no monitoring_versions found")

# Where each pinned key actually lives. cAdvisor is not on Docker Hub, and its
# tags are not contiguous - v0.53.0 and v0.54.0 were never published - so
# "bump to the next number" is not safe for it.
REPOS = {
    "prometheus": ("hub", "prom/prometheus", r"v\d+\.\d+\.\d+"),
    "alertmanager": ("hub", "prom/alertmanager", r"v\d+\.\d+\.\d+"),
    "node_exporter": ("hub", "prom/node-exporter", r"v\d+\.\d+\.\d+"),
    "blackbox_exporter": ("hub", "prom/blackbox-exporter", r"v\d+\.\d+\.\d+"),
    "grafana": ("hub", "grafana/grafana", r"\d+\.\d+\.\d+"),
    "loki": ("hub", "grafana/loki", r"\d+\.\d+\.\d+"),
    "alloy": ("hub", "grafana/alloy", r"v\d+\.\d+\.\d+"),
    "cadvisor": ("gcr", "cadvisor/cadvisor", r"v\d+\.\d+\.\d+"),
    "relay_base": ("hub", "library/python", r"3\.\d+\.\d+-alpine3\.\d+"),
}


def fetch(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        return json.load(response)


def key(tag):
    return [int(n) for n in re.findall(r"\d+", tag)]


def latest(kind, repo, pattern):
    tags = []
    if kind == "hub":
        url = ("https://hub.docker.com/v2/repositories/%s/tags/"
               "?page_size=100&ordering=last_updated" % repo)
        for page in (1, 2, 3):
            data = fetch(url + "&page=%d" % page)
            tags += [t["name"] for t in data.get("results", [])]
            if not data.get("next"):
                break
    else:
        tags = fetch("https://gcr.io/v2/%s/tags/list" % repo).get("tags", [])
    matching = [t for t in tags if re.fullmatch(pattern, t)]
    return max(matching, key=key) if matching else None


for name, current in sorted(pinned.items()):
    spec = REPOS.get(name)
    if not spec:
        continue
    try:
        newest = latest(*spec)
    except (urllib.error.URLError, OSError) as exc:
        print("  \033[33mwarn\033[0m  %-24s %-22s could not check (%s)"
              % (name, current, exc))
        continue
    if not newest:
        print("  \033[33mwarn\033[0m  %-24s %-22s no matching tags" % (name, current))
    elif newest == current:
        print("  \033[32mok\033[0m    %-24s %s" % (name, current))
    else:
        print("  \033[33mnew\033[0m   %-24s %-22s -> %s" % (name, current, newest))

print()
print("  Edit monitoring_versions in inventory/group_vars/all/monitoring.yml,")
print("  then: ansible-playbook ... --tags monitoring -e monitoring_update=true")
PYTHON
fi

echo
if (( fails > 0 )); then
  echo "  ${fails} check(s) failed."
  echo
  exit 1
fi
echo "  All checks passed."
echo
