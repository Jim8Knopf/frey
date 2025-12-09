#!/bin/bash

# ==============================================================================
# Freya-WiFi-Captive-Portal-Auto
#
# A script to automatically connect to open Wi-Fi networks and handle
# basic captive portals.
#
# This script is designed to be run periodically by a scheduler like systemd/cron.
#
# Dependencies:
# - wpa_cli (wpa_supplicant command-line tool)
# - curl
# ==============================================================================

# --- Configuration ---

# List of known SSIDs to NOT auto-connect to (e.g., private networks).
# Add your home Wi-Fi, phone hotspot, etc. here.
# Example: KNOWN_SSIDS=("MyHome" "MyPhoneHotspot")
KNOWN_SSIDS=()

# Log file for debugging and history.
LOG_FILE="/var/log/frey-wifi-auto-connect.log"

# URL to test for captive portal detection.
# Should be a non-HTTPS URL that returns a predictable response.
PORTAL_TEST_URL="http://neverssl.com"

# --- Script Logic ---

# Function to write log messages to LOG_FILE and stdout.
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Checks if the device is currently connected to one of the KNOWN_SSIDS.
# Returns 0 if connected to a known network, 1 otherwise.
is_connected_to_known_network() {
    # Get the SSID of the active Wi-Fi connection.
    # Using wpa_cli instead of nmcli to match Pi's actual network stack (wpa_supplicant)
    local current_ssid
    current_ssid=$(wpa_cli -i wlan0 status | grep '^ssid=' | cut -d'=' -f2)

    if [ -z "$current_ssid" ]; then
        return 1 # Not connected to any Wi-Fi.
    fi

    for ssid in "${KNOWN_SSIDS[@]}"; do
        if [ "$current_ssid" == "$ssid" ]; then
            return 0 # Connected to a known network.
        fi
    done

    # Connected, but not to a network in our known list.
    # We'll treat this as a public network we might need to check for a portal.
    return 1
}

# Scans for and connects to the strongest open Wi-Fi network.
connect_to_open_network() {
    log "Scanning for open Wi-Fi networks..."

    # Find the strongest open (no security) network.
    # Format: SSID,SECURITY,SIGNAL
    local best_ssid
    best_ssid=$(nmcli --terse --fields SSID,SECURITY,SIGNAL dev wifi list | grep ':$' | sort -t: -k3 -n -r | head -n1 | cut -d':' -f1)

    if [ -n "$best_ssid" ]; then
        log "Found open network: '$best_ssid'. Attempting to connect."
        
        # Attempt to connect. nmcli will create and manage the connection profile.
        if nmcli dev wifi connect "$best_ssid"; then
            log "Successfully initiated connection to '$best_ssid'."
            return 0
        else
            log "Failed to connect to '$best_ssid'."
            return 1
        fi
    else
        log "No open Wi-Fi networks found."
        return 1
    fi
}

