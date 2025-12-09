#!/bin/bash
# ==============================================================================
# FREY WIFI ROAMING DAEMON
# ==============================================================================
# Automatic WiFi roaming system that continuously monitors and switches
# between WiFi networks to maintain the best possible internet connection
#
# FEATURES:
# - Adaptive scanning (aggressive when no connection, conservative when stable)
# - Intelligent network scoring and selection
# - Automatic captive portal handling
# - Internet verification after every connection
# - MQTT integration for Home Assistant/n8n control
# - Network history tracking
# - Blacklist management
#
# USAGE:
#   frey-wifi-roaming-daemon [--verbose] [--foreground]
#
# CONFIGURATION:
#   /etc/frey/wifi-roaming.conf
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
CONFIG_FILE="/etc/frey/wifi-roaming.conf"
KNOWN_NETWORKS_FILE="/etc/frey/known-networks.conf"
NETWORK_HISTORY_FILE="/var/lib/frey/wifi-network-history.json"
BLACKLIST_FILE="/var/lib/frey/wifi-blacklist.json"
STATE_FILE="/var/run/frey-wifi-roaming.state"
LOG_FILE="/var/log/frey-wifi-roaming.log"
PID_FILE="/var/run/frey-wifi-roaming.pid"
PORTAL_STATE_FILE="/var/lib/frey/captive-portal/portal.state"
LOCKED_SSID_FILE="/var/run/frey-wifi-locked-ssid"

# Default settings (overridden by config file)
INTERFACE_CLIENT="wlan0"
SCAN_INTERVAL_DEFAULT=120
SCAN_INTERVAL_NO_CONNECTION=30
SCAN_INTERVAL_NO_INTERNET=60
SCAN_INTERVAL_GOOD=600
MIN_SIGNAL_DBM=-85
SWITCH_THRESHOLD=15
MQTT_ENABLED=true
MQTT_BROKER="localhost"
MQTT_PORT=1883
MQTT_TOPIC_PREFIX="frey/wifi/roaming"
SWITCH_THRESHOLD_NO_INTERNET=0

# Runtime state
CURRENT_SSID=""
CURRENT_SIGNAL=0
HAS_INTERNET=false
SCAN_INTERVAL=$SCAN_INTERVAL_DEFAULT
DAEMON_ENABLED=true
VERBOSE=false
FOREGROUND=false
PORTAL_FAIL_BACKOFF=60
PORTAL_FAIL_BACKOFF_OPEN=30
SCANNING_PAUSED=false  # Signal-based pause/resume control

# ==============================================================================
# Signal Handlers for Pause/Resume Control
# ==============================================================================
# SIGUSR1 = pause scanning, SIGUSR2 = resume scanning
# Usage: kill -SIGUSR1 <pid>  (pause)
#        kill -SIGUSR2 <pid>  (resume)

handle_pause() {
    SCANNING_PAUSED=true
    log INFO "🔇 WiFi roaming PAUSED by user signal (SIGUSR1)"
    log INFO "Send SIGUSR2 to resume scanning"
}

handle_resume() {
    SCANNING_PAUSED=false
    log INFO "🔊 WiFi roaming RESUMED by user signal (SIGUSR2)"
}

# Register signal handlers
trap handle_pause SIGUSR1
trap handle_resume SIGUSR2
LAST_CONNECTED_OPEN=false
OPEN_FAIL_BLACKLIST=60
# Ignore FreyHub AP to prevent wlan0 from connecting to own wlan1 (routing loop prevention)
DEFAULT_IGNORE_SSIDS=("FreyHub")

# Connection stability
INTERNET_CHECK_FAILURES=0
MAX_INTERNET_CHECK_FAILURES=2  # Allow up to 2 failures before treating as no-internet
LAST_SCAN_ON_KNOWN_NETWORK=0
MIN_KNOWN_NETWORK_SCAN_INTERVAL=600  # Only scan every 10 mins when on stable known network

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ==============================================================================
# Logging
# ==============================================================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"

    if [ "$VERBOSE" = true ] || [ "$FOREGROUND" = true ]; then
        case $level in
            INFO)
                echo -e "${GREEN}[${level}]${NC} ${message}" >&2
                ;;
            WARN)
                echo -e "${YELLOW}[${level}]${NC} ${message}" >&2
                ;;
            ERROR)
                echo -e "${RED}[${level}]${NC} ${message}" >&2
                ;;
            *)
                echo -e "${BLUE}[${level}]${NC} ${message}" >&2
                ;;
        esac
    fi
}

