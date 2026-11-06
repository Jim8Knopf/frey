#!/usr/bin/env bash
# Verify anonymous access is redirected; authenticated and model checks are separate.
set -uo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
CA="${CA:-ca/frey-root-ca.crt}"
HOST="${HOSTNAME_LOCAL_AI:-ai.hub.frey}"
failures=0

if [[ ! -r "$CA" ]]; then
  echo "Cannot read Frey CA: $CA" >&2
  exit 1
fi
for path in / /health /v1/models; do
  status=$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' \
    --max-time 10 --cacert "$CA" --resolve "$HOST:443:$PI_ADDR" \
    "https://$HOST$path") || status=000
  if [[ "$status" == 302 ]]; then
    printf 'OK   %s: authentication required\n' "$path"
  else
    printf 'FAIL %s: expected authentication redirect, got %s\n' "$path" "$status" >&2
    failures=$((failures + 1))
  fi
done
(( failures == 0 ))
