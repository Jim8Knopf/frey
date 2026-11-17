#!/usr/bin/env bash
# Check routing, feature availability, the OIDC discovery back channel, and
# whether face recognition is actually finding faces.
#
# THE LAST ONE IS THE POINT. /api/server/features reports facialRecognition as
# true from the moment the feature is switched on - it says nothing about
# whether a single face has ever been found. Immich discards a face-detection
# job that fails rather than retrying it, so a library can sit at 2% coverage
# indefinitely with four healthy containers and a green feature flag. That is
# exactly what happened here, undetected, for thousands of photos.
#
#   scripts/immich-check.sh              routing, OAuth, coverage, inference
#   SKIP_SSH=1 scripts/immich-check.sh   the HTTPS half only
set -euo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_SSH="${PI_SSH:-ansible@${PI_ADDR}}"
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

if [[ -n "${SKIP_SSH:-}" ]]; then
  printf '%s\n' 'SKIP_SSH set - face-detection coverage and inference not checked.'
  exit 0
fi

ssh_pi() {
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 "$PI_SSH" "$@"
}

# -----------------------------------------------------------------------------
# THE MODEL CACHE
#
# The ML service fetches models from Hugging Face on first use. When it cannot
# reach the Hub it reads the failure as a corrupt download, DELETES the cached
# model and retries - and answers HTTP 500 meanwhile. So an empty-ish cache is
# not a slow start, it is every job from now on being thrown away.
# -----------------------------------------------------------------------------
models=$(ssh_pi "sudo find /opt/frey/appdata/immich/model-cache -name model.onnx -type f 2>/dev/null | wc -l" | tr -d '\r')
if [[ "${models:-0}" -lt 6 ]]; then
  echo "Immich has only ${models:-0} of 6 machine-learning models cached." >&2
  echo "Every face-detection, smart-search and OCR job will fail with HTTP 500 and be discarded." >&2
  echo "Get an uplink, re-run 'ansible-playbook playbooks/site.yml --tags immich', then re-queue." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# CAN IT ACTUALLY FIND A FACE
#
# The same probe the immich role runs at deploy time: a real inference request,
# because /ping answers long before any model is loaded. Output goes to a file
# on the Pi before being read back - a `docker exec` carrying the payload on
# stdout can truncate.
# -----------------------------------------------------------------------------
probe=$(ssh_pi "sudo docker exec immich_machine_learning python3 -c \"
import io, json, httpx
from PIL import Image
buf = io.BytesIO()
Image.new('RGB', (640, 640), (128, 128, 128)).save(buf, format='JPEG')
entries = {'facial-recognition': {'detection': {'modelName': 'buffalo_l', 'options': {'minScore': 0.7}}, 'recognition': {'modelName': 'buffalo_l'}}}
r = httpx.post('http://127.0.0.1:3003/predict', data={'entries': json.dumps(entries)}, files={'image': ('probe.jpg', buf.getvalue(), 'image/jpeg')}, timeout=600)
print(r.status_code)
\" > /tmp/frey-immich-probe.txt 2>&1; cat /tmp/frey-immich-probe.txt" | tr -d '\r' | tail -1)
if [[ "$probe" != "200" ]]; then
  echo "Immich machine learning could not complete a face-detection request: ${probe}" >&2
  echo "Check 'docker logs immich_machine_learning' for 'Temporary failure in name resolution'." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# COVERAGE
#
# The left join matters: an asset with no job-status row has never been looked
# at either, and counting only existing rows with a null timestamp misses it.
# -----------------------------------------------------------------------------
counts=$(ssh_pi "sudo docker exec immich_postgres sh -c '
  psql -U immich -d immich -At -F\" \" -c \"
    select
      (select count(*) from asset where \\\"deletedAt\\\" is null),
      (select count(*) from asset a
         left join asset_job_status s on s.\\\"assetId\\\" = a.id
         where a.\\\"deletedAt\\\" is null and s.\\\"facesRecognizedAt\\\" is null),
      (select count(*) from asset_face where \\\"deletedAt\\\" is null),
      (select count(*) from person where length(name) > 0)
  \" > /tmp/frey-immich-counts.txt 2>&1; cat /tmp/frey-immich-counts.txt'" | tr -d '\r' | grep -E '^[0-9]+ ' | tail -1)

read -r assets pending faces people <<< "$counts"
[[ -n "${assets:-}" && -n "${pending:-}" ]] || { echo "Could not read Immich face-detection counts: ${counts}" >&2; exit 1; }

done_count=$((assets - pending))
if [[ "$assets" -gt 0 ]]; then
  percent=$((done_count * 100 / assets))
else
  percent=100
fi
printf 'Face detection: %s of %s assets scanned (%s%%), %s faces found, %s people named.\n' \
  "$done_count" "$assets" "$percent" "$faces" "$people"

# A library with assets and no faces at all is the failure this script exists
# for: healthy containers, a green feature flag, and nothing ever scanned.
if [[ "$assets" -gt 0 && "$faces" -eq 0 ]]; then
  echo "Immich has ${assets} assets and has found no faces at all." >&2
  echo "Re-queue the work with scripts/immich-reprocess.sh." >&2
  exit 1
fi
if [[ "$pending" -gt 50 ]]; then
  printf '%s\n' "${pending} assets are still waiting for face detection. Normal while a pass is running;"
  printf '%s\n' "if it is not going down, the jobs are being discarded - run scripts/immich-reprocess.sh."
fi
printf '%s\n' 'Immich face recognition passed: models cached, inference working, coverage reported.'
