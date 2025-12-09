#!/usr/bin/env bash
set -euo pipefail

# Require bash (arrays used)
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "Please run with bash: ./frey-portal-helper.sh"
  exit 1
fi

# Usage: ./frey-portal-helper.sh <pi-host-or-ip> [portal_url]
# Example: ./frey-portal-helper.sh frey http://10.5.0.1/
# Defaults: host 'frey', user 'ansible', SOCKS port auto-pick (1080-1100), portal URL captive.apple.com
# Optional env:
#   PI_HOST, PI_USER, PORTAL_URL, SOCKS_PORT, SSH_IDENTITY (path to key), SSH_OPTS (extra ssh args)

PI_HOST="${1:-${PI_HOST:-frey}}"
PORTAL_URL="${2:-${PORTAL_URL:-http://captive.apple.com/}}"  # Use the portal URL printed by `frey wifi portal` if provided
PI_USER="${PI_USER:-ansible}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
SSH_IDENTITY="${SSH_IDENTITY:-$HOME/.ssh/id_rsa_ansible}"
SSH_OPTS_EXTRA=()

if [[ -n "$SSH_IDENTITY" && -f "$SSH_IDENTITY" ]]; then
  SSH_OPTS_EXTRA+=(-i "$SSH_IDENTITY")
fi

if [[ -n "${SSH_OPTS:-}" ]]; then
  # shellcheck disable=SC2206
  SSH_OPTS_EXTRA+=(${SSH_OPTS})
fi

tmp_profile=$(mktemp -d /tmp/frey-portal.XXXXXX)
SSH_STARTED=false
SSH_LOG="/tmp/frey-portal-ssh.log"

cleanup() {
  if [[ -n "${SSH_PID:-}" ]]; then
    if $SSH_STARTED; then
      kill "$SSH_PID" 2>/dev/null || true
    fi
  fi
  rm -rf "$tmp_profile"
}
trap cleanup EXIT

is_port_free() {
  local port="$1"
  if ss -lnt "( sport = :$port )" 2>/dev/null | awk 'NR>1 {print}' | grep -q .; then
    return 1
  fi
  return 0
}

pick_socks_port() {
  local base="${SOCKS_PORT:-1080}"
  if is_port_free "$base"; then
    echo "$base"
    return 0
  fi
  for p in $(seq 1081 1100); do
    if is_port_free "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

SOCKS_PORT_CHOSEN=$(pick_socks_port) || { echo "No free port found for SOCKS in 1080-1100 range."; exit 1; }

echo "Starting SOCKS tunnel to ${PI_USER}@${PI_HOST} on localhost:${SOCKS_PORT_CHOSEN} ..."
ssh_cmd=(ssh
  -o ExitOnForwardFailure=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o BatchMode=yes
  -D "localhost:${SOCKS_PORT_CHOSEN}"
  "${SSH_OPTS_EXTRA[@]}"
  "${PI_USER}@${PI_HOST}"
)

# Run ssh in background and verify it stays up
"${ssh_cmd[@]}" -N >"$SSH_LOG" 2>&1 &
SSH_PID=$!
sleep 1
if kill -0 "$SSH_PID" 2>/dev/null; then
  SSH_STARTED=true
else
  echo "Failed to start SSH tunnel. Password auth is not supported in background."
  echo "Tried host: ${PI_HOST}, user: ${PI_USER}, port: ${SOCKS_PORT_CHOSEN}"
  if [[ ! -f "$SSH_IDENTITY" ]]; then
    echo "No key found at SSH_IDENTITY=${SSH_IDENTITY}. Provide a key or set SSH_IDENTITY."
  fi
  echo "Ensure key-based SSH works: ssh -i ${SSH_IDENTITY} ${PI_USER}@${PI_HOST}"
  echo "SSH log:"
  tail -n 20 "$SSH_LOG" 2>/dev/null || true
  exit 1
fi

if [[ -z "${SSH_PID:-}" ]]; then
  echo "Failed to start SSH tunnel. Check connectivity/credentials."
  echo "Tried host: ${PI_HOST}, user: ${PI_USER}, port: ${SOCKS_PORT_CHOSEN}"
  echo "If host key changed, the script already ignores known_hosts; ensure SSH works: ssh ${PI_USER}@${PI_HOST}"
  exit 1
fi

launch_chromium() {
  chromium --user-data-dir="$tmp_profile/chrome" \
    --proxy-server="socks5://localhost:${SOCKS_PORT_CHOSEN}" \
    --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE localhost" \
    "$PORTAL_URL" >/dev/null 2>&1 &
}

launch_firefox() {
  mkdir -p "$tmp_profile/firefox"
  cat >"$tmp_profile/firefox/user.js" <<EOF
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", ${SOCKS_PORT_CHOSEN});
user_pref("network.proxy.socks_remote_dns", true);
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1");
EOF
  firefox -profile "$tmp_profile/firefox" -no-remote "$PORTAL_URL" >/dev/null 2>&1 &
}

if command -v chromium >/dev/null 2>&1; then
  launch_chromium
elif command -v firefox >/dev/null 2>&1; then
  launch_firefox
else
  echo "Need chromium or firefox installed."
  exit 1
fi

echo "Browser opened via SOCKS5 (localhost:${SOCKS_PORT_CHOSEN}). Portal URL: ${PORTAL_URL}"
echo "Complete the portal login in the opened browser window."
read -r -p "Press ENTER when the portal login is done to tear down the tunnel..."

echo "Cleaning up..."
# Prevent double cleanup from the EXIT trap once we clean manually
trap - EXIT
cleanup
exit 0
