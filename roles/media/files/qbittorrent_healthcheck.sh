#!/bin/bash
#
# qBittorrent Smart Healthcheck Script
#
# This script checks:
# 1. qBittorrent Web UI is responsive
# 2. Active download activity (downloading torrents or download speed > 0)
# 3. Internet connectivity
# 4. If torrents are queued but no progress is made for STALL_THRESHOLD seconds (with internet),
#    mark unhealthy to trigger a restart
#
# Exit codes:
# 0 = Healthy (service is working properly)
# 1 = Unhealthy (service should be restarted)

set -uo pipefail

# Configuration
WEBUI_PORT="${WEBUI_PORT:-8080}"
WEBUI_URL="http://localhost:${WEBUI_PORT}"
STATE_FILE="/tmp/qbt_health_state"
COOKIE_JAR="/tmp/qbt_health_cookie"
STALL_THRESHOLD="${QBT_STALL_THRESHOLD:-300}"  # 5 minutes default
INTERNET_CHECK_HOST="${QBT_INTERNET_HOST:-1.1.1.1}"
API_TIMEOUT=5
AUTH_FLAGS=()
CURL_OPTS=(--silent --show-error --max-time "$API_TIMEOUT")

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Check if qBittorrent Web UI is responding (200 or auth-required 403 both mean reachable)
check_webui() {
    local http_code
    http_code=$(
        curl -o /dev/null -w "%{http_code}" "${CURL_OPTS[@]}" "${AUTH_FLAGS[@]}" \
            "${WEBUI_URL}/api/v2/app/version" 2>/dev/null || echo "000"
    )

    if [ "$http_code" = "200" ] || [ "$http_code" = "403" ]; then
        return 0
    fi

    log "ERROR: qBittorrent Web UI unreachable (status: ${http_code})"
    return 1
}

# Authenticate against the qBittorrent API (only when credentials are provided)
authenticate() {
    if [ -z "${QBT_USERNAME:-}" ] || [ -z "${QBT_PASSWORD:-}" ]; then
        # No credentials provided — fall back to unauthenticated calls (best effort)
        return 0
    fi

    local response
    response=$(
        curl "${CURL_OPTS[@]}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
            --data "username=${QBT_USERNAME}&password=${QBT_PASSWORD}" \
            "${WEBUI_URL}/api/v2/auth/login" 2>/dev/null || true
    )

    if echo "$response" | grep -q "Ok."; then
        AUTH_FLAGS=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")
        return 0
    fi

    log "WARNING: Authentication failed for provided qBittorrent credentials"
    return 1
}

# Fetch download speed from the API (returns numeric value or 0 on error)
get_download_speed() {
    local transfer_info
    if ! transfer_info=$(curl -f "${CURL_OPTS[@]}" "${AUTH_FLAGS[@]}" "${WEBUI_URL}/api/v2/transfer/info" 2>/dev/null); then
        log "WARNING: Could not fetch transfer info from qBittorrent API"
        echo "0"
        return 1
    fi

    local dl_speed
    dl_speed=$(echo "$transfer_info" | sed -n 's/.*"dl_info_speed":\([0-9]*\).*/\1/p' | head -n 1)
    if [ -z "$dl_speed" ]; then
        dl_speed="0"
    fi

    echo "$dl_speed"
    return 0
}

# Count torrents matching a filter (e.g., downloading, stalledDL)
get_torrent_count() {
    local filter="$1"
    local torrents
    torrents=$(curl -f "${CURL_OPTS[@]}" "${AUTH_FLAGS[@]}" "${WEBUI_URL}/api/v2/torrents/info?filter=${filter}" 2>/dev/null || true)

    if [ -z "$torrents" ]; then
        echo "0"
        return 1
    fi

    local count
    count=$(echo "$torrents" | grep -c '"state"' || true)
    echo "${count:-0}"
    return 0
}

# Check internet connectivity
check_internet() {
    if ping -c 1 -W 2 "$INTERNET_CHECK_HOST" >/dev/null 2>&1; then
        return 0
    else
        log "INFO: No internet connectivity detected"
        return 1
    fi
}

# Read state file (format: timestamp)
read_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

# Write state file
write_state() {
    echo "$1" > "$STATE_FILE"
}

# Main healthcheck logic
main() {
    # Authenticate to the API (if credentials provided)
    if ! authenticate; then
        log "INFO: Continuing without authenticated API session"
    fi

    # Verify Web UI reachability
    if ! check_webui; then
        log "UNHEALTHY: Web UI not responding"
        exit 1
    fi

    local download_speed
    download_speed=$(get_download_speed)

    local downloading_count
    downloading_count=$(get_torrent_count "downloading")

    local stalled_count
    stalled_count=$(get_torrent_count "stalledDL")

    local active_candidates=$((downloading_count + stalled_count))

    local current_time
    current_time=$(date +%s)
    local stall_start_time
    stall_start_time=$(read_state)

    # Decision logic
    if [ "$active_candidates" -eq 0 ]; then
        # No queued downloads — being idle is healthy
        write_state "0"
        log "HEALTHY: No active or stalled downloads"
        exit 0
    fi

    # Any download activity counts as healthy
    if [ "$download_speed" -gt 0 ] || [ "$downloading_count" -gt 0 ]; then
        write_state "0"
        log "HEALTHY: Active downloads detected (speed: ${download_speed} bytes/s)"
        exit 0
    fi

    # Check internet connectivity
    local has_internet=0
    if check_internet; then
        has_internet=1
    fi

    if [ "$has_internet" -eq 0 ]; then
        # No internet - can't download anyway, don't penalize qBittorrent
        write_state "0"
        log "HEALTHY: No internet (not qBittorrent's fault)"
        exit 0
    fi

    # No download progress + has internet = potential stall
    if [ "$stall_start_time" -eq 0 ]; then
        # First time detecting this state - start timer
        write_state "$current_time"
        log "INFO: No download progress but internet available - starting stall timer"
        exit 0
    fi

    # Calculate stall duration
    local stall_duration=$((current_time - stall_start_time))

    if [ "$stall_duration" -ge "$STALL_THRESHOLD" ]; then
        # Stalled too long - mark unhealthy to trigger restart
        log "UNHEALTHY: No download progress for ${stall_duration}s (threshold: ${STALL_THRESHOLD}s) despite internet connectivity"
        write_state "0"  # Reset state for next cycle
        exit 1
    else
        log "INFO: No download progress for ${stall_duration}s (threshold: ${STALL_THRESHOLD}s)"
        exit 0
    fi
}

# Run main function
main
