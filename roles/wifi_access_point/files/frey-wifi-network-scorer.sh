#!/bin/bash
# ==============================================================================
# FREY WIFI NETWORK SCORER
# ==============================================================================
# Scores WiFi networks based on multiple criteria to help roaming daemon
# choose the best network to connect to
#
# USAGE:
#   frey-wifi-network-scorer --ssid "Network Name" --signal -65 [options]
#
# EXIT CODES:
#   Outputs score (0-100) to stdout
# ==============================================================================

set -euo pipefail

# Configuration files
CONFIG_FILE="/etc/frey/wifi-roaming.conf"
KNOWN_NETWORKS_FILE="/etc/frey/known-networks.conf"
NETWORK_HISTORY_FILE="/var/lib/frey/wifi-network-history.json"
BLACKLIST_FILE="/var/lib/frey/wifi-blacklist.json"

# Default values
SSID=""
SIGNAL_DBM=0
SECURITY=""
IS_KNOWN=false
VERBOSE=false

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssid|-s)
            SSID="$2"
            shift 2
            ;;
        --signal|-g)
            SIGNAL_DBM="$2"
            shift 2
            ;;
        --security)
            SECURITY="$2"
            shift 2
            ;;
        --known)
            IS_KNOWN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --ssid 'Network' --signal -65 [--security WPA2] [--known]"
            echo "Outputs network score (0-100) based on multiple criteria"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

# ==============================================================================
# Load configuration
# ==============================================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Source config file safely
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
}

