#!/bin/bash

# ==============================================================================
# Frey WiFi Portal Debug Script
#
# Diagnoses transparent/walled-garden portals that don't redirect HTTP
# ==============================================================================

LOG_FILE="/var/log/frey-portal-debug.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "==============================================================================="
log "=== Portal Debug Session Started ==="
log "==============================================================================="
log ""

# Step 1: Network Configuration
log "Step 1: Network Configuration"
log "---------------------------------------------------------------"
ip addr show wlan0 | tee -a "$LOG_FILE"
log ""

WLAN0_IP=$(ip -4 addr show wlan0 | grep inet | awk '{print $2}' | cut -d/ -f1)
log "wlan0 IP: $WLAN0_IP"
log ""

# Step 2: Gateway Information
log "Step 2: Gateway Information"
log "---------------------------------------------------------------"
ip route | grep default | tee -a "$LOG_FILE"
GATEWAY=$(ip route | grep default | grep wlan0 | awk '{print $3}')
log "Gateway IP: $GATEWAY"
log ""

# Test gateway connectivity
if [ -n "$GATEWAY" ]; then
    log "Testing gateway connectivity..."
    if ping -c 3 -W 5 "$GATEWAY" >> "$LOG_FILE" 2>&1; then
        log "✓ Gateway is reachable"
    else
        log "✗ Gateway is NOT reachable"
    fi
fi
log ""

# Step 3: DNS Resolution Test
log "Step 3: DNS Resolution Test"
log "---------------------------------------------------------------"
for domain in google.com microsoft.com apple.com; do
    log "Resolving $domain..."
    RESULT=$(dig +short "$domain" | head -n 1)
    log "  → $RESULT"
done | tee -a "$LOG_FILE"
log ""

# Check if all domains resolve to same IP (DNS hijacking)
GOOGLE_IP=$(dig +short google.com | head -n 1)
MICROSOFT_IP=$(dig +short microsoft.com | head -n 1)
if [ "$GOOGLE_IP" = "$MICROSOFT_IP" ]; then
    log "⚠ DNS HIJACKING DETECTED - all domains resolve to: $GOOGLE_IP"
    log "Portal is likely at: http://$GOOGLE_IP/"
    PORTAL_IP="$GOOGLE_IP"
else
    log "DNS appears normal (different IPs for different domains)"
    PORTAL_IP=""
fi
log ""

# Step 4: Try Common Portal URLs
log "Step 4: Testing Common Portal URLs"
log "---------------------------------------------------------------"

PORTAL_URLS=(
    "http://1.1.1.1"
    "http://captive.apple.com"
    "http://connectivitycheck.gstatic.com/generate_204"
    "http://clients3.google.com/generate_204"
    "http://detectportal.firefox.com"
)

if [ -n "$GATEWAY" ]; then
    PORTAL_URLS+=("http://$GATEWAY")
    PORTAL_URLS+=("http://$GATEWAY/login")
    PORTAL_URLS+=("http://$GATEWAY/portal")
fi

if [ -n "$PORTAL_IP" ]; then
    PORTAL_URLS+=("http://$PORTAL_IP")
    PORTAL_URLS+=("http://$PORTAL_IP/login")
fi

for url in "${PORTAL_URLS[@]}"; do
    log "Testing: $url"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    REDIRECT=$(curl -s -w "%{redirect_url}" -o /dev/null --max-time 5 "$url" 2>/dev/null)

    if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        log "  HTTP $HTTP_CODE"
        if [ -n "$REDIRECT" ]; then
            log "  Redirect: $REDIRECT"
        fi

        # If we get a 200 or 302, save the page
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            SAFE_NAME=$(echo "$url" | sed 's|http://||g' | sed 's|/|_|g')
            curl -s --max-time 5 "$url" > "/tmp/portal-${SAFE_NAME}.html"
            SIZE=$(wc -c < "/tmp/portal-${SAFE_NAME}.html")
            if [ "$SIZE" -gt 100 ]; then
                log "  ✓ Saved to /tmp/portal-${SAFE_NAME}.html ($SIZE bytes)"

                # Check for form elements
                FORMS=$(grep -ic '<form' "/tmp/portal-${SAFE_NAME}.html" || echo "0")
                if [ "$FORMS" -gt 0 ]; then
                    log "  ✓ Contains $FORMS form(s) - likely the portal!"
                fi
            fi
        fi
    else
        log "  No response"
    fi
done | tee -a "$LOG_FILE"
log ""

# Step 5: Test with curl following redirects
log "Step 5: Testing with Redirect Following"
log "---------------------------------------------------------------"
log "Trying http://neverssl.com with -L (follow redirects)..."
FINAL_URL=$(curl -sL -w "%{url_effective}" -o /tmp/portal-neverssl-redirect.html --max-time 10 "http://neverssl.com")
log "Final URL: $FINAL_URL"

SIZE=$(wc -c < /tmp/portal-neverssl-redirect.html)
log "Downloaded: $SIZE bytes"

if [ "$SIZE" -gt 100 ]; then
    FORMS=$(grep -ic '<form' /tmp/portal-neverssl-redirect.html || echo "0")
    log "Forms found: $FORMS"

    if [ "$FORMS" -gt 0 ]; then
        log "✓ Portal page captured to /tmp/portal-neverssl-redirect.html"

        log ""
        log "Form analysis:"
        grep -i '<form' /tmp/portal-neverssl-redirect.html | head -n 3 | tee -a "$LOG_FILE"
        log ""
        grep -iE 'checkbox|type.*submit|button.*accept|button.*agree' /tmp/portal-neverssl-redirect.html | head -n 10 | tee -a "$LOG_FILE"
    fi
fi
log ""

# Step 6: Check HTTPS behavior
log "Step 6: Testing HTTPS Requests"
log "---------------------------------------------------------------"
log "Trying https://google.com..."
curl -Ik --max-time 10 https://google.com 2>&1 | head -n 10 | tee -a "$LOG_FILE"
log ""

# Step 7: Summary
log "==============================================================================="
log "=== Debug Summary ==="
log "==============================================================================="
log ""
log "Network Info:"
log "  wlan0 IP: $WLAN0_IP"
log "  Gateway: $GATEWAY"
log ""

log "Portal Detection Results:"
if [ -n "$PORTAL_IP" ]; then
    log "  Method: DNS Hijacking"
    log "  Portal IP: $PORTAL_IP"
else
    log "  Method: Unknown (check captured HTML files)"
fi
log ""

log "Captured Files:"
ls -lh /tmp/portal-*.html 2>/dev/null | tee -a "$LOG_FILE"
log ""

log "Next Steps:"
log "1. Review captured HTML files: ls /tmp/portal-*.html"
log "2. Check largest file: ls -lhS /tmp/portal-*.html | head -n 1"
log "3. Analyze portal form: grep -i 'form\\|input\\|button' /tmp/portal-*.html"
log ""
log "Full log: $LOG_FILE"
log ""
