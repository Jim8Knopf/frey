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

# ------------------------------------------------------------------------------
# ONE SSH CONNECTION, REUSED.
#
# This script asks the Pi forty-odd separate questions. Without multiplexing
# that is forty-odd SSH connections in a few seconds, and this Pi runs OpenSSH
# 10 with PerSourcePenalties enabled and persourcemaxstartups 10 - so a burst
# like that can get this address locked out of port 22 for up to ten minutes,
# with every retry extending it. ControlMaster turns the whole run into a
# single connection that is torn down at the end.
# ------------------------------------------------------------------------------
SSH_CTL="$(mktemp -u "${TMPDIR:-/tmp}/frey-mon-ssh-XXXXXX")"

ssh_pi() {
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      -o ControlMaster=auto -o ControlPath="${SSH_CTL}" -o ControlPersist=60 \
      -i "${PI_KEY}" "${PI_USER}@${PI_ADDR}" "$@" 2>/dev/null
}

cleanup_ssh() {
  [ -S "${SSH_CTL}" ] && ssh -O exit -o ControlPath="${SSH_CTL}" \
      "${PI_USER}@${PI_ADDR}" >/dev/null 2>&1
  return 0
}

# Query a container's own HTTP endpoint from inside it. Nothing publishes a
# port, so this is the only route in.
curl_in() {
  local container="$1" url="$2"
  ssh_pi "sudo docker exec ${container} wget -q -O - --timeout=10 '${url}'"
}

# ------------------------------------------------------------------------------
# PARSE ON THE PI, NOT HERE.
#
# The Prometheus targets and rules endpoints return tens of kilobytes, and
# moving that much over a MULTIPLEXED ssh connection is unreliable: measured
# repeatedly on this Pi, a 37 KB response arrived complete sometimes and
# truncated to ~3.7 KB other times. ControlPersist leaves a master process
# holding a duplicate of the pipe, so whether the shell reads everything
# before the foreground client exits is a race.
#
# It failed in the worst possible direction, too - a truncated response parses
# as "no alerting rules" and "no Watchdog rule", so a perfectly healthy stack
# reported that a dead Prometheus would go unnoticed.
#
# So the JSON never leaves the Pi. The analysis script is base64-encoded (which
# sidesteps every quoting problem), run there, and only its handful of output
# lines cross the wire.
# ------------------------------------------------------------------------------
# KNOWN FLAKE: `docker exec ... | python3` truncates at about 4 KB,
# intermittently - measured as 3918 bytes of unterminated JSON on one run in
# five, against 43 KB on the others. When it bites, this returns nothing and
# the check reports "rules api: no response", which reads as a broken
# Prometheus rather than a broken pipe. Re-run before believing it.
#
# Redirecting the body to a file on the Pi first is the obvious fix and was
# tried: it made the remote command exit 139 (SIGSEGV) every time, so the
# direct pipe stays until that is understood. Do not "fix" this blind.
remote_py() {
  local source="$1" container="$2" url="$3"
  local b64 remote="/tmp/frey-mon-check-$$.py"
  b64="$(printf '%s' "${source}" | base64 -w0)"
  ssh_pi "printf '%s' '${b64}' | base64 -d > '${remote}' \
          && sudo docker exec ${container} wget -q -O - --timeout=15 '${url}' \
             | python3 '${remote}'; rc=\$?; rm -f '${remote}'; exit \$rc"
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
# These two API responses run to tens of kilobytes, and getting them intact
# took two corrections worth recording, because both failures LOOKED like
# "monitoring is broken" rather than "this script is broken" - the most
# alarming possible false negative from a tool whose job is reassurance.
#
#   1. Do not hand the JSON to python through argv. It gets truncated.
#   2. Never let ssh's stdout be a regular FILE while multiplexing. Measured
#      on this Pi, fetching the same 36718-byte response:
#
#        capture to a variable          36718   ok
#        pipe to another command        36718   ok
#        ssh > file, no multiplexing    36718   ok
#        ssh > file, multiplexed         3918   TRUNCATED
#
#      The persisting master process inherits the redirected descriptor and
#      the foreground client exits before the rest is written. It has to be
#      two statements - capture, then write - because even
#      `printf '%s' "$(ssh ...)" > file` loses data: the file descriptor is
#      already in place when the master forks.
#
# So: capture into a variable, then write that variable out for python.
TARGETS_PY='
import json, sys
data = json.load(sys.stdin)
active = data.get("data", {}).get("activeTargets", [])
bad = 0
for t in sorted(active, key=lambda x: (x["labels"].get("job",""), x["labels"].get("service",""))):
    job = t["labels"].get("job","?")
    name = t["labels"].get("service") or t["labels"].get("instance","?")
    if t.get("health") == "up":
        print("OK|%s|%s" % (job, name))
    else:
        bad += 1
        print("BAD|%s|%s %s" % (job, name, (t.get("lastError") or "")[:60]))
print("SUMMARY|%d|%d" % (len(active), bad))
'

out="$(remote_py "${TARGETS_PY}" prometheus 'http://127.0.0.1:9090/api/v1/targets?state=any')"
if [[ -z "${out}" ]]; then
  fail "prometheus targets api" "no response"
else
  while IFS='|' read -r kind a b; do
    case "${kind}" in
      OK)  pass "${a}" "${b}" ;;
      BAD) fail "${a}" "${b}" ;;
      SUMMARY) printf '        %s targets, %s down\n' "${a}" "${b}" ;;
    esac
  done <<< "${out}"