# ==============================================================================
# Check if network is in known networks
# ==============================================================================
is_known_network() {
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
# Get network priority from known networks
# ==============================================================================
get_network_priority() {
    local ssid="$1"

    if [ ! -f "$KNOWN_NETWORKS_FILE" ]; then
        echo "0"
        return
    fi

    local priority
    priority=$(grep "^${ssid}|" "$KNOWN_NETWORKS_FILE" 2>/dev/null | cut -d'|' -f3 || echo "0")

    echo "${priority:-0}"
}

# ==============================================================================
# Check if network is blacklisted
# ==============================================================================
is_blacklisted() {
    local ssid="$1"

    if [ ! -f "$BLACKLIST_FILE" ]; then
        return 1
    fi

    # Check if blacklist entry exists and hasn't expired
    if command -v jq &>/dev/null && [ -f "$BLACKLIST_FILE" ]; then
        local blacklist_until
        blacklist_until=$(jq -r --arg ssid "$ssid" '.[$ssid] // empty' "$BLACKLIST_FILE" 2>/dev/null || echo "")

        if [ -n "$blacklist_until" ]; then
            local current_time
            current_time=$(date +%s)

            if [ "$blacklist_until" -gt "$current_time" ]; then
                log "Network is blacklisted until: $(date -d @"$blacklist_until")"
                return 0
            fi
        fi
    fi

    return 1
}

# ==============================================================================
# Get network failure count from history
# ==============================================================================
get_failure_count() {
    local ssid="$1"

    if [ ! -f "$NETWORK_HISTORY_FILE" ]; then
        echo "0"
        return
    fi

    if command -v jq &>/dev/null; then
        local failures
        failures=$(jq -r --arg ssid "$ssid" '.[$ssid].failures // 0' "$NETWORK_HISTORY_FILE" 2>/dev/null || echo "0")
        echo "$failures"
    else
        echo "0"
    fi
}

# ==============================================================================
# Get network success rate from history
# ==============================================================================
get_success_rate() {
    local ssid="$1"

    if [ ! -f "$NETWORK_HISTORY_FILE" ]; then
        echo "0"
        return
    fi

    if command -v jq &>/dev/null; then
        local successes
        local attempts
        successes=$(jq -r --arg ssid "$ssid" '.[$ssid].successes // 0' "$NETWORK_HISTORY_FILE" 2>/dev/null || echo "0")
        attempts=$(jq -r --arg ssid "$ssid" '.[$ssid].attempts // 0' "$NETWORK_HISTORY_FILE" 2>/dev/null || echo "0")

        if [ "$attempts" -gt 0 ]; then
            echo "$((successes * 100 / attempts))"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# ==============================================================================
# Calculate signal score (0-40 points)
# ==============================================================================
score_signal() {
    local signal=$1
    local score=0

    log "Scoring signal: ${signal} dBm"

    if [ "$signal" -ge -50 ]; then
        score=40
        log "  Excellent signal (>= -50 dBm): +40"
    elif [ "$signal" -ge -60 ]; then
        score=30
        log "  Good signal (-50 to -60 dBm): +30"
    elif [ "$signal" -ge -70 ]; then
        score=20
        log "  Fair signal (-60 to -70 dBm): +20"
    elif [ "$signal" -ge -80 ]; then
        score=10
        log "  Weak signal (-70 to -80 dBm): +10"
    else
        score=5
        log "  Very weak signal (< -80 dBm): +5"
    fi

    echo "$score"
}

# ==============================================================================
# Calculate known network bonus (0-30 points)
# ==============================================================================
score_known_network() {
    local ssid="$1"
    local score=0

    if is_known_network "$ssid"; then
        local priority
        priority=$(get_network_priority "$ssid")

        if [ "$priority" -gt 0 ]; then
            # High priority known networks get full bonus
            score=$((priority * 30 / 100))
            log "Known network with priority ${priority}: +${score}"
        else
            # Default known network bonus
            score=20
            log "Known network (default): +20"
        fi
    else
        log "Unknown network: +0"
    fi

    echo "$score"
}

# ==============================================================================
# Calculate history bonus/penalty (0-20 points)
# ==============================================================================
score_history() {
    local ssid="$1"
    local score=0

    local success_rate
    success_rate=$(get_success_rate "$ssid")

    log "Network success rate: ${success_rate}%"

    if [ "$success_rate" -ge 80 ]; then
        score=20
        log "  High success rate (>= 80%): +20"
    elif [ "$success_rate" -ge 60 ]; then
        score=15
        log "  Good success rate (>= 60%): +15"
    elif [ "$success_rate" -ge 40 ]; then
        score=10
        log "  Moderate success rate (>= 40%): +10"
    elif [ "$success_rate" -gt 0 ]; then
        score=5
        log "  Low success rate (< 40%): +5"
    else
        log "  No history: +0"
    fi

    echo "$score"
}

# ==============================================================================
# Calculate security penalty (0 to -10 points)
# ==============================================================================
score_security() {
    local security="$1"
    local penalty=0

    if [ -z "$security" ] || [[ "$security" =~ ^(Open|OPEN)$ ]]; then
        penalty=-5
        log "Open network (no encryption): -5"
    elif [[ "$security" =~ WEP ]]; then
        penalty=-3
        log "WEP security (weak): -3"
    else
        log "Secure network (WPA/WPA2/WPA3): +0"
    fi

    echo "$penalty"
}

# ==============================================================================
# Calculate failure penalty (-10 points per failure)
# ==============================================================================
score_failures() {
    local ssid="$1"
    local failures
    failures=$(get_failure_count "$ssid")

    local penalty=$((failures * -10))

    # Cap penalty for open networks to avoid permanently burying them
    if [ -n "${SECURITY:-}" ] && echo "$SECURITY" | grep -qi "open"; then
        local min_penalty=-40
        if [ "$penalty" -lt "$min_penalty" ]; then
            penalty=$min_penalty
        fi
    fi

    # Reduce penalty for known networks to avoid starving them
    if is_known_network "$ssid"; then
        local min_penalty=-30
        if [ "$penalty" -lt "$min_penalty" ]; then
            penalty=$min_penalty
        fi
    fi

    if [ "$failures" -gt 0 ]; then
        log "Recent failures: ${failures}, penalty: ${penalty}"
    fi

    echo "$penalty"
}

# ==============================================================================
# Check blacklist patterns
# ==============================================================================
matches_blacklist_pattern() {
    local ssid="$1"

    local patterns=()

    # Common patterns to avoid (prefer config if available)
    if declare -p BLACKLIST_PATTERNS >/dev/null 2>&1; then
        eval "patterns=(\"\${BLACKLIST_PATTERNS[@]}\")"
    else
        patterns=(
            ".*-printer.*"
            ".*-iot.*"
            ".*-setup.*"
            "HP-.*"
            "Canon_.*"
            "Brother_.*"
            "DIRECT-.*"
            ".*_nomap"
            ".*\\[hidden\\].*"
            "^FreyHub$"
        )
    fi

    for pattern in "${patterns[@]}"; do
        if echo "$ssid" | grep -qiE "$pattern"; then
            log "Matches blacklist pattern: $pattern"
            return 0
        fi
    done

    return 1
}

# ==============================================================================
# Main scoring function
# ==============================================================================
main() {
    if [ -z "$SSID" ]; then
        echo "Error: SSID required" >&2
        exit 1
    fi

    log "================================"
    log "Scoring network: $SSID"
    log "Signal: ${SIGNAL_DBM} dBm"
    log "Security: ${SECURITY:-Unknown}"
    log "================================"

    # Load configuration
    load_config

    # Check if blacklisted (return score of 0)
    if is_blacklisted "$SSID"; then
        log "❌ Network is blacklisted"
        echo "0"
        exit 0
    fi

    # Check blacklist patterns
    if matches_blacklist_pattern "$SSID"; then
        log "❌ Network matches blacklist pattern"
        echo "0"
        exit 0
    fi

    # If a whitelist is defined, require a match
    if declare -p WHITELIST_PATTERNS >/dev/null 2>&1; then
        eval "local whitelist=(\"\${WHITELIST_PATTERNS[@]}\")"
        if [ "${#whitelist[@]}" -gt 0 ]; then
            local matched=false
            for pattern in "${whitelist[@]}"; do
                if echo "$SSID" | grep -qiE "$pattern"; then
                    matched=true
                    break
                fi
            done

            if [ "$matched" = false ]; then
                log "❌ Network does not match whitelist"
                echo "0"
                exit 0
            fi
        fi
    fi

    # Calculate individual scores
    local signal_score
    local known_score
    local history_score
    local security_score
    local failure_penalty

    signal_score=$(score_signal "$SIGNAL_DBM")
    known_score=$(score_known_network "$SSID")
    history_score=$(score_history "$SSID")
    security_score=$(score_security "$SECURITY")
    failure_penalty=$(score_failures "$SSID")

    # Calculate total score
    local total_score=$((signal_score + known_score + history_score + security_score + failure_penalty))

    # Allow negative scores to penalize repeated failures and deprioritize bad opens
    if [ "$total_score" -lt -100 ]; then
        total_score=-100
    elif [ "$total_score" -gt 100 ]; then
        total_score=100
    fi

    # Ensure known networks keep a minimal score floor
    if is_known_network "$SSID" && [ "$total_score" -lt 10 ]; then
        total_score=10
    fi

    # Ensure open networks have a small floor so they remain selectable
    if [ -n "${SECURITY:-}" ] && echo "$SECURITY" | grep -qi "open"; then
        if [ "$total_score" -lt 5 ]; then
            total_score=5
        fi
    fi

    log "--------------------------------"
    log "Signal strength:  ${signal_score}"
    log "Known network:    ${known_score}"
    log "History:          ${history_score}"
    log "Security:         ${security_score}"
    log "Failure penalty:  ${failure_penalty}"
    log "--------------------------------"
    log "Total score:      ${total_score}"
    log "================================"

    # Output score
    echo "$total_score"
}

# Run main function
main
exit 0
