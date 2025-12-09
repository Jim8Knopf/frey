#!/bin/bash

# ==============================================================================
# Frey Enhanced Captive Portal Login Tool
#
# Auto-detects captive portals (even when DNS is blocked), tries automatic
# bypass first, then opens lynx for manual authentication if needed.
#
# Usage: frey wifi portal   (auto-sudo) or sudo frey-portal-login
# ==============================================================================

set -euo pipefail

# --- Configuration ---
STATE_FILE="/var/lib/frey/captive-portal/portal.state"
MOTD_FILE="/etc/motd.d/90-captive-portal"
LOG_PREFIX="[PortalLogin]"
BYPASS_TOOL="/usr/local/bin/frey-wifi-portal-shell-bypass.sh"
WIFI_CLIENT_INTERFACE="${WIFI_CLIENT_INTERFACE:-wlan0}"  # Default client interface for gateway detection
SOCKS_PORT="${SOCKS_PORT:-1080}"                         # Local SOCKS5 port exposed for headless login

# Defensive initialization for variables that might be used by subshells
lynx_dir="${lynx_dir:-}"  # Prevent "unbound variable" errors from lynx or subshells

# --- Logging Functions ---
log() {
    echo "${LOG_PREFIX} $1" >&2
    logger -t frey-portal-login "$1"
}

log_success() {
    echo -e "${LOG_PREFIX} \e[32m✓\e[0m $1" >&2
}

log_error() {
    echo -e "${LOG_PREFIX} \e[31m✗\e[0m $1" >&2
}

log_info() {
    echo -e "${LOG_PREFIX} \e[34mℹ\e[0m $1" >&2
}

# --- Internet Connectivity Check ---
check_internet() {
    log_info "Checking internet connectivity..."

    # Test 1: ICMP ping to Cloudflare DNS
    if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
        log_success "Internet connectivity verified (ICMP to 1.1.1.1)"
        return 0
    fi

    # Test 2: ICMP ping to Google DNS
    if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet connectivity verified (ICMP to 8.8.8.8)"
        return 0
    fi

    log_error "No internet connectivity detected"
    return 1
}

