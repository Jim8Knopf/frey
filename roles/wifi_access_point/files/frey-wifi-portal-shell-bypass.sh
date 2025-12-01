#!/bin/bash

# ==============================================================================
# Frey WiFi Portal Shell Bypass
#
# A lightweight shell-based captive portal bypass script that attempts to
# automatically accept portal terms using curl and HTML parsing.
#
# This script tries multiple strategies in order:
# 1. Simple URL attempts (common acceptance endpoints)
# 2. Form discovery and submission (parse HTML and submit forms)
# 3. Known vendor patterns (Aruba, Cisco, UniFi, etc.)
#
# Dependencies: curl, grep, sed
# Optional: xmlstarlet or pup for better HTML parsing
#
# Usage: frey-wifi-portal-shell-bypass.sh <portal_url>
# ==============================================================================

set -euo pipefail

# --- Configuration ---
PORTAL_URL="${1:-}"
LOG_PREFIX="[ShellBypass]"
TIMEOUT=5  # Timeout per curl request in seconds
MAX_REDIRECTS=5
USER_AGENT="Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Common portal acceptance paths to try
COMMON_PATHS=(
    "/success"
    "/accept"
    "/agree"
    "/connect"
    "/login"
    "/continue"
    "/?accept=true"
    "/?login=true"
    "/?agree=true"
    "/guest/accept"
    "/auth/accept"
)

# Temporary files
TEMP_DIR=$(mktemp -d)
PORTAL_HTML="${TEMP_DIR}/portal.html"
COOKIES_FILE="${TEMP_DIR}/cookies.txt"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# --- Logging Functions ---

log() {
    echo "${LOG_PREFIX} $1" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "${LOG_PREFIX} [DEBUG] $1" >&2
    fi
}

# --- Connectivity Functions ---

check_internet() {
    log_debug "Checking internet connectivity..."

    # Test 1: ICMP ping to Cloudflare DNS (most reliable)
    # Captive portals cannot fake ICMP responses - they either allow or block packets
    if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
        log "Internet connectivity verified (ICMP to 1.1.1.1)"
        return 0
    fi

    # Test 2: ICMP ping to Google DNS (fallback)
    if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log "Internet connectivity verified (ICMP to 8.8.8.8)"
        return 0
    fi

    # Test 3: HTTP with strict validation (only if ICMP blocked by network policy)
    # Use Google's generate_204 endpoint which ONLY returns 204 when NOT behind portal
    # Portals redirect this to their own page (returning 200/302, not 204)
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "http://clients3.google.com/generate_204" 2>/dev/null || echo "000")

    if [ "${http_code}" = "204" ]; then
        log "Internet connectivity verified (HTTP 204)"
        return 0
    fi

    log_debug "No internet connectivity detected"
    return 1
}

# --- URL Manipulation Functions ---

extract_base_url() {
    # Extract protocol, domain, and port from URL
    local url="$1"
    echo "${url}" | sed -E 's|(https?://[^/]+).*|\1|'
}