# ==============================================================================
# MQTT Publishing
# ==============================================================================
mqtt_publish() {
    if [ "$MQTT_ENABLED" != true ]; then
        return
    fi

    local topic="$1"
    local message="$2"

    if command -v mosquitto_pub &>/dev/null; then
        mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" \
            -t "${MQTT_TOPIC_PREFIX}/${topic}" \
            -m "$message" \
            2>/dev/null || true
    fi
}

# ==============================================================================
# Configuration Loading
# ==============================================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log INFO "Loading configuration from $CONFIG_FILE"
        # shellcheck disable=SC1090
        source "$CONFIG_FILE" 2>/dev/null || true
    fi

    # Default ignore SSIDs if not set in config
    if ! declare -p IGNORE_SSIDS >/dev/null 2>&1; then
        IGNORE_SSIDS=("${DEFAULT_IGNORE_SSIDS[@]}")
    fi
}

# ==============================================================================
# Initialization
# ==============================================================================
init_daemon() {
    log INFO "========================================"
    log INFO "Frey WiFi Roaming Daemon Starting"
    log INFO "========================================"

    # Create necessary directories
    mkdir -p "$(dirname "$STATE_FILE")"
    mkdir -p "$(dirname "$NETWORK_HISTORY_FILE")"
    mkdir -p "$(dirname "$LOG_FILE")"

    # Initialize JSON files if they don't exist
    if [ ! -f "$NETWORK_HISTORY_FILE" ]; then
        echo "{}" > "$NETWORK_HISTORY_FILE"
    fi

    if [ ! -f "$BLACKLIST_FILE" ]; then
        echo "{}" > "$BLACKLIST_FILE"
    fi

    # Write PID file
    echo $$ > "$PID_FILE"

    # Publish initial status
    mqtt_publish "status/state" "starting"

    log INFO "Daemon initialized successfully"
}

# ==============================================================================
# Get current WiFi status
# ==============================================================================
get_current_status() {
    if ! wpa_cli -i "$INTERFACE_CLIENT" status &>/dev/null; then
        CURRENT_SSID=""
        CURRENT_SIGNAL=0
        return 1
    fi

    local status
    status=$(wpa_cli -i "$INTERFACE_CLIENT" status 2>/dev/null)

    if echo "$status" | grep -q "wpa_state=COMPLETED"; then
        CURRENT_SSID=$(echo "$status" | grep "^ssid=" | cut -d'=' -f2)
        CURRENT_SIGNAL=$(wpa_cli -i "$INTERFACE_CLIENT" signal_poll 2>/dev/null | grep "^RSSI=" | cut -d'=' -f2 || echo "0")
        return 0
    else
        CURRENT_SSID=""
        CURRENT_SIGNAL=0
        return 1
    fi
}

# ==============================================================================
# Verify internet connectivity
# ==============================================================================
verify_internet() {
    if /usr/local/bin/frey-wifi-internet-verify --interface "$INTERFACE_CLIENT" &>/dev/null; then
        HAS_INTERNET=true
        INTERNET_CHECK_FAILURES=0  # Reset failure counter on success
        return 0
    else
        # Allow transient failures
        INTERNET_CHECK_FAILURES=$((INTERNET_CHECK_FAILURES + 1))
        
        if [ $INTERNET_CHECK_FAILURES -ge $MAX_INTERNET_CHECK_FAILURES ]; then
            HAS_INTERNET=false
        fi
        return 1
    fi
}

# ==============================================================================
# Scan for available networks
# ==============================================================================
scan_networks() {
    log DEBUG "Scanning for available networks..."

    # Trigger scan
    wpa_cli -i "$INTERFACE_CLIENT" scan &>/dev/null || return 1

    # Wait for scan results
    sleep 3

    # Get scan results
    local scan_results
    scan_results=$(wpa_cli -i "$INTERFACE_CLIENT" scan_results 2>/dev/null | tail -n +2)

    if [ -z "$scan_results" ]; then
        log WARN "No networks found in scan"
        return 1
    fi

    echo "$scan_results"
}