# --- Portal URL Detection (DNS-Independent, Docker-Aware) ---
detect_portal_url() {
    log_info "Detecting captive portal..."

    # Method 1: Get default gateway for the specific client interface (avoids Docker routes)
    local gateway
    gateway=$(ip route | grep "^default.*dev ${WIFI_CLIENT_INTERFACE}" | awk '{print $3}' | head -n1)

    # Method 2: If no interface-specific route, filter out Docker virtual interfaces
    if [ -z "$gateway" ]; then
        log_info "No interface-specific route, filtering Docker interfaces..."
        gateway=$(ip route | grep '^default' | awk '{print $3 " " $5}' | grep -vE 'veth|docker|br-|169\.254\.' | awk '{print $1}' | head -n1)
    fi

    # Method 3: If still no gateway, derive it from wlan0 IP (captive portals often don't provide gateway before auth)
    if [ -z "$gateway" ]; then
        log_info "No default route found, deriving gateway from interface IP..."
        local wlan_ip
        wlan_ip=$(ip addr show "$WIFI_CLIENT_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)

        if [ -n "$wlan_ip" ]; then
            # If interface only has link-local IP, wait for DHCP to complete
            if [[ "$wlan_ip" =~ ^169\.254\. ]]; then
                log_info "Interface has link-local IP (169.254.x.x) - waiting for DHCP..."
                sleep 5
                wlan_ip=$(ip addr show "$WIFI_CLIENT_INTERFACE" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            fi

            # Extract subnet (e.g., 10.6.110.185 -> 10.6.110)
            local subnet
            subnet=$(echo "$wlan_ip" | awk -F. '{print $1"."$2"."$3}')

            # Try common gateway addresses
            for gw_suffix in 1 254 100; do  # Prefer .1, then .254, then .100
                local candidate="${subnet}.${gw_suffix}"
                log_info "Testing gateway candidate: $candidate"
                if ping -c 2 -W 3 "$candidate" >/dev/null 2>&1; then
                    gateway="$candidate"
                    log_success "Found reachable gateway: $gateway"
                    break
                fi
            done
        fi
    fi

    if [ -z "$gateway" ]; then
        log_error "No default gateway found and could not derive one"
        return 1
    fi

    log_info "Gateway: $gateway (via $WIFI_CLIENT_INTERFACE)"

    # Wait for network to stabilize after WiFi connection
    log_info "Waiting for network to stabilize..."
    sleep 3

    local portal_url=""

    # Method 1: Try captive portal detection URLs (most reliable - they redirect to login)
    log_info "Trying captive portal detection URLs..."
    for detection_url in "http://captive.apple.com/" "http://detectportal.firefox.com/success.txt" "http://connectivitycheck.gstatic.com/generate_204"; do
        log_info "Testing: $detection_url"
        portal_url=$(curl -s -L -w "%{url_effective}" -o /dev/null --max-time 5 "$detection_url" 2>/dev/null || echo "")

        # If URL changed (redirect occurred), we found the portal
        if [ -n "$portal_url" ] && [ "$portal_url" != "$detection_url" ]; then
            log_success "Portal detected via redirect: $portal_url"
            echo "$portal_url"
            return 0
        fi

        # If we got the original URL back, internet might already work
        if [ "$portal_url" = "$detection_url" ]; then
            log_info "Detection URL responded normally (might indicate internet access)"
        fi
    done

    # Method 2: Try gateway directly with common portal paths
    log_info "Trying gateway with common portal paths..."
    for path in "" "/login" "/portal" "/guest/s/login"; do
        local test_url="http://$gateway${path}"
        log_info "Testing: $test_url"

        # Check if URL responds to HTTP at all
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$test_url" 2>/dev/null || echo "000")

        if [ "$http_code" != "000" ] && [ "$http_code" != "timeout" ]; then
            log_success "Gateway responds on $test_url (HTTP $http_code)"
            echo "$test_url"
            return 0
        fi
    done

    # Method 3: Gateway doesn't serve HTTP, but portal might work via DNS hijacking
    # Try a known external site that portal should redirect
    log_info "Testing DNS-based portal redirect..."
    portal_url=$(curl -s -L -w "%{url_effective}" -o /dev/null --max-time 5 "http://example.com/" 2>/dev/null || echo "")

    if [ -n "$portal_url" ] && [[ "$portal_url" == *"$gateway"* ]]; then
        log_success "Portal detected via DNS redirect: $portal_url"
        echo "$portal_url"
        return 0
    fi

    # Fallback: Use captive.apple.com as it's most likely to work
    log_info "Using captive.apple.com as fallback portal trigger"
    echo "http://captive.apple.com/"
    return 0
}

# --- Automatic Bypass Attempt ---
try_auto_bypass() {
    local portal_url="$1"

    log_info "Attempting automatic bypass..."

    # Check if bypass tool exists
    if [ ! -x "$BYPASS_TOOL" ]; then
        log_info "Auto-bypass tool not available"
        return 1
    fi

    # Try bypass (suppress output)
    if "$BYPASS_TOOL" "$portal_url" >/dev/null 2>&1; then
        log_success "Auto-bypass succeeded!"

        # Verify internet
        if check_internet; then
            log_success "Internet access verified!"
            cleanup_on_success
            return 0
        fi
    fi

    log_info "Auto-bypass failed"
    return 1
}

# --- Launch Interactive Browser ---
launch_lynx() {
    local url="$1"
    local ssid="$2"
    local cookie_file="/tmp/lynx-cookies-$$.txt"

    clear
    echo ""
    echo "==============================================================================="
    echo "  CAPTIVE PORTAL DETECTED - Manual Login Required"
    echo "==============================================================================="
    echo ""
    echo "  Network: $ssid"
    echo "  Portal URL: $url"
    echo ""
    echo "  AUTO-BYPASS FAILED - Opening interactive browser..."
    echo ""
    echo "  Instructions:"
    echo "    • Look for 'Accept', 'Continue', or 'I Agree' buttons"
    echo "    • Use ARROW KEYS to navigate"
    echo "    • Press ENTER to click buttons"
    echo "    • For checkboxes: Navigate to them and press ENTER"
    echo "    • Press 'q' then 'y' to quit lynx when done"
    echo ""
    echo "  After authenticating, this script will verify internet access."
    echo ""
    echo "==============================================================================="
    echo ""
    read -r -p "Press ENTER to open portal..."

    # Launch lynx with portal-optimized settings
    lynx -accept_all_cookies \
         -cookie_file="$cookie_file" \
         -cookie_save_file="$cookie_file" \
         -useragent="Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
         -display_charset=utf-8 \
         -nolist \
         "$url" || true

    # Cleanup
    rm -f "$cookie_file"
}

# --- Cleanup on Success ---
cleanup_on_success() {
    log_info "Cleaning up portal state..."
    rm -f "$STATE_FILE" "$MOTD_FILE"
    log_success "Portal state cleared"
}

# --- Start local SOCKS proxy (for browser-based manual login) ---
ensure_socks_proxy() {
    local pidfile="/run/frey-portal-socks.pid"

    # Reuse existing process if alive
    if [ -f "$pidfile" ]; then
        local existing_pid
        existing_pid=$(cat "$pidfile" 2>/dev/null || true)
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            return 0
        fi
    fi

    mkdir -p /run/frey /var/log/frey
    # Bind SOCKS to 0.0.0.0 so laptop/phone on LAN/AP can reach it; exit on failure
    setsid ssh -g -N \
        -o ExitOnForwardFailure=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -D "0.0.0.0:${SOCKS_PORT}" \
        localhost \
        > /var/log/frey/portal-socks.log 2>&1 &
    echo $! > "$pidfile"
}

# --- Headless helper (for manual login from another device) ---
print_headless_helper() {
    local portal_url="$1"
    local ip_list
    ip_list=$(hostname -I 2>/dev/null | xargs)

    echo ""
    echo "-------------------------------------------------------------------------------"
    echo " Headless login helper (use from your laptop if auto-bypass fails)"
    echo "-------------------------------------------------------------------------------"
    echo " Portal URL: $portal_url"
    echo " Pi IPs (pick one reachable from your laptop/phone): ${ip_list:-unknown}"
    echo ""
    echo " Automatic helper running on Pi:"
    echo "   SOCKS5: <pi-ip>:${SOCKS_PORT} (proxy DNS on)"
    echo ""
    echo " Manjaro/Linux browser setup:"
    echo "   - Set browser proxy to SOCKS5 host <pi-ip>, port ${SOCKS_PORT}"
    echo "   - Enable \"Proxy DNS\"/\"SOCKS v5\""
    echo "   - Open the portal URL above and complete the login"
    echo ""
    echo " Android:"
    echo "   - If your WiFi settings allow SOCKS, set host <pi-ip>, port ${SOCKS_PORT}"
    echo "   - Otherwise, use an app (e.g., SocksDroid/Every Proxy) or Termux: ssh -D 1080 ansible@<pi-ip>"
    echo ""
    echo " Fallback (laptop command if needed):"
    echo "   ssh -D 1080 ansible@<pi-ip>   # then SOCKS5 localhost:1080 in browser"
    echo "-------------------------------------------------------------------------------"
    echo ""
}

# --- Main Execution ---
main() {
    # Elevate automatically when run directly
    if [ "$EUID" -ne 0 ]; then
        exec sudo "$0" "$@"
    fi

    clear
    echo ""
    echo "==============================================================================="
    echo "  Frey Captive Portal Login"
    echo "==============================================================================="
    echo ""

    # Step 1: Check if internet already works
    if check_internet; then
        log_success "Internet already available, no portal login needed!"
        cleanup_on_success
        exit 0
    fi

    # Step 2: Detect portal URL (DNS-independent)
    log_info "Internet blocked - detecting captive portal..."
    local portal_url
    if ! portal_url=$(detect_portal_url); then
        log_error "Could not detect portal URL"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check WiFi connection: iwconfig $WIFI_CLIENT_INTERFACE"
        echo "  2. Check DHCP lease: ip addr show $WIFI_CLIENT_INTERFACE"
        echo "  3. Check gateway: ip route | grep default"
        echo "  4. Check interface routes: ip route show dev $WIFI_CLIENT_INTERFACE"
        echo ""
        echo "Current routing table:"
        ip route show
        echo ""
        exit 1
    fi

    # Get SSID for display
    local ssid
    ssid=$(iwconfig $WIFI_CLIENT_INTERFACE 2>/dev/null | grep ESSID | awk -F'"' '{print $2}' || echo "Unknown")

    # Print headless helper info early so user can switch to browser if needed
    print_headless_helper "$portal_url"

    # Step 3: Try automatic bypass
    if try_auto_bypass "$portal_url"; then
        echo ""
        echo "==============================================================================="
        echo "  SUCCESS! Auto-bypass worked"
        echo "==============================================================================="
        echo ""
        echo "Internet access is now available."
        echo ""
        exit 0
    fi

    # Step 3b: Spin up SOCKS helper for browser-based manual login
    log_info "Starting local SOCKS helper for browser-based login..."
    ensure_socks_proxy

    # Step 4: Manual login with lynx (auto-bypass failed)
    launch_lynx "$portal_url" "$ssid"

    # Step 5: Verify internet access
    echo ""
    echo "==============================================================================="
    echo "  Verifying Internet Access"
    echo "==============================================================================="
    echo ""

    if check_internet; then
        log_success "SUCCESS! Portal authentication completed!"
        log_success "Internet access verified"
        cleanup_on_success
        echo ""
        echo "You can now use the internet normally."
        echo ""
        exit 0
    else
        log_error "Authentication may not be complete"
        echo ""
        echo "If you completed the portal login but still don't have internet:"
        echo "  1. The portal may require additional steps (check email, etc.)"
        echo "  2. Try running this tool again: frey wifi portal"
        echo "  3. Check logs: sudo journalctl -t frey-portal-login -n 20"
        echo ""
        exit 1
    fi
}

main
