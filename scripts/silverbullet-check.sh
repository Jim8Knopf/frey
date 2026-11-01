#!/usr/bin/env bash
# Check the public routing boundaries; authenticated editing and offline sync
# require a separate browser test. Run from the repository root.
set -uo pipefail

PI_ADDR="${PI_ADDR:-10.20.0.1}"
CA="${CA:-ca/frey-root-ca.crt}"
HOST="${HOSTNAME_SILVERBULLET:-silverbullet.hub.frey}"
SPACE_PREFIX="${SILVERBULLET_SPACE_PREFIX:-/notes}"
failures=0
pending=0

if [[ ! -r "$CA" ]]; then
  echo "Cannot read Frey CA: $CA" >&2
  exit 1
fi

check() {
  local path="$1" expected="$2" status
  status=$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' \
    --max-time 10 --cacert "$CA" --resolve "$HOST:443:$PI_ADDR" \
    "https://$HOST$path") || status=000
  if [[ "$status" == "$expected" ]]; then
    printf 'OK   %s: %s\n' "$path" "$status"
  else
    printf 'FAIL %s: expected %s, got %s\n' "$path" "$expected" "$status" >&2
    failures=$((failures + 1))
  fi
}

check / 302
check /.fs 302
check /.dashboard 302
check "${SPACE_PREFIX}/.fs" 302
check_static() {
  local path="$1" allow_app_auth="${2:-false}" headers status location
  headers=$(curl --noproxy '*' -sS -D - -o /dev/null --max-time 10 \
    --cacert "$CA" --resolve "$HOST:443:$PI_ADDR" "https://$HOST$path") || {
      printf 'FAIL %s: request failed\n' "$path" >&2
      failures=$((failures + 1))
      return
    }
  status=$(awk 'NR == 1 {print $2}' <<< "$headers")
  location=$(awk 'tolower($1) == "location:" {gsub("\r", "", $2); print $2}' <<< "$headers")
  if [[ "$status" == 200 ]]; then
    printf 'OK   %s: 200\n' "$path"
  elif [[ "$status" == 401 && "$allow_app_auth" == true ]]; then
    printf 'OK   %s: SilverBullet requires its own login\n' "$path"
  elif [[ "$status" == 307 && "$location" == '/.setup/' ]]; then
    printf 'WAIT %s: finish SilverBullet first-run setup\n' "$path"
    pending=1
  else
    printf 'FAIL %s: unexpected status %s (location %s)\n' "$path" "$status" "$location" >&2
    failures=$((failures + 1))
  fi
}

check_static "${SPACE_PREFIX}/service_worker.js"
check_static "${SPACE_PREFIX}/.client/manifest.json" true
(( failures > 0 )) && exit 1
(( pending > 0 )) && exit 2
exit 0