# ==============================================================================
# Score and rank networks
# ==============================================================================
rank_networks() {
    local scan_results="$1"
    local ranked_networks=""

    while IFS=$'\t' read -r bssid freq signal flags ssid; do
        # Skip empty SSIDs
        [ -z "$ssid" ] && continue

        # Skip hidden networks
        [[ "$ssid" == *"\\x00"* ]] && continue

        # Check minimum signal threshold
        if [ "$signal" -lt "$MIN_SIGNAL_DBM" ]; then
            log DEBUG "Skipping '$ssid' - signal too weak: ${signal} dBm"
            continue
        fi

        # Determine security type
        local security="Unknown"
        if [[ "$flags" =~ WPA ]]; then
            security="WPA"
        elif [[ "$flags" =~ WEP ]]; then
            security="WEP"
        else
            security="Open"
        fi

        # Score the network
        local score
        score=$(/usr/local/bin/frey-wifi-network-scorer --ssid "$ssid" --signal "$signal" --security "$security" 2>/dev/null || echo "0")

        log DEBUG "Network: '$ssid' Signal: ${signal} dBm Security: ${security} Score: ${score}"

        # Add to ranked list (format: score|ssid|signal|security)
        ranked_networks+="${score}|${ssid}|${signal}|${security}"$'\n'
    done <<< "$scan_results"

    # Sort by score (descending)
    echo "$ranked_networks" | grep -v "^$" | sort -t'|' -k1 -nr
}

