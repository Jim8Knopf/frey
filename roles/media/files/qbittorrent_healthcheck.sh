#!/bin/bash
#
# qBittorrent Smart Healthcheck Script
#
# This script checks:
# 1. qBittorrent Web UI is responsive
# 2. Active download activity (downloading torrents or download speed > 0)
# 3. Internet connectivity
# 4. If internet is available but no downloads for STALL_THRESHOLD seconds, mark unhealthy
#
# Exit codes:
# 0 = Healthy (service is working properly)
# 1 = Unhealthy (service should be restarted)

set -e

# Configuration
WEBUI_PORT="${WEBUI_PORT:-8080}"
WEBUI_URL="http://localhost:${WEBUI_PORT}"
STATE_FILE="/tmp/qbt_health_state"
STALL_THRESHOLD="${QBT_STALL_THRESHOLD:-300}"  # 5 minutes default
INTERNET_CHECK_HOST="${QBT_INTERNET_HOST:-1.1.1.1}"
API_TIMEOUT=5

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Check if qBittorrent Web UI is responding
check_webui() {
    if curl -sf --max-time "$API_TIMEOUT" "${WEBUI_URL}/api/v2/app/version" >/dev/null 2>&1; then
        return 0
    else
        log "ERROR: qBittorrent Web UI not responding"
        return 1
    fi
}

# Check if there are active downloads
check_active_downloads() {
    local transfer_info
    transfer_info=$(curl -sf --max-time "$API_TIMEOUT" "${WEBUI_URL}/api/v2/transfer/info" 2>/dev/null)

    if [ -z "$transfer_info" ]; then
        log "WARNING: Could not fetch transfer info from qBittorrent API"
        return 1
    fi

    # Extract download speed (dl_info_speed field)
    local dl_speed
    dl_speed=$(echo "$transfer_info" | grep -o '"dl_info_speed":[0-9]*' | cut -d':' -f2)

    # Check if download speed > 0 (active downloading)
    if [ -n "$dl_speed" ] && [ "$dl_speed" -gt 0 ]; then
        log "INFO: Active downloads detected (speed: ${dl_speed} bytes/s)"
        return 0
    fi

    # Alternative check: count downloading torrents
    local torrent_list
    torrent_list=$(curl -sf --max-time "$API_TIMEOUT" "${WEBUI_URL}/api/v2/torrents/info?filter=downloading" 2>/dev/null)

    local downloading_count
    downloading_count=$(echo "$torrent_list" | grep -c '"state":"downloading"' || echo "0")

    if [ "$downloading_count" -gt 0 ]; then
        log "INFO: Active downloads detected (${downloading_count} torrents downloading)"
        return 0
    fi

    log "INFO: No active downloads detected"
    return 1
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
    # Always check if Web UI is responsive first
    if ! check_webui; then
        log "UNHEALTHY: Web UI not responding"
        exit 1
    fi

    # Check for active downloads
    local has_downloads=0
    if check_active_downloads; then
        has_downloads=1
    fi

    # Check internet connectivity
    local has_internet=0
    if check_internet; then
        has_internet=1
    fi

    local current_time
    current_time=$(date +%s)
    local stall_start_time
    stall_start_time=$(read_state)

    # Decision logic
    if [ "$has_downloads" -eq 1 ]; then
        # Downloads active - reset stall timer and mark healthy
        write_state "0"
        log "HEALTHY: Active downloads detected"
        exit 0
    fi

    if [ "$has_internet" -eq 0 ]; then
        # No internet - can't download anyway, don't penalize qBittorrent
        write_state "0"
        log "HEALTHY: No internet (not qBittorrent's fault)"
        exit 0
    fi

    # No downloads + has internet = potential stall
    if [ "$stall_start_time" -eq 0 ]; then
        # First time detecting this state - start timer
        write_state "$current_time"
        log "INFO: No downloads but internet available - starting stall timer"
        exit 0
    fi

    # Calculate stall duration
    local stall_duration=$((current_time - stall_start_time))

    if [ "$stall_duration" -ge "$STALL_THRESHOLD" ]; then
        # Stalled too long - mark unhealthy to trigger restart
        log "UNHEALTHY: No downloads for ${stall_duration}s (threshold: ${STALL_THRESHOLD}s) despite internet connectivity"
        write_state "0"  # Reset state for next cycle
        exit 1
    else
        log "INFO: No downloads for ${stall_duration}s (threshold: ${STALL_THRESHOLD}s)"
        exit 0
    fi
}

# Run main function
main