# Detects and attempts to handle a captive portal using multiple bypass strategies.
# Uses multi-layered detection: HTTP redirect, ping test, and content verification.
check_captive_portal() {
    log "Checking for captive portal..."
    local portal_detected=false
    local portal_url=""

    # Test 1: Check for HTTP redirect (traditional method)
    local final_url
    final_url=$(curl -s -w "%{url_effective}" -o /dev/null --max-time 10 "$PORTAL_TEST_URL" 2>/dev/null)

    if [[ -n "$final_url" ]] && [[ "$final_url" != "$PORTAL_TEST_URL"* ]]; then
        log "Portal detected (Test 1): HTTP redirect to $final_url"
        portal_detected=true
        portal_url="$final_url"
    fi

    # Test 2: Verify real internet with ping (catches non-redirecting portals)
    if [ "$portal_detected" = false ]; then
        if ! ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
            log "Portal detected (Test 2): Ping to 1.1.1.1 failed (no real internet)"
            portal_detected=true
            # Try to find portal URL from gateway
            local gateway
            gateway=$(ip route | grep default | awk '{print $3}' | head -n1)
            [ -n "$gateway" ] && portal_url="http://$gateway/"
        fi
    fi

    # Test 3: Verify HTTP response content (catches interception without redirect)
    if [ "$portal_detected" = false ]; then
        local response
        response=$(curl -s --max-time 10 "$PORTAL_TEST_URL" 2>/dev/null)
        # neverssl.com should contain "NeverSSL" in the response
        if [ -n "$response" ] && ! echo "$response" | grep -q "NeverSSL"; then
            log "Portal detected (Test 3): Unexpected HTTP response content"
            portal_detected=true
            # Response might be portal HTML - try to extract form action URL
            local form_action
            form_action=$(echo "$response" | grep -oP 'action="\K[^"]+' | head -n1)
            [ -n "$form_action" ] && portal_url="$form_action"
        fi
    fi

    # Test 4: Transparent portal detection (HTTP works but ICMP blocked)
    # Some modern portals (like Encapto) block internet traffic without HTTP redirects
    if [ "$portal_detected" = false ]; then
        # Check if HTTP to generate_204 works but ICMP doesn't
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://clients3.google.com/generate_204" 2>/dev/null || echo "000")

        # If we get HTTP response (not 204) but ICMP fails, it's a transparent portal
        if [ "${http_code}" != "000" ] && [ "${http_code}" != "204" ]; then
            if ! ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
                log "Portal detected (Test 4): Transparent portal (HTTP=${http_code}, ICMP blocked)"
                portal_detected=true
                # Try to get portal URL from the HTTP redirect or gateway
                local redirect_url
                redirect_url=$(curl -s -L -w "%{url_effective}" -o /dev/null --max-time 10 "http://clients3.google.com/generate_204" 2>/dev/null || echo "")
                if [ -n "$redirect_url" ] && [ "$redirect_url" != "http://clients3.google.com/generate_204" ]; then
                    portal_url="$redirect_url"
                else
                    # Fall back to gateway
                    local gateway
                    gateway=$(ip route | grep default | awk '{print $3}' | head -n1)
                    [ -n "$gateway" ] && portal_url="http://$gateway/"
                fi
            fi
        fi
    fi

    # If portal detected, save state and attempt bypass
    if [ "$portal_detected" = true ]; then
        log "Captive portal confirmed. Attempting bypass..."
        [ -n "$portal_url" ] && log "Portal URL: $portal_url"

        # Save portal state for manual login tool
        local STATE_FILE="/var/lib/frey/captive-portal/portal.state"
        mkdir -p "$(dirname "$STATE_FILE")"
        {
            echo "portal_url=${portal_url:-unknown}"
            echo "detected_at=$(date +%s)"
            echo "detected_at_human=$(date)"
            local current_ssid
            current_ssid=$(wpa_cli -i wlan0 status 2>/dev/null | grep '^ssid=' | cut -d'=' -f2 || echo "unknown")
            echo "ssid=${current_ssid}"
        } > "$STATE_FILE"
        chmod 644 "$STATE_FILE"

        # Strategy 1: Try shell-based bypass first (fast and lightweight)
        local shell_bypasser="/usr/local/bin/frey-wifi-portal-shell-bypass.sh"
        if [ -x "$shell_bypasser" ]; then
            log "Attempting shell-based portal bypass..."
            if "$shell_bypasser" "${portal_url:-$PORTAL_TEST_URL}"; then
                log "Shell-based bypass succeeded!"
                # Clear portal state and notifications on success
                rm -f "$STATE_FILE" /etc/motd.d/90-captive-portal
                return 0
            else
                log "Shell-based bypass failed, trying fallback methods..."
            fi
        else
            log "WARNING: Shell bypass script not found at $shell_bypasser"
        fi

        # Strategy 2: Fall back to Selenium/Python if shell bypass failed
        local python_bypasser="/usr/local/bin/frey-wifi-portal-bypasser.py"
        if [ -x "$python_bypasser" ]; then
            log "Attempting Selenium-based bypass..."
            # Call the Python script with the detected portal URL.
            # The Python script will print its own logs to stderr.
            if "$python_bypasser" "${portal_url:-$PORTAL_TEST_URL}"; then
                log "Selenium-based bypass succeeded!"
                # Clear portal state and notifications on success
                rm -f "$STATE_FILE" /etc/motd.d/90-captive-portal
                return 0
            else
                log "Selenium-based bypass failed."
            fi
        else
            log "WARNING: Selenium bypass script not found at $python_bypasser"
        fi

        log "ERROR: All portal bypass strategies failed"
        log "MANUAL INTERVENTION REQUIRED"

        # Notify user via multiple methods
        # Method 1: wall (for active SSH sessions)
        wall "Captive portal detected but auto-bypass failed. Run 'frey wifi portal' to authenticate manually." 2>/dev/null || true

        # Method 2: MOTD (for next login)
        mkdir -p /etc/motd.d
        cat > /etc/motd.d/90-captive-portal << 'EOF'

================================================================================
  CAPTIVE PORTAL DETECTED - Manual Login Required
================================================================================

  Your Pi is connected to a WiFi network that requires authentication.
  Automatic bypass failed. Please complete authentication manually:

    frey wifi portal

  This will open an interactive text browser to complete the login.

================================================================================
EOF

        # Method 3: Systemd journal (high priority)
        logger -t frey-portal -p user.warning "Captive portal detected, manual login required: frey wifi portal"

        return 1
    else
        log "No captive portal detected. Internet access verified."
        # Clear any stale notifications
        rm -f /var/lib/frey/captive-portal/portal.state /etc/motd.d/90-captive-portal
        return 0
    fi
}

# --- Main Execution ---

main() {
    touch "$LOG_FILE"
    log "--- Running WiFi Auto-Connect Check ---"

    # Don't do anything if we are connected to a trusted network.
    if is_connected_to_known_network; then
        log "Connected to a known network. Exiting."
        exit 0
    fi
    
    # Check current connection status.
    # Using wpa_cli instead of nmcli to match Pi's actual network stack
    local active_con
    active_con=$(wpa_cli -i wlan0 status | grep '^wpa_state=' | cut -d'=' -f2)

    if [ "$active_con" != "COMPLETED" ]; then
        log "Not connected to any Wi-Fi network."
        if connect_to_open_network; then
            sleep 10 # Give the connection time to establish and get an IP.
            check_captive_portal
        fi
    else
        log "Connected to an unknown/public network: '$active_con'."
        check_captive_portal
    fi

    log "--- WiFi Auto-Connect Check Finished ---"
}

main