make_absolute_url() {
    # Convert relative URL to absolute using base URL
    local base_url="$1"
    local rel_url="$2"

    if [[ "${rel_url}" =~ ^https?:// ]]; then
        # Already absolute
        echo "${rel_url}"
    elif [[ "${rel_url}" =~ ^\/ ]]; then
        # Root-relative
        echo "${base_url}${rel_url}"
    else
        # Relative to current path
        local base_path
        base_path=$(dirname "${base_url}")
        echo "${base_path}/${rel_url}"
    fi
}

# --- Strategy 1: Simple URL Attempts ---

try_simple_urls() {
    log "Strategy 1: Trying common acceptance URLs..."

    local base_url
    base_url=$(extract_base_url "${PORTAL_URL}")

    for path in "${COMMON_PATHS[@]}"; do
        local test_url="${base_url}${path}"
        log_debug "Trying: ${test_url}"

        # Make GET request and follow redirects
        if curl -s -L \
            --max-time "${TIMEOUT}" \
            --max-redirs "${MAX_REDIRECTS}" \
            --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" \
            --cookie-jar "${COOKIES_FILE}" \
            --output /dev/null \
            "${test_url}" 2>/dev/null; then

            # Check if we now have internet
            sleep 2  # Give portal time to process
            if check_internet; then
                log "SUCCESS: Portal accepted via ${path}"
                return 0
            fi
        fi
    done

    log "Strategy 1 failed: No common URL worked"
    return 1
}

# --- Strategy 2: Form Discovery & Submission ---

parse_form_data() {
    # Parse HTML file and extract form action, method, and input fields
    local html_file="$1"

    # Try to find first form
    local form_section
    form_section=$(sed -n '/<form/,/<\/form>/p' "${html_file}" | head -n 50)

    if [ -z "${form_section}" ]; then
        log_debug "No form found in HTML"
        return 1
    fi

    # Extract form action
    local form_action
    form_action=$(echo "${form_section}" | grep -oP '(?<=action=")[^"]*' | head -n 1 || echo "")
    if [ -z "${form_action}" ]; then
        # Try single quotes
        form_action=$(echo "${form_section}" | grep -oP "(?<=action=')[^']*" | head -n 1 || echo "")
    fi
    if [ -z "${form_action}" ]; then
        # Form might submit to same URL
        form_action="${PORTAL_URL}"
    fi

    # Extract form method
    local form_method
    form_method=$(echo "${form_section}" | grep -oP '(?<=method=")[^"]*' | head -n 1 | tr '[:upper:]' '[:lower:]' || echo "post")

    # Extract input fields (name and value)
    local form_data=""
    while IFS= read -r line; do
        local input_name
        local input_value

        # Get input name
        input_name=$(echo "${line}" | grep -oP '(?<=name=")[^"]*' || echo "")
        if [ -z "${input_name}" ]; then
            input_name=$(echo "${line}" | grep -oP "(?<=name=')[^']*" || echo "")
        fi

        # Get input value
        input_value=$(echo "${line}" | grep -oP '(?<=value=")[^"]*' || echo "")
        if [ -z "${input_value}" ]; then
            input_value=$(echo "${line}" | grep -oP "(?<=value=')[^']*" || echo "")
        fi

        # Handle checkboxes - set common acceptance values
        local input_type
        input_type=$(echo "${line}" | grep -oP '(?<=type=")[^"]*' || echo "text")
        if [ "${input_type}" = "checkbox" ]; then
            if [ -z "${input_value}" ]; then
                input_value="on"
            fi
            # Check if this looks like an acceptance checkbox
            if echo "${line}" | grep -iE '(accept|agree|terms|policy|conditions)'; then
                log_debug "Found acceptance checkbox: ${input_name}"
            fi
        fi

        # Build form data string
        if [ -n "${input_name}" ]; then
            if [ -n "${form_data}" ]; then
                form_data="${form_data}&"
            fi
            form_data="${form_data}${input_name}=${input_value}"
        fi
    done < <(echo "${form_section}" | grep -E '<input[^>]*>')

    # Check for buttons with names (some forms use button clicks)
    while IFS= read -r line; do
        local button_name
        button_name=$(echo "${line}" | grep -oP '(?<=name=")[^"]*' || echo "")
        if [ -n "${button_name}" ]; then
            local button_value
            button_value=$(echo "${line}" | grep -oP '(?<=value=")[^"]*' || echo "submit")
            if [ -n "${form_data}" ]; then
                form_data="${form_data}&"
            fi
            form_data="${form_data}${button_name}=${button_value}"
            log_debug "Found submit button: ${button_name}=${button_value}"
        fi
    done < <(echo "${form_section}" | grep -E '<button[^>]*>' || true)

    # Output results
    echo "ACTION:${form_action}"
    echo "METHOD:${form_method}"
    echo "DATA:${form_data}"

    return 0
}

try_form_submission() {
    log "Strategy 2: Attempting form discovery and submission..."

    # Download portal page
    log_debug "Downloading portal page: ${PORTAL_URL}"
    if ! curl -s -L \
        --max-time 10 \
        --user-agent "${USER_AGENT}" \
        --cookie "${COOKIES_FILE}" \
        --cookie-jar "${COOKIES_FILE}" \
        --output "${PORTAL_HTML}" \
        "${PORTAL_URL}" 2>/dev/null; then
        log "Failed to download portal page"
        return 1
    fi

    # Parse form data
    local form_info
    if ! form_info=$(parse_form_data "${PORTAL_HTML}"); then
        log "No form found in portal page"
        return 1
    fi

    # Extract parsed data
    local form_action form_method form_data
    form_action=$(echo "${form_info}" | grep "^ACTION:" | cut -d: -f2-)
    form_method=$(echo "${form_info}" | grep "^METHOD:" | cut -d: -f2-)
    form_data=$(echo "${form_info}" | grep "^DATA:" | cut -d: -f2-)

    if [ -z "${form_action}" ] || [ -z "${form_data}" ]; then
        log "Could not extract form information"
        return 1
    fi

    # Make action URL absolute
    local base_url
    base_url=$(extract_base_url "${PORTAL_URL}")
    form_action=$(make_absolute_url "${base_url}" "${form_action}")

    log_debug "Form action: ${form_action}"
    log_debug "Form method: ${form_method}"
    log_debug "Form data: ${form_data}"

    # Submit form
    log "Submitting form to: ${form_action}"
    if [ "${form_method}" = "get" ]; then
        curl -s -L \
            --max-time "${TIMEOUT}" \
            --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" \
            --cookie-jar "${COOKIES_FILE}" \
            --output /dev/null \
            "${form_action}?${form_data}" 2>/dev/null
    else
        curl -s -L \
            --max-time "${TIMEOUT}" \
            --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" \
            --cookie-jar "${COOKIES_FILE}" \
            --data "${form_data}" \
            --output /dev/null \
            "${form_action}" 2>/dev/null
    fi

    # Check if we now have internet
    sleep 2
    if check_internet; then
        log "SUCCESS: Portal accepted via form submission"
        return 0
    fi

    log "Strategy 2 failed: Form submission did not grant access"
    return 1
}

# --- Strategy 3: Known Vendor Patterns ---

try_known_patterns() {
    log "Strategy 3: Trying known vendor patterns..."

    # Download portal page if not already downloaded
    if [ ! -f "${PORTAL_HTML}" ]; then
        curl -s -L \
            --max-time 10 \
            --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" \
            --cookie-jar "${COOKIES_FILE}" \
            --output "${PORTAL_HTML}" \
            "${PORTAL_URL}" 2>/dev/null || return 1
    fi

    local base_url
    base_url=$(extract_base_url "${PORTAL_URL}")

    # Pattern 1: Aruba/Ruckus Networks
    if grep -qi "aruba\|ruckus" "${PORTAL_HTML}"; then
        log "Detected Aruba/Ruckus portal"
        local aruba_url="${base_url}/guest/s/default/?accept=true"
        if curl -s -L --max-time "${TIMEOUT}" --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" --cookie-jar "${COOKIES_FILE}" \
            --output /dev/null "${aruba_url}" 2>/dev/null; then
            sleep 2
            if check_internet; then
                log "SUCCESS: Aruba/Ruckus pattern worked"
                return 0
            fi
        fi
    fi

    # Pattern 2: Cisco Meraki
    if grep -qi "meraki\|cisco" "${PORTAL_HTML}"; then
        log "Detected Cisco Meraki portal"
        local meraki_url="${base_url}/login.html"
        if curl -s -L --max-time "${TIMEOUT}" --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" --cookie-jar "${COOKIES_FILE}" \
            --data "buttonClicked=4&acceptTerms=on" \
            --output /dev/null "${meraki_url}" 2>/dev/null; then
            sleep 2
            if check_internet; then
                log "SUCCESS: Cisco Meraki pattern worked"
                return 0
            fi
        fi
    fi

    # Pattern 3: UniFi Guest Portal
    if grep -qi "ubiquiti\|unifi" "${PORTAL_HTML}"; then
        log "Detected UniFi portal"
        local unifi_url="${base_url}/guest/s/default/"
        if curl -s -L --max-time "${TIMEOUT}" --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" --cookie-jar "${COOKIES_FILE}" \
            --data "accept=true" \
            --output /dev/null "${unifi_url}" 2>/dev/null; then
            sleep 2
            if check_internet; then
                log "SUCCESS: UniFi pattern worked"
                return 0
            fi
        fi
    fi

    # Pattern 4: Mikrotik HotSpot
    if grep -qi "mikrotik" "${PORTAL_HTML}" || echo "${PORTAL_URL}" | grep -qi "hotspot"; then
        log "Detected potential Mikrotik HotSpot"
        local mikrotik_url="${base_url}/login"
        if curl -s -L --max-time "${TIMEOUT}" --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" --cookie-jar "${COOKIES_FILE}" \
            --data "username=&password=" \
            --output /dev/null "${mikrotik_url}" 2>/dev/null; then
            sleep 2
            if check_internet; then
                log "SUCCESS: Mikrotik pattern worked"
                return 0
            fi
        fi
    fi

    # Pattern 5: pfSense Captive Portal
    if grep -qi "pfsense" "${PORTAL_HTML}"; then
        log "Detected pfSense portal"
        local pfsense_url="${base_url}/"
        if curl -s -L --max-time "${TIMEOUT}" --user-agent "${USER_AGENT}" \
            --cookie "${COOKIES_FILE}" --cookie-jar "${COOKIES_FILE}" \
            --data "accept=Continue" \
            --output /dev/null "${pfsense_url}" 2>/dev/null; then
            sleep 2
            if check_internet; then
                log "SUCCESS: pfSense pattern worked"
                return 0
            fi
        fi
    fi

    log "Strategy 3 failed: No known vendor pattern matched"
    return 1
}

# --- Main Execution ---

main() {
    # Validate input
    if [ -z "${PORTAL_URL}" ]; then
        log "ERROR: No portal URL provided"
        echo "Usage: $0 <portal_url>" >&2
        exit 1
    fi

    log "Starting captive portal bypass for: ${PORTAL_URL}"

    # Check if we already have internet (shouldn't happen, but just in case)
    if check_internet; then
        log "Internet already available, no bypass needed"
        exit 0
    fi

    # Try each strategy in order
    if try_simple_urls; then
        exit 0
    fi

    if try_form_submission; then
        exit 0
    fi

    if try_known_patterns; then
        exit 0
    fi

    log "FAILED: All bypass strategies failed"
    log "Portal may require manual intervention or browser-based acceptance"
    exit 1
}

main