# ==============================================================================
# Connect to network
# ==============================================================================
connect_to_network() {
    local ssid="$1"
    local password="${2:-}"

    log INFO "Attempting to connect to: '$ssid'"

    # Add or select network
    local network_id

    if [ -n "$password" ]; then
        # Add new network with password
        network_id=$(wpa_cli -i "$INTERFACE_CLIENT" add_network | tail -1)
        wpa_cli -i "$INTERFACE_CLIENT" set_network "$network_id" ssid "\"$ssid\"" &>/dev/null
        wpa_cli -i "$INTERFACE_CLIENT" set_network "$network_id" psk "\"$password\"" &>/dev/null
    else
        # Open network or check if already configured
        local existing_id
        existing_id=$(wpa_cli -i "$INTERFACE_CLIENT" list_networks | grep -w "$ssid" | awk '{print $1}' | head -1)

        if [ -n "$existing_id" ]; then
            network_id="$existing_id"
        else
            network_id=$(wpa_cli -i "$INTERFACE_CLIENT" add_network | tail -1)
            wpa_cli -i "$INTERFACE_CLIENT" set_network "$network_id" ssid "\"$ssid\"" &>/dev/null
            wpa_cli -i "$INTERFACE_CLIENT" set_network "$network_id" key_mgmt NONE &>/dev/null
        fi
    fi

    # Enable and select network
    wpa_cli -i "$INTERFACE_CLIENT" enable_network "$network_id" &>/dev/null
    wpa_cli -i "$INTERFACE_CLIENT" select_network "$network_id" &>/dev/null

    # Track whether this is an open network (for portal/backoff logic)
    LAST_CONNECTED_OPEN=false
    if [ -z "$password" ]; then
        LAST_CONNECTED_OPEN=true
    fi

    # Wait for connection
    local attempts=0
    while [ $attempts -lt 15 ]; do
        sleep 1
        if wpa_cli -i "$INTERFACE_CLIENT" status | grep -q "wpa_state=COMPLETED"; then
            log INFO "✓ Connected to WiFi: '$ssid'"

            # Request IP address, retrying with dhcpcd then dhclient (skip if dhcpcd already managing interface)
            local dh_attempt=0
            while [ $dh_attempt -lt 3 ]; do
                local current_ip
                current_ip=$(ip -4 addr show "$INTERFACE_CLIENT" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)

                # If we have a non-link-local IP, leave DHCP alone (whether or not dhcpcd is running)
                if [ -n "$current_ip" ] && [[ ! "$current_ip" =~ ^169\.254\. ]]; then
                    if pgrep -f "dhcpcd.*$INTERFACE_CLIENT" >/dev/null 2>&1; then
                        break
                    fi
                    break
                fi

                # No valid IP yet; if dhcpcd is already working on it, wait and retry
                if pgrep -f "dhcpcd.*$INTERFACE_CLIENT" >/dev/null 2>&1; then
                    sleep 2
                    dh_attempt=$((dh_attempt + 1))
                    continue
                fi

                # No IP and no dhcpcd running - try dhcpcd first
                if command -v dhcpcd &>/dev/null; then
                    dhcpcd -n "$INTERFACE_CLIENT" &>/dev/null || dhcpcd "$INTERFACE_CLIENT" &>/dev/null || true
                fi
                sleep 2

                current_ip=$(ip -4 addr show "$INTERFACE_CLIENT" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
                if [ -n "$current_ip" ] && [[ ! "$current_ip" =~ ^169\.254\. ]]; then
                    break
                fi

                # dhcpcd failed, try dhclient as backup
                if command -v dhclient &>/dev/null; then
                    timeout 15 dhclient -1 -v "$INTERFACE_CLIENT" &>/dev/null || true
                fi
                sleep 3

                dh_attempt=$((dh_attempt + 1))
            done

            if ! ip -4 addr show "$INTERFACE_CLIENT" | grep -q "inet "; then
                log WARN "Failed to obtain IPv4 lease after multiple attempts"
                
                # For open networks, try portal bypass before giving up
                if [ "${LAST_CONNECTED_OPEN:-false}" = true ]; then
                    log INFO "Open network with DHCP failure - attempting captive portal bypass..."
                    if handle_captive_portal "$ssid"; then
                        # Portal was bypassed - try DHCP again
                        if command -v dhcpcd &>/dev/null; then
                            dhcpcd -n "$INTERFACE_CLIENT" &>/dev/null || dhcpcd "$INTERFACE_CLIENT" &>/dev/null || true
                        fi
                        sleep 2
                        if ip -4 addr show "$INTERFACE_CLIENT" | grep -q "inet "; then
                            return 0
                        fi
                    fi
                fi
                
                return 1
            fi

            return 0
        fi
        attempts=$((attempts + 1))
    done

    log WARN "✗ Failed to connect to: '$ssid'"
    wpa_cli -i "$INTERFACE_CLIENT" remove_network "$network_id" &>/dev/null || true
    return 1
}

# ==============================================================================
# Handle captive portal
# ==============================================================================
handle_captive_portal() {
    local ssid="$1"

    log INFO "Checking for captive portal on '$ssid'..."

    if /usr/local/bin/frey-wifi-captive-portal-auto --interface "$INTERFACE_CLIENT" 2>&1 | tee -a "$LOG_FILE" | grep -q "bypassed successfully"; then
        log INFO "✓ Captive portal bypassed automatically"
        return 0
    else
        log WARN "⚠ Automatic captive portal bypass failed"
        # For open networks, apply short blacklist to rotate candidates; record failure
        if [ "${LAST_CONNECTED_OPEN:-false}" = true ]; then
            log INFO "Open network; short blacklist to rotate candidates"
            update_network_history "$ssid" false
            blacklist_network "$ssid" "${OPEN_FAIL_BLACKLIST:-60}" true
            wpa_cli -i "$INTERFACE_CLIENT" disconnect &>/dev/null || true
            CURRENT_SSID=""
        else
            local backoff="${PORTAL_FAIL_BACKOFF:-60}"
            blacklist_network "$ssid" "$backoff"
        fi
        return 1
    fi
}

# ==============================================================================
# Blacklist network temporarily
# ==============================================================================
blacklist_network() {
    local ssid="$1"
    local duration="${2:-300}"  # Default: 5 minutes
    local allow_open="${3:-false}"

    # Do not blacklist known networks to preserve preferred connectivity
    if is_known_ssid "$ssid"; then
        log INFO "Skipping blacklist for known network '$ssid'"
        return
    fi

    # Avoid blacklisting open networks unless explicitly allowed
    if [ "${LAST_CONNECTED_OPEN:-false}" = true ] && [ "$allow_open" != true ]; then
        log INFO "Skipping blacklist for open network '$ssid'"
        return
    fi

    if ! command -v jq &>/dev/null; then
        log WARN "jq not installed - cannot blacklist networks"
        return
    fi

    local blacklist_until
    blacklist_until=$(($(date +%s) + duration))

    log INFO "Blacklisting '$ssid' until $(date -d @"$blacklist_until")"

    # Update blacklist file
    local temp_file
    temp_file=$(mktemp)
    jq --arg ssid "$ssid" --arg until "$blacklist_until" \
        '. + {($ssid): ($until | tonumber)}' \
        "$BLACKLIST_FILE" > "$temp_file" 2>/dev/null || echo "{}" > "$temp_file"
    mv "$temp_file" "$BLACKLIST_FILE"
}

# ==============================================================================
# Update network history
# ==============================================================================
update_network_history() {
    local ssid="$1"
    local success="$2"  # true/false

    if ! command -v jq &>/dev/null; then
        return
    fi

    local temp_file
    temp_file=$(mktemp)

    if [ "$success" = true ]; then
        jq --arg ssid "$ssid" \
            '.[$ssid].successes = ((.[$ssid].successes // 0) + 1) | .[$ssid].attempts = ((.[$ssid].attempts // 0) + 1) | .[$ssid].last_success = now' \
            "$NETWORK_HISTORY_FILE" > "$temp_file" 2>/dev/null || echo "{}" > "$temp_file"
    else
        jq --arg ssid "$ssid" \
            '.[$ssid].failures = ((.[$ssid].failures // 0) + 1) | .[$ssid].attempts = ((.[$ssid].attempts // 0) + 1)' \
            "$NETWORK_HISTORY_FILE" > "$temp_file" 2>/dev/null || echo "{}" > "$temp_file"
    fi

    mv "$temp_file" "$NETWORK_HISTORY_FILE"
}

# ==============================================================================
# Get network password from known networks
# ==============================================================================
get_network_password() {
    local ssid="$1"

    if [ ! -f "$KNOWN_NETWORKS_FILE" ]; then
        echo ""
        return
    fi

    local password
    password=$(grep "^${ssid}|" "$KNOWN_NETWORKS_FILE" 2>/dev/null | cut -d'|' -f2 || echo "")

    echo "$password"
}

# Check if an SSID is configured as known
is_known_ssid() {
    local ssid="$1"

    if [ ! -f "$KNOWN_NETWORKS_FILE" ]; then
        return 1
    fi

    if grep -q "^${ssid}|" "$KNOWN_NETWORKS_FILE" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ==============================================================================
# Main roaming logic
# ==============================================================================
roaming_cycle() {
    log DEBUG "Starting roaming cycle..."

    # Skip scanning if paused by user signal
    if [ "$SCANNING_PAUSED" = true ]; then
        log DEBUG "Scanning paused - sleeping"
        sleep 10  # Short sleep to keep daemon responsive
        return
    fi

    # Skip scanning/roaming while a captive portal login is in progress
    if [ -f "$PORTAL_STATE_FILE" ]; then
        log DEBUG "Captive portal in progress - holding roaming scans"
        sleep 10
        return
    fi

    # If a manual lock is set, honor it (stay on that SSID; try to reconnect if off it)
    if [ -f "$LOCKED_SSID_FILE" ]; then
        local locked_ssid
        locked_ssid=$(cat "$LOCKED_SSID_FILE" 2>/dev/null || true)
        if [ -n "$locked_ssid" ]; then
            if [ "$CURRENT_SSID" != "$locked_ssid" ]; then
                log INFO "🔒 Locked to '$locked_ssid' - attempting to connect and skipping other networks"
                local pw
                pw=$(get_network_password "$locked_ssid")
                connect_to_network "$locked_ssid" "$pw" || true
                sleep "$SCAN_INTERVAL_NO_CONNECTION"
                return
            else
                log INFO "🔒 Locked to '$locked_ssid' - staying connected"
                sleep "$SCAN_INTERVAL_GOOD"
                return
            fi
        fi
    fi

    # Get current status
    get_current_status || true

    # Publish current status
    mqtt_publish "status/current_ssid" "${CURRENT_SSID:-disconnected}"
    mqtt_publish "status/signal_dbm" "$CURRENT_SIGNAL"

    # Verify internet
    verify_internet || true
    mqtt_publish "status/has_internet" "$HAS_INTERNET"

    # Determine scan interval based on current state
    if [ -z "$CURRENT_SSID" ]; then
        # No connection - scan aggressively
        SCAN_INTERVAL=$SCAN_INTERVAL_NO_CONNECTION
        INTERNET_CHECK_FAILURES=0
        LAST_SCAN_ON_KNOWN_NETWORK=0
        mqtt_publish "status/state" "no_connection"
        log INFO "State: NO_CONNECTION - Scan interval: ${SCAN_INTERVAL}s"
    elif [ "$HAS_INTERNET" = false ]; then
        # Connected but no internet - scan moderately
        SCAN_INTERVAL=$SCAN_INTERVAL_NO_INTERNET
        LAST_SCAN_ON_KNOWN_NETWORK=0
        mqtt_publish "status/state" "no_internet"
        log INFO "State: NO_INTERNET (SSID: $CURRENT_SSID) - Scan interval: ${SCAN_INTERVAL}s"

        # Try to handle captive portal
        if handle_captive_portal "$CURRENT_SSID"; then
            verify_internet || true
        fi
    elif [ "$CURRENT_SIGNAL" -lt -75 ]; then
        # Weak signal - scan moderately
        SCAN_INTERVAL=$SCAN_INTERVAL_NO_INTERNET
        LAST_SCAN_ON_KNOWN_NETWORK=0
        mqtt_publish "status/state" "weak_signal"
        log INFO "State: WEAK_SIGNAL (SSID: $CURRENT_SSID, Signal: ${CURRENT_SIGNAL} dBm) - Scan interval: ${SCAN_INTERVAL}s"
    else
        # Good connection - scan very conservatively on known networks
        local current_is_known=false
        if is_known_ssid "$CURRENT_SSID"; then
            current_is_known=true
        fi
        
        if [ "$current_is_known" = true ]; then
            # On a known network with good internet - scan very infrequently
            SCAN_INTERVAL=$SCAN_INTERVAL_GOOD
            LAST_SCAN_ON_KNOWN_NETWORK=$(date +%s)
            log DEBUG "State: CONNECTED_GOOD (Known: YES, SSID: $CURRENT_SSID, Signal: ${CURRENT_SIGNAL} dBm) - Scan interval: ${SCAN_INTERVAL}s"
        else
            # On unknown network with good internet
            SCAN_INTERVAL=$SCAN_INTERVAL_GOOD
            LAST_SCAN_ON_KNOWN_NETWORK=0
            log DEBUG "State: CONNECTED_GOOD (Known: NO, SSID: $CURRENT_SSID, Signal: ${CURRENT_SIGNAL} dBm) - Scan interval: ${SCAN_INTERVAL}s"
        fi
        mqtt_publish "status/state" "connected_good"
    fi

    # If we are on a known network with internet, do nothing (avoid flaps)
    if [ -n "$CURRENT_SSID" ] && [ "$HAS_INTERNET" = true ] && is_known_ssid "$CURRENT_SSID"; then
        log INFO "🔒 Holding connection on known network '$CURRENT_SSID' (internet OK) - skipping scan/switch"
        sleep "$SCAN_INTERVAL_GOOD"
        return
    fi

    # Scan for available networks
    local scan_results
    scan_results=$(scan_networks) || true

    if [ -z "$scan_results" ]; then
        log WARN "Scan returned no results"
        return
    fi

    # Rank networks by score
    local ranked_networks
    ranked_networks=$(rank_networks "$scan_results")

    # Filter: only known networks (no auto-join to unknown/public)
    local filtered_networks
    filtered_networks=$(echo "$ranked_networks" | while IFS='|' read -r score ssid signal security; do
        [ -z "$ssid" ] && continue

        # Skip ignored SSIDs
        for ignore in "${IGNORE_SSIDS[@]}"; do
            if [ "$ssid" = "$ignore" ]; then
                continue 2
            fi
        done

        # Only allow known SSIDs
        if ! is_known_ssid "$ssid"; then
            continue
        fi
        echo "${score}|${ssid}|${signal}|${security}"
    done)

    if [ -z "$filtered_networks" ]; then
        log WARN "No eligible networks after filtering"
        return
    fi

    local candidate_networks="$filtered_networks"
    local network_count
    network_count=$(echo "$candidate_networks" | wc -l)
    log INFO "Evaluating $network_count candidate networks"
    mqtt_publish "status/networks_found" "$network_count"

    # Get best available network
    local best_network
    best_network=$(echo "$candidate_networks" | head -1)

    if [ -z "$best_network" ]; then
        log WARN "No suitable networks found"
        return
    fi

    local best_score best_ssid best_signal best_security
    IFS='|' read -r best_score best_ssid best_signal best_security <<< "$best_network"

    log INFO "Best available: '$best_ssid' (score: $best_score, signal: ${best_signal} dBm)"

    # Decide whether to switch or iterate candidates
    if [ -n "$CURRENT_SSID" ]; then
        # Already connected - check if we should switch
        local current_score
        current_score=$(/usr/local/bin/frey-wifi-network-scorer --ssid "$CURRENT_SSID" --signal "$CURRENT_SIGNAL" 2>/dev/null || echo "0")

        log INFO "Current network: '$CURRENT_SSID' (score: $current_score)"

        # If no internet on current network, treat current score as 0 to encourage switching
        if [ "$HAS_INTERNET" = false ]; then
            current_score=0
        fi

        local current_is_known=false
        if is_known_ssid "$CURRENT_SSID"; then
            current_is_known=true
        fi

        # ===== CRITICAL: NEVER LEAVE A KNOWN NETWORK WITH INTERNET =====
        if [ "$HAS_INTERNET" = true ] && [ "$current_is_known" = true ] && [ "${PREFER_KNOWN_NETWORKS:-true}" = true ]; then
            log INFO "🔒 STAYING on known network '$CURRENT_SSID' (has internet, never switching)"
            return
        fi

        # ===== NEVER SWITCH IF ON GOOD KNOWN NETWORK =====
        if [ "$current_is_known" = true ] && [ "$CURRENT_SIGNAL" -gt -75 ]; then
            # Only scan infrequently on known networks
            local time_since_known_scan=$(($(date +%s) - LAST_SCAN_ON_KNOWN_NETWORK))
            if [ $time_since_known_scan -lt $MIN_KNOWN_NETWORK_SCAN_INTERVAL ]; then
                log DEBUG "On good known network, skipping scan (last scan: ${time_since_known_scan}s ago)"
                return
            fi
        fi

        # Lower the switch threshold when current network lacks internet
        local effective_threshold="$SWITCH_THRESHOLD"
        if [ "$HAS_INTERNET" = false ]; then
            effective_threshold="${SWITCH_THRESHOLD_NO_INTERNET:-0}"
        fi

        local score_diff=$((best_score - current_score))

        # ===== CRITICAL: NEVER DOWNGRADE FROM KNOWN NETWORK TO PUBLIC WIFI =====
        # Check if candidate network is known
        local candidate_is_known=false
        if is_known_ssid "$best_ssid"; then
            candidate_is_known=true
        fi

        # If currently on known network, NEVER switch to unknown/public network
        # This enforces strict priority hierarchy: known networks >> public WiFi
        if [ "$current_is_known" = true ] && [ "$candidate_is_known" = false ]; then
            log INFO "🔒 REFUSING to switch from known network '$CURRENT_SSID' to public WiFi '$best_ssid'"
            log INFO "Known networks always preferred over public WiFi (priority enforcement)"
            return
        fi

        # ===== NEVER SWITCH TO THE SAME NETWORK WE'RE ALREADY ON =====
        if [ "$best_ssid" = "$CURRENT_SSID" ]; then
            log INFO "Already connected to best network '$CURRENT_SSID' - staying put"
            return
        fi

        if [ "$score_diff" -lt "$effective_threshold" ]; then
            log INFO "No switch needed (score difference: $score_diff < threshold: $effective_threshold)"
            return
        fi

        log INFO "Switching networks (score improvement: $score_diff >= threshold: $effective_threshold)"
        mqtt_publish "events" "{\"event\":\"switching\",\"from\":\"$CURRENT_SSID\",\"to\":\"$best_ssid\",\"reason\":\"better_score\"}"

        # Try the top candidate only when switching from an active connection
        local password
        password=$(get_network_password "$best_ssid")

    if connect_to_network "$best_ssid" "$password"; then
        sleep 2
        if verify_internet; then
            log INFO "✅ Successfully connected with internet access: '$best_ssid'"
            update_network_history "$best_ssid" true
            INTERNET_CHECK_FAILURES=0
            mqtt_publish "events" "{\"event\":\"connected_success\",\"ssid\":\"$best_ssid\"}"
        else
            log WARN "⚠ Connected but no internet: '$best_ssid'"
            log WARN "Portal/manual action may be required; skipping auto-bypass"
            update_network_history "$best_ssid" false
        fi
    else
        log ERROR "❌ Failed to connect to: '$best_ssid'"
        update_network_history "$best_ssid" false
        if [ "${LAST_CONNECTED_OPEN:-false}" = true ]; then
            blacklist_network "$best_ssid" "${OPEN_FAIL_BLACKLIST:-60}" true
        else
            blacklist_network "$best_ssid" "${BLACKLIST_DURATION:-300}"
        fi
        mqtt_publish "events" "{\"event\":\"connection_failed\",\"ssid\":\"$best_ssid\"}"
    fi
    else
        log INFO "No current connection - testing candidate networks"
        mqtt_publish "events" "{\"event\":\"connecting\",\"to\":\"candidates\"}"

        local connected=false
        while IFS='|' read -r candidate_score candidate_ssid candidate_signal candidate_security; do
            [ -z "$candidate_ssid" ] && continue

            log INFO "Attempting to connect to: '$candidate_ssid' (score: $candidate_score, signal: ${candidate_signal} dBm)"
            local password
            password=$(get_network_password "$candidate_ssid")

            if connect_to_network "$candidate_ssid" "$password"; then
                sleep 2
                if verify_internet; then
                    log INFO "✅ Successfully connected with internet access: '$candidate_ssid'"
                    update_network_history "$candidate_ssid" true
                    INTERNET_CHECK_FAILURES=0
                    mqtt_publish "events" "{\"event\":\"connected_success\",\"ssid\":\"$candidate_ssid\"}"
                else
                    log WARN "⚠ Connected but no internet: '$candidate_ssid'"
                    log WARN "Portal/manual action may be required; skipping auto-bypass"
                    update_network_history "$candidate_ssid" false
                fi
                connected=true
                break
            else
                log ERROR "❌ Failed to connect to: '$candidate_ssid'"
                update_network_history "$candidate_ssid" false
                if [ "${LAST_CONNECTED_OPEN:-false}" = true ]; then
                    blacklist_network "$candidate_ssid" "${OPEN_FAIL_BLACKLIST:-60}" true
                else
                    blacklist_network "$candidate_ssid" "${BLACKLIST_DURATION:-300}"
                fi
                mqtt_publish "events" "{\"event\":\"connection_failed\",\"ssid\":\"$candidate_ssid\"}"
            fi
        done <<< "$candidate_networks"

        if [ "$connected" = false ]; then
            log WARN "No candidate networks succeeded this cycle"
        fi
    fi
}

# ==============================================================================
# Main daemon loop
# ==============================================================================
main_loop() {
    while true; do
        if [ "$DAEMON_ENABLED" = true ]; then
            roaming_cycle

            # Publish next scan time
            mqtt_publish "status/next_scan" "$(($(date +%s) + SCAN_INTERVAL))"

            log DEBUG "Next scan in ${SCAN_INTERVAL} seconds"
            sleep "$SCAN_INTERVAL"
        else
            log INFO "Daemon disabled - sleeping"
            mqtt_publish "status/state" "disabled"
            sleep 60
        fi
    done
}

# ==============================================================================
# Signal handlers
# ==============================================================================
cleanup() {
    log INFO "Daemon stopping..."
    mqtt_publish "status/state" "stopped"
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ==============================================================================
# Parse arguments and start daemon
# ==============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --foreground|-f)
            FOREGROUND=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Load configuration
load_config

# Initialize daemon
init_daemon

# Start main loop
log INFO "Starting main roaming loop"
main_loop
