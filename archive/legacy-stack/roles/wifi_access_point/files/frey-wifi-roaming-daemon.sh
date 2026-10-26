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

# Runtime state
CURRENT_SSID=""
CURRENT_SIGNAL=0
HAS_INTERNET=false
SCAN_INTERVAL=$SCAN_INTERVAL_DEFAULT
DAEMON_ENABLED=true
VERBOSE=false
FOREGROUND=false

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
        return 0
    else
        HAS_INTERNET=false
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

    # Wait for connection
    local attempts=0
    while [ $attempts -lt 10 ]; do
        sleep 1
        if wpa_cli -i "$INTERFACE_CLIENT" status | grep -q "wpa_state=COMPLETED"; then
            log INFO "✓ Connected to WiFi: '$ssid'"

            # Request IP address
            dhcpcd "$INTERFACE_CLIENT" &>/dev/null || true
            sleep 2

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
        # Blacklist this network temporarily
        blacklist_network "$ssid" 300  # 5 minutes
        return 1
    fi
}

# ==============================================================================
# Blacklist network temporarily
# ==============================================================================
blacklist_network() {
    local ssid="$1"
    local duration="${2:-300}"  # Default: 5 minutes

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

# ==============================================================================
# Main roaming logic
# ==============================================================================
roaming_cycle() {
    log DEBUG "Starting roaming cycle..."

    # Get current status
    get_current_status

    # Publish current status
    mqtt_publish "status/current_ssid" "${CURRENT_SSID:-disconnected}"
    mqtt_publish "status/signal_dbm" "$CURRENT_SIGNAL"

    # Verify internet
    verify_internet
    mqtt_publish "status/has_internet" "$HAS_INTERNET"

    # Determine scan interval based on current state
    if [ -z "$CURRENT_SSID" ]; then
        # No connection - scan aggressively
        SCAN_INTERVAL=$SCAN_INTERVAL_NO_CONNECTION
        mqtt_publish "status/state" "no_connection"
        log INFO "State: NO_CONNECTION - Scan interval: ${SCAN_INTERVAL}s"
    elif [ "$HAS_INTERNET" = false ]; then
        # Connected but no internet - scan moderately
        SCAN_INTERVAL=$SCAN_INTERVAL_NO_INTERNET
        mqtt_publish "status/state" "no_internet"
        log INFO "State: NO_INTERNET (SSID: $CURRENT_SSID) - Scan interval: ${SCAN_INTERVAL}s"

        # Try to handle captive portal
        if handle_captive_portal "$CURRENT_SSID"; then
            verify_internet
        fi
    elif [ "$CURRENT_SIGNAL" -lt -75 ]; then
        # Weak signal - scan moderately
        SCAN_INTERVAL=$SCAN_INTERVAL_NO_INTERNET
        mqtt_publish "status/state" "weak_signal"
        log INFO "State: WEAK_SIGNAL (SSID: $CURRENT_SSID, Signal: ${CURRENT_SIGNAL} dBm) - Scan interval: ${SCAN_INTERVAL}s"
    else
        # Good connection - scan conservatively
        SCAN_INTERVAL=$SCAN_INTERVAL_GOOD
        mqtt_publish "status/state" "connected_good"
        log DEBUG "State: CONNECTED_GOOD (SSID: $CURRENT_SSID, Signal: ${CURRENT_SIGNAL} dBm) - Scan interval: ${SCAN_INTERVAL}s"
    fi

    # Scan for available networks
    local scan_results
    scan_results=$(scan_networks)

    if [ -z "$scan_results" ]; then
        log WARN "Scan returned no results"
        return
    fi

    # Rank networks by score
    local ranked_networks
    ranked_networks=$(rank_networks "$scan_results")

    local network_count
    network_count=$(echo "$ranked_networks" | wc -l)
    log INFO "Found $network_count scorable networks"
    mqtt_publish "status/networks_found" "$network_count"

    # Get best available network
    local best_network
    best_network=$(echo "$ranked_networks" | head -1)

    if [ -z "$best_network" ]; then
        log WARN "No suitable networks found"
        return
    fi

    local best_score best_ssid best_signal best_security
    IFS='|' read -r best_score best_ssid best_signal best_security <<< "$best_network"

    log INFO "Best available: '$best_ssid' (score: $best_score, signal: ${best_signal} dBm)"

    # Decide whether to switch
    if [ -n "$CURRENT_SSID" ]; then
        # Already connected - check if we should switch
        local current_score
        current_score=$(/usr/local/bin/frey-wifi-network-scorer --ssid "$CURRENT_SSID" --signal "$CURRENT_SIGNAL" 2>/dev/null || echo "0")

        log INFO "Current network: '$CURRENT_SSID' (score: $current_score)"

        local score_diff=$((best_score - current_score))

        if [ "$score_diff" -lt "$SWITCH_THRESHOLD" ]; then
            log INFO "No switch needed (score difference: $score_diff < threshold: $SWITCH_THRESHOLD)"
            return
        fi

        log INFO "Switching networks (score improvement: $score_diff >= threshold: $SWITCH_THRESHOLD)"
        mqtt_publish "events" "{\"event\":\"switching\",\"from\":\"$CURRENT_SSID\",\"to\":\"$best_ssid\",\"reason\":\"better_score\"}"
    else
        log INFO "No current connection - connecting to best network"
        mqtt_publish "events" "{\"event\":\"connecting\",\"to\":\"$best_ssid\"}"
    fi

    # Get password for known networks
    local password
    password=$(get_network_password "$best_ssid")

    # Attempt connection
    if connect_to_network "$best_ssid" "$password"; then
        # Verify internet
        sleep 2
        if verify_internet; then
            log INFO "✅ Successfully connected with internet access: '$best_ssid'"
            update_network_history "$best_ssid" true
            mqtt_publish "events" "{\"event\":\"connected_success\",\"ssid\":\"$best_ssid\"}"
        else
            log WARN "⚠ Connected but no internet: '$best_ssid'"
            # Try captive portal
            if handle_captive_portal "$best_ssid"; then
                update_network_history "$best_ssid" true
                mqtt_publish "events" "{\"event\":\"portal_bypassed\",\"ssid\":\"$best_ssid\"}"
            else
                update_network_history "$best_ssid" false
            fi
        fi
    else
        log ERROR "❌ Failed to connect to: '$best_ssid'"
        update_network_history "$best_ssid" false
        blacklist_network "$best_ssid" 300
        mqtt_publish "events" "{\"event\":\"connection_failed\",\"ssid\":\"$best_ssid\"}"
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
