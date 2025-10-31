#!/bin/bash
# ==============================================================================
# FREY WIFI INTERNET VERIFICATION
# ==============================================================================
# Fast, multi-method internet connectivity verification
# Used by roaming daemon to filter out non-internet networks
#
# USAGE:
#   frey-wifi-internet-verify [--interface wlan0] [--verbose]
#
# EXIT CODES:
#   0  = Internet access confirmed
#   1  = No internet access
#   2  = Captive portal detected
# ==============================================================================

set -euo pipefail

# Configuration
INTERFACE="${1:-wlan0}"
VERBOSE=false
TIMEOUT_DNS=2
TIMEOUT_HTTP=3
TIMEOUT_HTTPS=5

# Test URLs
TEST_URL_HTTP="http://detectportal.firefox.com/success.txt"
TEST_URL_HTTP_ALT="http://captive.apple.com/hotspot-detect.html"
TEST_URL_HTTPS="https://www.google.com"
DNS_SERVER="8.8.8.8"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interface|-i)
            INTERFACE="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--interface wlan0] [--verbose]"
            echo "Exit codes: 0=internet, 1=no internet, 2=captive portal"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${GREEN}[INFO]${NC} $1" >&2
    fi
}

warn() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

error() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

# ==============================================================================
# Test 1: DNS Resolution
# ==============================================================================
test_dns() {
    log "Testing DNS resolution..."

    if timeout "$TIMEOUT_DNS" nslookup google.com "$DNS_SERVER" &>/dev/null; then
        log "✓ DNS resolution working"
        return 0
    else
        error "✗ DNS resolution failed"
        return 1
    fi
}

# ==============================================================================
# Test 2: HTTP Connectivity (Captive Portal Detection)
# ==============================================================================
test_http() {
    log "Testing HTTP connectivity..."

    # Try primary test URL
    local response
    response=$(timeout "$TIMEOUT_HTTP" curl -s --interface "$INTERFACE" --max-time "$TIMEOUT_HTTP" "$TEST_URL_HTTP" 2>/dev/null || echo "")

    if [ "$response" = "success" ]; then
        log "✓ HTTP connectivity confirmed (no captive portal)"
        return 0
    fi

    # Check if we got redirected (captive portal indicator)
    local redirect_url
    redirect_url=$(timeout "$TIMEOUT_HTTP" curl -sI --interface "$INTERFACE" --max-time "$TIMEOUT_HTTP" "$TEST_URL_HTTP_ALT" 2>/dev/null | grep -i "^Location:" | head -1 | cut -d' ' -f2 | tr -d '\r')

    if [ -n "$redirect_url" ] && [[ "$redirect_url" != *"apple.com"* ]]; then
        warn "⚠ HTTP redirect detected (captive portal): $redirect_url"
        echo "$redirect_url"  # Output portal URL
        return 2  # Captive portal
    fi

    # Try alternative test
    response=$(timeout "$TIMEOUT_HTTP" curl -s --interface "$INTERFACE" --max-time "$TIMEOUT_HTTP" "$TEST_URL_HTTP_ALT" 2>/dev/null || echo "")

    if [[ "$response" == *"Success"* ]]; then
        log "✓ HTTP connectivity confirmed (alternative test)"
        return 0
    fi

    error "✗ HTTP connectivity failed"
    return 1
}

# ==============================================================================
# Test 3: HTTPS Connectivity
# ==============================================================================
test_https() {
    log "Testing HTTPS connectivity..."

    if timeout "$TIMEOUT_HTTPS" curl -s --interface "$INTERFACE" --max-time "$TIMEOUT_HTTPS" "$TEST_URL_HTTPS" -o /dev/null 2>&1; then
        log "✓ HTTPS connectivity confirmed"
        return 0
    else
        warn "⚠ HTTPS connectivity failed (common with captive portals)"
        return 1
    fi
}

# ==============================================================================
# Test 4: Ping Test (Basic IP Connectivity)
# ==============================================================================
test_ping() {
    log "Testing basic IP connectivity..."

    if timeout "$TIMEOUT_DNS" ping -I "$INTERFACE" -c 1 -W "$TIMEOUT_DNS" "$DNS_SERVER" &>/dev/null; then
        log "✓ IP connectivity confirmed"
        return 0
    else
        error "✗ IP connectivity failed"
        return 1
    fi
}

# ==============================================================================
# Main Verification Logic
# ==============================================================================
main() {
    log "Starting internet verification on interface: $INTERFACE"

    # Quick check: is interface up and has IP?
    if ! ip addr show "$INTERFACE" 2>/dev/null | grep -q "inet "; then
        error "Interface $INTERFACE has no IP address"
        return 1
    fi

    local ip_addr
    ip_addr=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
    log "Interface IP: $ip_addr"

    # Test 1: Ping (fastest, basic connectivity)
    if ! test_ping; then
        error "No basic IP connectivity"
        return 1
    fi

    # Test 2: DNS
    if ! test_dns; then
        error "DNS not working - likely no internet"
        return 1
    fi

    # Test 3: HTTP (captive portal detection)
    local http_result
    local portal_url
    portal_url=$(test_http)
    http_result=$?

    if [ $http_result -eq 0 ]; then
        # HTTP works, verify HTTPS for full internet
        if test_https; then
            log "✅ Full internet access confirmed"
            return 0
        else
            warn "HTTP works but HTTPS blocked (unusual)"
            return 0  # Consider this as internet (some networks block HTTPS)
        fi
    elif [ $http_result -eq 2 ]; then
        # Captive portal detected
        log "🔐 Captive portal detected"
        if [ -n "$portal_url" ]; then
            log "Portal URL: $portal_url"
            echo "$portal_url"
        fi
        return 2
    else
        # HTTP failed completely
        error "❌ No internet access"
        return 1
    fi
}

# Run main function
main
exit $?
