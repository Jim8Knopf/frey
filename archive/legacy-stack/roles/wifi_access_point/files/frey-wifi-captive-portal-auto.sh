#!/bin/bash
# ==============================================================================
# FREY WIFI AUTOMATIC CAPTIVE PORTAL AUTHENTICATION
# ==============================================================================
# Automatically detects and attempts to bypass captive portals using common
# patterns without requiring user interaction
#
# USAGE:
#   frey-wifi-captive-portal-auto [--interface wlan0] [--verbose]
#
# EXIT CODES:
#   0  = Portal bypassed successfully
#   1  = No portal detected or bypass failed
#   2  = Portal detected but automatic bypass failed (manual intervention needed)
# ==============================================================================

set -euo pipefail

# Configuration
INTERFACE="${1:-wlan0}"
VERBOSE=false
MAX_ATTEMPTS=5
ATTEMPT_DELAY=2

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
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
            echo "Exit codes: 0=success, 1=no portal, 2=manual needed"
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

info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ==============================================================================
# Detect Captive Portal
# ==============================================================================
detect_portal() {
    log "Detecting captive portal..."

    local portal_url

    # Method 1: Check Firefox captive portal detection
    local response
    response=$(curl -s --interface "$INTERFACE" --max-time 3 http://detectportal.firefox.com/success.txt 2>/dev/null || echo "")

    if [ "$response" = "success" ]; then
        log "No captive portal detected (Firefox test passed)"
        return 1
    fi

    # Method 2: Check Apple captive portal detection
    portal_url=$(curl -sI --interface "$INTERFACE" --max-time 3 http://captive.apple.com/hotspot-detect.html 2>/dev/null | grep -i "^Location:" | head -1 | cut -d' ' -f2 | tr -d '\r')

    if [ -n "$portal_url" ] && [[ "$portal_url" != *"apple.com"* ]]; then
        log "Captive portal detected: $portal_url"
        echo "$portal_url"
        return 0
    fi

    # Method 3: Try to get redirected from any HTTP request
    portal_url=$(curl -sI --interface "$INTERFACE" --max-time 3 -L http://neverssl.com 2>/dev/null | grep -i "^Location:" | tail -1 | cut -d' ' -f2 | tr -d '\r')

    if [ -n "$portal_url" ] && [[ "$portal_url" =~ ^http ]]; then
        log "Captive portal detected (redirect): $portal_url"
        echo "$portal_url"
        return 0
    fi

    log "No captive portal detected"
    return 1
}

# ==============================================================================
# Verify Internet Access
# ==============================================================================
verify_internet() {
    local response
    response=$(curl -s --interface "$INTERFACE" --max-time 3 http://detectportal.firefox.com/success.txt 2>/dev/null || echo "")

    if [ "$response" = "success" ]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Method 1: Simple GET Request (many portals authenticate just by visiting)
# ==============================================================================
method_simple_visit() {
    local portal_url="$1"
    log "Method 1: Simple visit to portal page..."

    curl -s -L --interface "$INTERFACE" --max-time 5 "$portal_url" -o /dev/null 2>&1
    sleep "$ATTEMPT_DELAY"

    if verify_internet; then
        info "✓ Portal bypassed with simple visit"
        return 0
    fi

    log "✗ Simple visit failed"
    return 1
}

# ==============================================================================
# Method 2: Auto-submit common button patterns
# ==============================================================================
method_auto_submit() {
    local portal_url="$1"
    log "Method 2: Parsing and auto-submitting forms..."

    # Download the portal page
    local page
    page=$(curl -s -L --interface "$INTERFACE" --max-time 5 "$portal_url" 2>/dev/null || echo "")

    if [ -z "$page" ]; then
        log "✗ Failed to download portal page"
        return 1
    fi

    # Extract form action URL
    local form_action
    form_action=$(echo "$page" | grep -oP 'action=["'\'']\K[^"'\'']+' | head -1)

    if [ -z "$form_action" ]; then
        log "No form action found"
        return 1
    fi

    # Make absolute URL if relative
    if [[ "$form_action" != http* ]]; then
        local base_url
        base_url=$(echo "$portal_url" | sed -E 's|(https?://[^/]+).*|\1|')
        if [[ "$form_action" == /* ]]; then
            form_action="${base_url}${form_action}"
        else
            form_action="${portal_url%/*}/${form_action}"
        fi
    fi

    log "Form action: $form_action"

    # Try common form data patterns
    local form_data_patterns=(
        "accept=true&agree=1"
        "accept=1&terms=1"
        "agree=true"
        "accept=yes"
        "terms=accepted"
        "submit=Accept"
        "action=accept"
        "continue=true"
    )

    for data in "${form_data_patterns[@]}"; do
        log "Trying form data: $data"
        curl -s -X POST --interface "$INTERFACE" --max-time 5 "$form_action" -d "$data" -o /dev/null 2>&1
        sleep "$ATTEMPT_DELAY"

        if verify_internet; then
            info "✓ Portal bypassed with form submission"
            return 0
        fi
    done

    log "✗ Form submission failed"
    return 1
}

# ==============================================================================
# Method 3: Try common API endpoints
# ==============================================================================
method_api_endpoints() {
    local portal_url="$1"
    log "Method 3: Trying common API endpoints..."

    local base_url
    base_url=$(echo "$portal_url" | sed -E 's|(https?://[^/]+).*|\1|')

    local api_endpoints=(
        "/login?accept=true"
        "/auth/accept"
        "/api/v1/auth"
        "/api/auth"
        "/authenticate"
        "/accept"
        "/continue"
        "/agree"
    )

    for endpoint in "${api_endpoints[@]}"; do
        local url="${base_url}${endpoint}"
        log "Trying: $url"

        # Try GET
        curl -s --interface "$INTERFACE" --max-time 3 "$url" -o /dev/null 2>&1
        sleep 1

        if verify_internet; then
            info "✓ Portal bypassed with API endpoint (GET): $endpoint"
            return 0
        fi

        # Try POST with JSON
        curl -s -X POST --interface "$INTERFACE" --max-time 3 "$url" \
            -H "Content-Type: application/json" \
            -d '{"accept":true,"agree":true}' \
            -o /dev/null 2>&1
        sleep 1

        if verify_internet; then
            info "✓ Portal bypassed with API endpoint (POST): $endpoint"
            return 0
        fi
    done

    log "✗ API endpoint method failed"
    return 1
}

# ==============================================================================
# Method 4: Click first button/link with accept/agree/continue keywords
# ==============================================================================
method_button_click() {
    local portal_url="$1"
    log "Method 4: Finding and clicking buttons/links..."

    local page
    page=$(curl -s -L --interface "$INTERFACE" --max-time 5 "$portal_url" 2>/dev/null || echo "")

    if [ -z "$page" ]; then
        log "✗ Failed to download portal page"
        return 1
    fi

    # Extract links that contain accept/agree/continue keywords (case-insensitive)
    local button_urls
    button_urls=$(echo "$page" | grep -oiP 'href=["'\'']\K[^"'\'']*(?=[^>]*(?:accept|agree|continue|proceed))' | head -5)

    if [ -z "$button_urls" ]; then
        log "No button URLs found"
        return 1
    fi

    local base_url
    base_url=$(echo "$portal_url" | sed -E 's|(https?://[^/]+).*|\1|')

    while IFS= read -r url; do
        # Make absolute URL
        if [[ "$url" != http* ]]; then
            if [[ "$url" == /* ]]; then
                url="${base_url}${url}"
            else
                url="${portal_url%/*}/${url}"
            fi
        fi

        log "Clicking: $url"
        curl -s -L --interface "$INTERFACE" --max-time 5 "$url" -o /dev/null 2>&1
        sleep "$ATTEMPT_DELAY"

        if verify_internet; then
            info "✓ Portal bypassed by clicking button"
            return 0
        fi
    done <<< "$button_urls"

    log "✗ Button click method failed"
    return 1
}

# ==============================================================================
# Method 5: Try to extract and submit any form automatically
# ==============================================================================
method_auto_form() {
    local portal_url="$1"
    log "Method 5: Auto-submitting any detected forms..."

    local page
    page=$(curl -s -L --interface "$INTERFACE" --max-time 5 "$portal_url" 2>/dev/null || echo "")

    if [ -z "$page" ]; then
        log "✗ Failed to download portal page"
        return 1
    fi

    # Look for forms and try to submit them
    local form_count
    form_count=$(echo "$page" | grep -c "<form" || echo "0")

    if [ "$form_count" -eq 0 ]; then
        log "No forms found"
        return 1
    fi

    log "Found $form_count form(s)"

    # Extract first form action
    local form_action
    form_action=$(echo "$page" | grep -oP '<form[^>]*action=["'\'']\K[^"'\'']+' | head -1)

    if [ -n "$form_action" ]; then
        # Make absolute URL
        if [[ "$form_action" != http* ]]; then
            local base_url
            base_url=$(echo "$portal_url" | sed -E 's|(https?://[^/]+).*|\1|')
            if [[ "$form_action" == /* ]]; then
                form_action="${base_url}${form_action}"
            else
                form_action="${portal_url%/*}/${form_action}"
            fi
        fi

        log "Submitting form to: $form_action"
        curl -s -X POST --interface "$INTERFACE" --max-time 5 "$form_action" -o /dev/null 2>&1
        sleep "$ATTEMPT_DELAY"

        if verify_internet; then
            info "✓ Portal bypassed by auto-form submission"
            return 0
        fi
    fi

    log "✗ Auto-form submission failed"
    return 1
}

# ==============================================================================
# Main Authentication Logic
# ==============================================================================
main() {
    info "🔍 Starting automatic captive portal authentication..."

    # First, detect if there's actually a portal
    local portal_url
    portal_url=$(detect_portal)
    local detect_result=$?

    if [ $detect_result -ne 0 ]; then
        log "No captive portal detected"
        return 1
    fi

    info "📡 Portal detected: $portal_url"
    info "⚡ Attempting automatic bypass..."

    # Try each method in order
    local methods=(
        "method_simple_visit"
        "method_auto_submit"
        "method_button_click"
        "method_api_endpoints"
        "method_auto_form"
    )

    for method in "${methods[@]}"; do
        if $method "$portal_url"; then
            info "✅ Captive portal bypassed successfully!"
            info "🌐 Internet access confirmed"
            return 0
        fi
    done

    warn "❌ All automatic bypass methods failed"
    warn "📝 Manual authentication required"
    warn "Portal URL: $portal_url"

    return 2  # Manual intervention needed
}

# Run main function
main
exit $?