fi

# -----------------------------------------------------------------------------
echo
echo "Alert rules"
# -----------------------------------------------------------------------------
RULES_PY='
import json, sys
data = json.load(sys.stdin)
groups = data.get("data", {}).get("groups", [])
rules = [r for g in groups for r in g.get("rules", [])]
alerting = [r for r in rules if r.get("type") == "alerting"]
broken = [r for r in alerting if r.get("health") not in ("ok", "unknown")]
watchdog = [r for r in alerting if r.get("name") == "Watchdog"]
firing = [(r["name"], a) for r in alerting for a in r.get("alerts", [])
          if a.get("state") == "firing" and a["labels"].get("severity") != "none"]
print("COUNT|%d|%d" % (len(alerting), len(groups)))
print("BROKEN|%d" % len(broken))
for r in broken:
    print("BROKENONE|%s|%s" % (r.get("name"), (r.get("lastError") or "")[:70]))
print("WATCHDOG|%d" % len(watchdog))
for n, a in firing:
    print("FIRING|%s|%s|%s" % (a["labels"].get("severity","?"), n,
                               a.get("annotations",{}).get("summary","")[:60]))
'

out="$(remote_py "${RULES_PY}" prometheus 'http://127.0.0.1:9090/api/v1/rules')"
if [[ -z "${out}" ]]; then
  fail "rules api" "no response"
else
  firing_lines=""
  while IFS='|' read -r kind a b c; do
    case "${kind}" in
      COUNT)
        if (( a > 0 )); then pass "rules loaded" "${a} alerts in ${b} groups"
        else fail "rules loaded" "no alerting rules - check promtool output"; fi ;;
      BROKEN)
        if (( a == 0 )); then pass "rule evaluation" "no errors"
        else fail "rule evaluation" "${a} rule(s) erroring"; fi ;;
      BROKENONE) printf '        ! %s: %s\n' "${a}" "${b}" ;;
      WATCHDOG)
        if (( a > 0 )); then pass "dead man's switch" "Watchdog rule present"
        else fail "dead man's switch" "no Watchdog rule - a dead Prometheus would be silent"; fi ;;
      FIRING) firing_lines+="  ${a} ${b}: ${c}"$'\n' ;;
    esac
  done <<< "${out}"
  if [[ -n "${firing_lines}" ]]; then
    echo
    echo "Firing now"
    printf '%s' "${firing_lines}"
  fi
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
  dropped="$(relay_metric frey_alert_relay_dropped_total)"
  last_wd="$(relay_metric frey_alert_relay_last_watchdog_timestamp_seconds)"

  # ------------------------------------------------------------------------
  # JUDGE DELIVERY BY RECENCY, NOT BY THE LIFETIME COUNTERS.
  #
  # These counters persist across restarts, so one bad afternoon leaves
  # `failed` sitting at a large number forever. Printing "sent 9, failed 1899"
  # and then "All checks passed" is alarming and useless in equal measure -
  # the question is whether delivery works NOW.
  #
  # So: compare the last failure against the last success. A failure more
  # recent than the last success means delivery is broken right now.
  # ------------------------------------------------------------------------
  last_ok="$(relay_metric frey_alert_relay_last_success_timestamp_seconds)"
  last_fail="$(relay_metric frey_alert_relay_last_failure_timestamp_seconds)"
  last_ok=${last_ok%.*}; last_fail=${last_fail%.*}

  if [[ -n "${last_fail}" ]] && (( ${last_fail:-0} > ${last_ok:-0} )); then
    fail "ntfy delivery" \
      "failing now - last failure $(( (now - last_fail) / 60 ))m ago, after the last success"
  elif [[ -n "${last_ok}" ]] && (( ${last_ok:-0} > 0 )); then
    pass "ntfy delivery" "working - last delivered $(( (now - last_ok) / 60 ))m ago"
  else
    warn "ntfy delivery" "nothing delivered yet (run --test to prove it)"
  fi
  printf '        lifetime: sent %s, failed %s, dropped %s\n' \
    "${sent:-0}" "${failed:-0}" "${dropped:-0}"

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
  python3 - "${REPO_ROOT}/inventory/group_vars/all/images.yml" <<'PYTHON'
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
print("  Edit monitoring_versions in inventory/group_vars/all/images.yml,")
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
