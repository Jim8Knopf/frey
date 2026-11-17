#!/usr/bin/env bash
# Check routing, feature availability, and the OIDC discovery back channel.
set -euo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
CA="${CA:-ca/frey-root-ca.crt}"
HOST="${HOSTNAME_IMMICH:-immich.hub.frey}"
[[ -r "$CA" ]] || { echo "Cannot read Frey CA: $CA" >&2; exit 1; }
base="https://$HOST"
curl_args=(--noproxy '*' -fsS --max-time 30 --cacert "$CA" --resolve "$HOST:443:$PI_ADDR")
curl "${curl_args[@]}" "$base/api/server/ping" | python3 -c 'import json,sys; assert json.load(sys.stdin)["res"] == "pong"'
curl "${curl_args[@]}" "$base/api/server/features" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["oauth"] and d["smartSearch"] and d["facialRecognition"]'
for redirect in "$base/auth/login" 'app.immich:///oauth-callback'; do
  body=$(python3 -c 'import json,sys; print(json.dumps({"redirectUri":sys.argv[1]}))' "$redirect")
  response=$(curl "${curl_args[@]}" -H 'Content-Type: application/json' -d "$body" "$base/api/oauth/authorize")
  auth_url=$(python3 -c 'import json,sys,urllib.parse; url=json.load(sys.stdin)["url"]; u=urllib.parse.urlparse(url); q=urllib.parse.parse_qs(u.query); assert u.scheme == "https" and u.hostname == "auth.hub.frey" and q.get("client_id") == ["immich"] and q.get("code_challenge_method") == ["S256"] and "immich_role" in q.get("scope", [""])[0].split(); print(url)' <<< "$response")
  status=$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' --max-time 30 --cacert "$CA" --resolve "auth.hub.frey:443:$PI_ADDR" "$auth_url")
  [[ "$status" == 303 || "$status" == 302 ]] || { echo "Authelia rejected the Immich authorization request: HTTP $status" >&2; exit 1; }
done
printf '%s\n' 'Immich routing, machine-learning features, and web/mobile OAuth discovery passed.'
