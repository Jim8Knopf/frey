#!/bin/bash

# ==============================================================================
# Frey WiFi DHCP Debug Script with Auto-Reconnect
#
# Debugs DHCP issues on LibrariesSA-Free, then reconnects to hotspot
# Logs everything so we can analyze after SSH is restored
# ==============================================================================

LOG_FILE="/var/log/frey-dhcp-debug.log"
INTERFACE="wlan0"
HOTSPOT_SSID="NOTHING by JK"
HOTSPOT_PASS="c9wm9kk42cnwd5g"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "==============================================================================="
log "=== DHCP Debug Session Started ==="
log "==============================================================================="
log ""

# Connect to LibrariesSA-Free
log "Step 1: Connecting to LibrariesSA-Free..."
log "---------------------------------------------------------------"
frey-connect-wifi "LibrariesSA-Free" "" >> "$LOG_FILE" 2>&1
CONNECT_RESULT=$?

if [ $CONNECT_RESULT -ne 0 ]; then
    log "ERROR: Failed to connect to LibrariesSA-Free"
    log "Check /var/log/frey-wifi-connect.log for details"
    exit 1
fi

log "WiFi association complete"
log ""

# Wait for connection to stabilize
log "Waiting 5 seconds for WiFi to stabilize..."
sleep 5
log ""

# Kill existing dhcpcd and try with full debug
log "Step 2: Killing existing dhcpcd processes..."
log "---------------------------------------------------------------"
pkill -f "dhcpcd.*$INTERFACE" >> "$LOG_FILE" 2>&1
sleep 2
log "Existing dhcpcd processes killed"
log ""

# Release any existing DHCP lease
log "Releasing any existing DHCP lease..."
dhcpcd -k "$INTERFACE" >> "$LOG_FILE" 2>&1 || true
sleep 2
log ""

# Show interface status BEFORE
log "Step 3: Interface status BEFORE dhcpcd:"
log "---------------------------------------------------------------"
ip addr show "$INTERFACE" | tee -a "$LOG_FILE"
log ""
ip route | tee -a "$LOG_FILE"
log ""

# Try dhcpcd with extensive debugging
log "Step 4: Attempting dhcpcd with FULL DEBUG..."
log "---------------------------------------------------------------"
log "Timeout: 180 seconds"
log "This will capture all DHCP messages (DISCOVER, OFFER, REQUEST, ACK)"
log ""

# Capture dhcpcd debug output
START_TIME=$(date +%s)
dhcpcd --debug --rebind --timeout 180 "$INTERFACE" >> "$LOG_FILE" 2>&1
DHCP_RESULT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log ""
log "dhcpcd finished in $DURATION seconds"
log "dhcpcd exit code: $DHCP_RESULT"
log ""

# Check results
log "Step 5: Interface status AFTER dhcpcd:"
log "---------------------------------------------------------------"
ip addr show "$INTERFACE" | tee -a "$LOG_FILE"
log ""

log "Step 6: Routing table:"
log "---------------------------------------------------------------"
ip route | tee -a "$LOG_FILE"
log ""

# Check if we got an IP
WLAN0_IPV4=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
WLAN0_IPV6=$(ip -6 addr show "$INTERFACE" | grep 'inet6.*scope global' | awk '{print $2}')

if [ -n "$WLAN0_IPV4" ]; then
    log "✓ SUCCESS: Got IPv4 address: $WLAN0_IPV4"
    log ""

    # Try to access portal
    log "Step 7: Testing portal access..."
    log "---------------------------------------------------------------"
    GATEWAY=$(ip route | grep default | grep "$INTERFACE" | awk '{print $3}')
    log "Gateway: ${GATEWAY:-NONE}"
    log ""

    if [ -n "$GATEWAY" ]; then
        log "Testing gateway connectivity..."
        if ping -c 3 -W 5 "$GATEWAY" >> "$LOG_FILE" 2>&1; then
            log "✓ Gateway is reachable"
        else
            log "✗ Gateway is NOT reachable"
        fi
        log ""

        log "Testing http://$GATEWAY/..."
        curl -v -m 10 "http://$GATEWAY/" > /tmp/portal-gateway.html 2>&1 | tee -a "$LOG_FILE"

        SIZE=$(wc -c < /tmp/portal-gateway.html 2>/dev/null || echo "0")
        log "Downloaded $SIZE bytes to /tmp/portal-gateway.html"

        if [ "$SIZE" -gt 100 ]; then
            log "Analyzing portal page..."
            FORMS=$(grep -ic '<form' /tmp/portal-gateway.html || echo "0")
            log "Found $FORMS form(s) in page"
        fi
    fi

    log ""
    log "Testing http://neverssl.com..."
    curl -vL -m 10 "http://neverssl.com" > /tmp/portal-neverssl.html 2>&1 | tee -a "$LOG_FILE"

    SIZE=$(wc -c < /tmp/portal-neverssl.html 2>/dev/null || echo "0")
    log "Downloaded $SIZE bytes to /tmp/portal-neverssl.html"

    log ""
    log "Testing DNS..."
    nslookup google.com >> "$LOG_FILE" 2>&1 && log "✓ DNS working" || log "✗ DNS failed"

elif [ -n "$WLAN0_IPV6" ]; then
    log "⚠ No IPv4, but got IPv6 address: $WLAN0_IPV6"
    log ""
    log "Some public WiFi networks provide IPv6 only or IPv6 first"
    log "Trying to access portal via IPv6..."
    log ""
    curl -6 -vL -m 10 "http://neverssl.com" > /tmp/portal-ipv6.html 2>&1 | tee -a "$LOG_FILE"

else
    log "✗ FAILED: No IP address obtained (neither IPv4 nor IPv6)"
    log ""
    log "Checking link status..."
    iw dev "$INTERFACE" link | tee -a "$LOG_FILE"
    log ""

    log "Checking for any DHCP messages in log..."
    log "---------------------------------------------------------------"
    grep -i 'dhcp\|discover\|offer\|request\|ack\|nak' "$LOG_FILE" | tail -n 20 | tee -a "${LOG_FILE}.summary"
fi

# Always reconnect to hotspot to restore SSH
log ""
log "==============================================================================="
log "Step 8: Reconnecting to hotspot to restore internet..."
log "==============================================================================="
frey-connect-wifi "$HOTSPOT_SSID" "$HOTSPOT_PASS" >> "$LOG_FILE" 2>&1
RECONNECT_RESULT=$?

if [ $RECONNECT_RESULT -eq 0 ]; then
    log "✓ Reconnected to hotspot successfully"
else
    log "✗ WARNING: Failed to reconnect to hotspot (exit code: $RECONNECT_RESULT)"
fi

log ""
log "==============================================================================="
log "=== Debug Session Complete ==="
log "==============================================================================="
log ""
log "Full log saved to: $LOG_FILE"
log ""
log "To review:"
log "  sudo cat $LOG_FILE"
log "  sudo grep -E 'DHCP|discover|offer|request|ack|NAK|timeout' $LOG_FILE"
log ""
log "Portal HTML files:"
log "  ls -lh /tmp/portal-*.html"
log ""
log "Key findings summary:"
log "  IPv4 address: ${WLAN0_IPV4:-NONE}"
log "  IPv6 address: ${WLAN0_IPV6:-NONE}"
log "  Gateway: ${GATEWAY:-NONE}"
log "  DHCP duration: ${DURATION}s"
log "  DHCP exit code: $DHCP_RESULT"
log ""
