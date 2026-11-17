#!/usr/bin/env bash
# Re-queue Immich machine-learning work that was lost rather than retried.
#
# WHY THIS IS NEEDED AT ALL
#
# When the ML container cannot reach Hugging Face it answers HTTP 500, and the
# server DISCARDS the job instead of re-queueing it. Nothing in Immich ever
# picks those assets up again: the nightly tasks cover missing thumbnails and
# clustering new faces, never missed detection. So one offline window does not
# delay face recognition for a few thousand photos, it cancels it - silently,
# with every container healthy. Redeploying does not fix it. This does.
#
#   scripts/immich-reprocess.sh                     face detection, missing only
#   scripts/immich-reprocess.sh faceDetection ocr   several queues
#   scripts/immich-reprocess.sh --force             EVERY asset again, not just missing
#   scripts/immich-reprocess.sh --yes               no confirmation prompt
#
# A pass over a full library is HOURS of CPU on four cores shared with the
# gateway. The role caps the ML container at three of them so FreyHub stays
# usable, but this is still best started while parked.
#
# THE API KEY
#
# Immich's job API is admin-only and Frey has no stored Immich credential, so
# this mints a temporary key, uses it, and deletes it on exit. The secret is
# generated locally and only ever leaves this machine inside the HTTPS request
# header - only its SHA-256 is sent to the Pi, which is exactly what Immich
# stores.
set -euo pipefail

PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_SSH="${PI_SSH:-ansible@${PI_ADDR}}"
CA="${CA:-ca/frey-root-ca.crt}"
HOST="${HOSTNAME_IMMICH:-immich.hub.frey}"
KEY_NAME='frey-reprocess (temporary)'

force=false
assume_yes=false
queues=()
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    --yes|-y) assume_yes=true ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 64 ;;
    *) queues+=("$arg") ;;
  esac
done
[[ ${#queues[@]} -gt 0 ]] || queues=(faceDetection)

for queue in "${queues[@]}"; do
  case "$queue" in
    faceDetection|facialRecognition|smartSearch|ocr|thumbnailGeneration|metadataExtraction) ;;
    *) echo "Unknown queue: $queue" >&2; exit 64 ;;
  esac
done

[[ -r "$CA" ]] || { echo "Cannot read Frey CA: $CA" >&2; exit 1; }

ssh_pi() {
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 "$PI_SSH" "$@"
}

psql_pi() {
  # Written to a file inside the container and read back, because a
  # `docker exec` carrying the payload on stdout can truncate.
  ssh_pi "sudo docker exec immich_postgres sh -c 'psql -U immich -d immich -At -F\" \" -c \"$1\" > /tmp/frey-reprocess.txt 2>&1; cat /tmp/frey-reprocess.txt'" | tr -d '\r'
}

counts() {
  psql_pi "select (select count(*) from asset where \\\"deletedAt\\\" is null), (select count(*) from asset a left join asset_job_status s on s.\\\"assetId\\\" = a.id where a.\\\"deletedAt\\\" is null and s.\\\"facesRecognizedAt\\\" is null), (select count(*) from asset_face where \\\"deletedAt\\\" is null)" | grep -E '^[0-9]+ ' | tail -1
}

read -r assets pending faces <<< "$(counts)"
[[ -n "${assets:-}" ]] || { echo "Could not read Immich's asset counts; is the stack up?" >&2; exit 1; }
printf 'Before: %s assets, %s awaiting face detection, %s faces found.\n' "$assets" "$pending" "$faces"

if [[ "$force" == true ]]; then
  printf 'This will re-process EVERY asset in: %s\n' "${queues[*]}"
else
  printf 'This will queue unprocessed assets in: %s\n' "${queues[*]}"
fi
printf '%s\n' 'Expect hours of CPU. The ML container is capped at three of four cores so the gateway keeps working.'
if [[ "$assume_yes" != true ]]; then
  read -r -p 'Continue? [y/N] ' reply
  [[ "$reply" == [yY]* ]] || { echo 'Aborted.'; exit 0; }
fi

# --- a temporary admin key -----------------------------------------------------
secret="$(openssl rand -hex 32)"
hash="$(printf '%s' "$secret" | openssl dgst -sha256 | awk '{print $NF}')"

cleanup() {
  psql_pi "delete from api_key where name = '${KEY_NAME}'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The oldest surviving user is the local administrator created at setup. The
# isAdmin test goes through to_jsonb so this keeps working if the column moves.
inserted=$(psql_pi "insert into api_key (name, key, \\\"userId\\\", permissions) select '${KEY_NAME}', decode('${hash}', 'hex'), u.id, '{job.create,job.read}' from \\\"user\\\" u where u.\\\"deletedAt\\\" is null and coalesce((to_jsonb(u) ->> 'isAdmin')::boolean, true) order by u.\\\"createdAt\\\" limit 1 returning \\\"userId\\\"" | grep -cE '^[0-9a-f-]{36}$' || true)
if [[ "${inserted:-0}" -lt 1 ]]; then
  echo 'Could not create a temporary API key - no administrator account found in Immich.' >&2
  echo 'Create the local admin from a trusted device first; see roles/immich/README.md.' >&2
  exit 1
fi

api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(--noproxy '*' -sS --max-time 60 --cacert "$CA" --resolve "$HOST:443:$PI_ADDR"
    -H "x-api-key: $secret" -H 'Content-Type: application/json' -X "$method")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}" -o /dev/null -w '%{http_code}' "https://$HOST$path"
}

status=$(api GET /api/jobs)
[[ "$status" == 200 ]] || { echo "The temporary API key was rejected (HTTP $status)." >&2; exit 1; }

for queue in "${queues[@]}"; do
  status=$(api PUT "/api/jobs/${queue}" "{\"command\":\"start\",\"force\":${force}}")
  if [[ "$status" == 200 || "$status" == 204 ]]; then
    printf 'Queued: %s\n' "$queue"
  else
    echo "Failed to queue ${queue}: HTTP ${status}" >&2
    exit 1
  fi
done

# Give the server a moment to fill the queue before reporting depth, so the
# output is evidence rather than a reassuring zero.
sleep 20
printf '%s\n' 'Queue depth now:'
for queue in "${queues[@]}"; do
  depth=$(ssh_pi "sudo docker exec immich_redis valkey-cli llen immich_bull:${queue}:wait" | tr -d '\r')
  active=$(ssh_pi "sudo docker exec immich_redis valkey-cli zcard immich_bull:${queue}:active" | tr -d '\r')
  printf '  %-20s waiting=%s active=%s\n' "$queue" "${depth:-?}" "${active:-?}"
done

printf '%s\n' 'Watch it drain with: scripts/immich-check.sh (or the Immich dashboard'"'"'s Jobs page).'
printf '%s\n' 'If waiting stays at 0 and nothing is active, the jobs are failing - read'
printf '%s\n' '`docker logs immich_machine_learning` before re-running this.'
