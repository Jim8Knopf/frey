#!/bin/bash
# ==============================================================================
# FREY BLUETOOTH PAIRING HELPER
# ==============================================================================
# Purpose: Interactive wizard for pairing Bluetooth audio devices
# Usage: sudo frey-bluetooth-pair
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_FILE="/etc/frey/bluetooth/device-priority.conf"
STATE_DIR="/var/lib/frey/bluetooth"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo frey-bluetooth-pair"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Frey Bluetooth Pairing Wizard${NC}                             ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure Bluetooth is powered on
echo -e "${YELLOW}→ Powering on Bluetooth adapter...${NC}"
bluetoothctl power on >/dev/null 2>&1
bluetoothctl discoverable on >/dev/null 2>&1
bluetoothctl pairable on >/dev/null 2>&1
sleep 1
echo -e "${GREEN}✓ Bluetooth adapter ready${NC}"
echo ""

# Instructions
echo -e "${YELLOW}Instructions:${NC}"
echo "1. Put your Bluetooth device in pairing mode"
echo "2. Wait for it to appear in the scan results"
echo "3. Select the device to pair"
echo ""
echo -e "${YELLOW}Supported devices:${NC}"
echo "  • Bluetooth headphones with microphone"
echo "  • Car audio systems (A2DP)"
echo "  • Bluetooth speakers"
echo "  • Bluetooth headsets"
echo ""

read -p "Press Enter when your device is in pairing mode..."

# Scan for devices
echo ""
echo -e "${YELLOW}→ Scanning for Bluetooth devices... (10 seconds)${NC}"

# Start scanning
bluetoothctl --timeout 10 scan on &
SCAN_PID=$!

# Wait for scan to complete
sleep 10

# Get list of devices
DEVICES=$(bluetoothctl devices | grep "Device")

if [ -z "$DEVICES" ]; then
    echo -e "${RED}✗ No devices found${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  • Make sure your device is in pairing mode"
    echo "  • Move the device closer to the Raspberry Pi"
    echo "  • Try restarting your Bluetooth device"
    exit 1
fi

# Display found devices
echo -e "${GREEN}✓ Found devices:${NC}"
echo ""

IFS=$'\n'
DEVICE_ARRAY=($DEVICES)
unset IFS

for i in "${!DEVICE_ARRAY[@]}"; do
    DEVICE_LINE="${DEVICE_ARRAY[$i]}"
    MAC=$(echo "$DEVICE_LINE" | awk '{print $2}')
    NAME=$(echo "$DEVICE_LINE" | cut -d' ' -f3-)
    echo "  $((i+1)). $NAME ($MAC)"
done

echo ""
read -p "Select device number to pair (1-${#DEVICE_ARRAY[@]}): " SELECTION

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#DEVICE_ARRAY[@]}" ]; then
    echo -e "${RED}✗ Invalid selection${NC}"
    exit 1
fi

# Get selected device
SELECTED_INDEX=$((SELECTION-1))
DEVICE_LINE="${DEVICE_ARRAY[$SELECTED_INDEX]}"
MAC=$(echo "$DEVICE_LINE" | awk '{print $2}')
NAME=$(echo "$DEVICE_LINE" | cut -d' ' -f3-)

echo ""
echo -e "${YELLOW}→ Pairing with: ${GREEN}$NAME${NC}"
echo -e "   MAC Address: ${BLUE}$MAC${NC}"
echo ""

# Pair device
echo -e "${YELLOW}→ Pairing...${NC}"
if ! echo -e "pair $MAC\nyes\n" | bluetoothctl; then
    echo -e "${RED}✗ Pairing failed${NC}"
    exit 1
fi
sleep 2

# Trust device
echo -e "${YELLOW}→ Trusting device...${NC}"
bluetoothctl trust "$MAC" >/dev/null 2>&1
sleep 1

# Connect device
echo -e "${YELLOW}→ Connecting...${NC}"
if bluetoothctl connect "$MAC" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected successfully${NC}"
else
    echo -e "${YELLOW}⚠ Connection pending (device may need to be turned on)${NC}"
fi

echo ""

# Ask for device type to determine priority
echo -e "${YELLOW}What type of device is this?${NC}"
echo "  1. Headphones / Headset (Priority: 100)"
echo "  2. Car Audio System (Priority: 50)"
echo "  3. Portable Speaker (Priority: 30)"
echo "  4. Custom priority"
echo ""
read -p "Select device type (1-4): " DEVICE_TYPE

case "$DEVICE_TYPE" in
    1)
        PRIORITY=100
        PROFILES="a2dp_sink,hsp_hs"
        ;;
    2)
        PRIORITY=50
        PROFILES="a2dp_sink"
        ;;
    3)
        PRIORITY=30
        PROFILES="a2dp_sink"
        ;;
    4)
        read -p "Enter priority (0-100): " PRIORITY
        echo "Profiles: a2dp_sink (audio out), hsp_hs (mic), hfp_hf (hands-free)"
        read -p "Enter profiles (comma-separated): " PROFILES
        ;;
    *)
        echo -e "${YELLOW}⚠ Invalid selection, using default (Priority: 50, A2DP only)${NC}"
        PRIORITY=50
        PROFILES="a2dp_sink"
        ;;
esac

# Save to configuration
echo ""
echo -e "${YELLOW}→ Saving configuration...${NC}"

mkdir -p "$(dirname "$CONFIG_FILE")"
mkdir -p "$STATE_DIR"

# Add device to config (append if not exists)
if grep -q "$MAC" "$CONFIG_FILE" 2>/dev/null; then
    # Update existing entry
    sed -i "/^.*|$MAC|/d" "$CONFIG_FILE"
fi

echo "$NAME|$MAC|$PRIORITY|$PROFILES" >> "$CONFIG_FILE"

# Save device info
echo "$NAME|$MAC|$PRIORITY|$PROFILES" > "$STATE_DIR/${MAC}.conf"

echo -e "${GREEN}✓ Configuration saved${NC}"
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}Pairing Complete!${NC}                                        ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Device:${NC}    $NAME"
echo -e "${GREEN}MAC:${NC}       $MAC"
echo -e "${GREEN}Priority:${NC}  $PRIORITY"
echo -e "${GREEN}Profiles:${NC}  $PROFILES"
echo ""
echo -e "${YELLOW}What happens now:${NC}"
echo "  • Device will auto-connect when in range"
echo "  • Audio will automatically route to this device"
echo "  • Check status: sudo frey-bluetooth-status"
echo "  • View logs: sudo journalctl -u frey-bluetooth-auto-connect -f"
echo ""

# Restart auto-connection service
if systemctl is-active --quiet frey-bluetooth-auto-connect; then
    echo -e "${YELLOW}→ Restarting auto-connection service...${NC}"
    systemctl restart frey-bluetooth-auto-connect
    echo -e "${GREEN}✓ Service restarted${NC}"
fi

echo ""
echo -e "${GREEN}✓ Done! Your device is ready to use.${NC}"
echo ""
