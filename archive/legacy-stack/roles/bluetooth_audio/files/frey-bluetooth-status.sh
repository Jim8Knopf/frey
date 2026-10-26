#!/bin/bash
# ==============================================================================
# FREY BLUETOOTH STATUS DISPLAY
# ==============================================================================
# Purpose: Show current Bluetooth connection status
# Usage: sudo frey-bluetooth-status
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CONFIG_FILE="/etc/frey/bluetooth/device-priority.conf"
STATE_DIR="/var/lib/frey/bluetooth"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${CYAN}Frey Bluetooth Status${NC}                                   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if Bluetooth is powered on
if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    echo -e "${RED}✗ Bluetooth adapter is powered off${NC}"
    echo ""
    echo "Run: bluetoothctl power on"
    exit 1
fi

echo -e "${GREEN}✓ Bluetooth adapter is powered on${NC}"
echo ""

# Show connected devices
echo -e "${YELLOW}━━━ Connected Devices ━━━${NC}"
CONNECTED=$(bluetoothctl devices Connected 2>/dev/null)

if [ -z "$CONNECTED" ]; then
    echo -e "${YELLOW}  No devices currently connected${NC}"
else
    echo "$CONNECTED" | while read -r line; do
        MAC=$(echo "$line" | awk '{print $2}')
        NAME=$(echo "$line" | cut -d' ' -f3-)

        # Get priority from config
        if [ -f "$CONFIG_FILE" ]; then
            PRIORITY=$(grep "$MAC" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f3 || echo "?")
        else
            PRIORITY="?"
        fi

        echo -e "${GREEN}  ● $NAME${NC}"
        echo -e "    MAC: $MAC"
        echo -e "    Priority: $PRIORITY"

        # Get connection info
        INFO=$(bluetoothctl info "$MAC" 2>/dev/null)
        if echo "$INFO" | grep -q "Battery Percentage:"; then
            BATTERY=$(echo "$INFO" | grep "Battery Percentage:" | awk '{print $3}' | tr -d '()')
            echo -e "    Battery: ${BATTERY}%"
        fi

        echo ""
    done
fi

# Show paired but not connected devices
echo -e "${YELLOW}━━━ Paired Devices (Not Connected) ━━━${NC}"
ALL_PAIRED=$(bluetoothctl devices Paired 2>/dev/null)
PAIRED_NOT_CONNECTED=$(comm -23 <(echo "$ALL_PAIRED" | sort) <(echo "$CONNECTED" | sort))

if [ -z "$PAIRED_NOT_CONNECTED" ]; then
    echo -e "  ${CYAN}(All paired devices are connected)${NC}"
else
    echo "$PAIRED_NOT_CONNECTED" | while read -r line; do
        MAC=$(echo "$line" | awk '{print $2}')
        NAME=$(echo "$line" | cut -d' ' -f3-)

        # Get priority from config
        if [ -f "$CONFIG_FILE" ]; then
            PRIORITY=$(grep "$MAC" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f3 || echo "?")
        else
            PRIORITY="?"
        fi

        echo -e "  ○ $NAME"
        echo -e "    MAC: $MAC"
        echo -e "    Priority: $PRIORITY"
        echo ""
    done
fi

# Show PulseAudio status
echo -e "${YELLOW}━━━ Audio Routing Status ━━━${NC}"

# Default sink (audio output)
DEFAULT_SINK=$(pactl info 2>/dev/null | grep "Default Sink:" | cut -d' ' -f3-)
if [ -n "$DEFAULT_SINK" ]; then
    SINK_DESC=$(pactl list sinks | grep -A 20 "Name: $DEFAULT_SINK" | grep "Description:" | cut -d':' -f2- | xargs)
    if echo "$DEFAULT_SINK" | grep -q "bluez"; then
        echo -e "${GREEN}  ♪ Audio Output: Bluetooth${NC}"
    else
        echo -e "${CYAN}  ♪ Audio Output: Local${NC}"
    fi
    echo -e "    Device: $SINK_DESC"
else
    echo -e "${RED}  ✗ No audio output configured${NC}"
fi

echo ""

# Default source (microphone input)
DEFAULT_SOURCE=$(pactl info 2>/dev/null | grep "Default Source:" | cut -d' ' -f3-)
if [ -n "$DEFAULT_SOURCE" ]; then
    SOURCE_DESC=$(pactl list sources | grep -A 20 "Name: $DEFAULT_SOURCE" | grep "Description:" | cut -d':' -f2- | xargs)
    if echo "$DEFAULT_SOURCE" | grep -q "bluez"; then
        echo -e "${GREEN}  🎤 Microphone Input: Bluetooth${NC}"
    else
        echo -e "${CYAN}  🎤 Microphone Input: Local${NC}"
    fi
    echo -e "    Device: $SOURCE_DESC"
else
    echo -e "${YELLOW}  ⚠ No microphone input configured${NC}"
fi

echo ""

# Show auto-connection daemon status
echo -e "${YELLOW}━━━ Auto-Connection Daemon ━━━${NC}"
if systemctl is-active --quiet frey-bluetooth-auto-connect; then
    echo -e "${GREEN}  ✓ Running${NC}"

    # Show recent logs
    echo -e "\n  ${CYAN}Recent Activity:${NC}"
    journalctl -u frey-bluetooth-auto-connect -n 5 --no-pager -o short-iso 2>/dev/null | \
        sed 's/^/    /' || echo "    (No recent logs)"
else
    echo -e "${RED}  ✗ Not Running${NC}"
    echo ""
    echo "  Start with: sudo systemctl start frey-bluetooth-auto-connect"
fi

echo ""
echo -e "${YELLOW}━━━ Management Commands ━━━${NC}"
echo "  Pair new device:       sudo frey-bluetooth-pair"
echo "  Force connect:         sudo frey-bluetooth-connect <MAC>"
echo "  View daemon logs:      sudo journalctl -u frey-bluetooth-auto-connect -f"
echo "  Restart daemon:        sudo systemctl restart frey-bluetooth-auto-connect"
echo ""
