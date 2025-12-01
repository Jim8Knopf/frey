#!/bin/bash

# ==============================================================================
# Frey WiFi Captive Portal Test Script
#
# Tests captive portal bypass on wlan0 while maintaining SSH via wlan1 AP
# Captures portal HTML and logs all attempts for analysis
# ==============================================================================

LOG_FILE="/var/log/frey-portal-test.log"
PORTAL_HTML="/tmp/portal-capture.html"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "==============================================================================="
log "=== Starting Captive Portal Test ==="
log "==============================================================================="
log ""

# Connect to LibrariesSA-Free (or any open public WiFi)
log "Step 1: Connecting to LibrariesSA-Free..."
log "---------------------------------------------------------------"
frey-connect-wifi "LibrariesSA-Free" "" >> "$LOG_FILE" 2>&1
CONNECT_RESULT=$?

if [ $CONNECT_RESULT -ne 0 ]; then
    log "ERROR: Failed to connect to LibrariesSA-Free"
    exit 1
fi

log "Connected to WiFi (wlan0)"
log ""

# Wait for connection to stabilize
log "Waiting 5 seconds for connection to stabilize..."
sleep 5
log ""

# Detect captive portal
log "Step 2: Detecting captive portal..."
log "---------------------------------------------------------------"
PORTAL_URL=$(curl -s -w "%{url_effective}" -o /dev/null --max-time 10 "http://neverssl.com")
log "Test URL: http://neverssl.com"
log "Redirect URL: $PORTAL_URL"
log ""

if [ "$PORTAL_URL" = "http://neverssl.com" ] || [ "$PORTAL_URL" = "http://neverssl.com/" ]; then
    log "No captive portal detected - already have internet!"
    log "Testing connectivity..."
    if ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1; then
        log "SUCCESS: Internet access working without portal bypass!"
    else
        log "WARNING: No redirect detected but no internet either"
    fi
    log "Skipping bypass test"
else
    log "Captive portal detected!"
    log ""

    # Capture portal HTML
    log "Step 3: Capturing portal HTML..."
    log "---------------------------------------------------------------"
    curl -s "$PORTAL_URL" > "$PORTAL_HTML"
    PORTAL_SIZE=$(wc -c < "$PORTAL_HTML")
    log "Portal HTML saved to: $PORTAL_HTML"
    log "File size: $PORTAL_SIZE bytes"
    log ""

    # Analyze portal structure
    log "Step 4: Analyzing portal structure..."
    log "---------------------------------------------------------------"
    log "Looking for forms:"
    grep -i '<form' "$PORTAL_HTML" | head -n 5 | tee -a "$LOG_FILE"
    log ""
    log "Looking for checkboxes and accept buttons:"
    grep -iE 'checkbox|accept|agree|type.*submit|button' "$PORTAL_HTML" | head -n 10 | tee -a "$LOG_FILE"
    log ""

    # Test bypass script
    log "Step 5: Testing shell bypass script..."
    log "---------------------------------------------------------------"
    log "Running: /usr/local/bin/frey-wifi-portal-shell-bypass.sh"
    log "Debug mode: ON"
    log ""

    DEBUG=1 /usr/local/bin/frey-wifi-portal-shell-bypass.sh "$PORTAL_URL" 2>&1 | tee -a "$LOG_FILE"
    BYPASS_RESULT=$?

    log ""
    log "Bypass script exit code: $BYPASS_RESULT"
    log ""

    # Test connectivity
    log "Step 6: Testing internet connectivity..."
    log "---------------------------------------------------------------"
    if ping -c 3 -W 5 8.8.8.8 >> "$LOG_FILE" 2>&1; then
        log "✓ SUCCESS: Internet access working!"
        log "✓ Captive portal was successfully bypassed!"
    else
        log "✗ FAILED: No internet access after bypass attempt"
        log "✗ Portal bypass did not grant internet access"
    fi
fi

log ""
log "Step 7: Reconnecting to hotspot..."
log "---------------------------------------------------------------"
frey-connect-wifi "NOTHING by JK" "c9wm9kk42cnwd5g" >> "$LOG_FILE" 2>&1
RECONNECT_RESULT=$?

if [ $RECONNECT_RESULT -eq 0 ]; then
    log "✓ Reconnected to hotspot successfully"
else
    log "✗ WARNING: Failed to reconnect to hotspot"
fi

log ""
log "==============================================================================="
log "=== Test Complete ==="
log "==============================================================================="
log ""
log "Results available in:"
log "  - Log file: $LOG_FILE"
log "  - Portal HTML: $PORTAL_HTML"
log ""
log "To view results:"
log "  sudo cat $LOG_FILE"
log "  sudo cat $PORTAL_HTML"
log ""
