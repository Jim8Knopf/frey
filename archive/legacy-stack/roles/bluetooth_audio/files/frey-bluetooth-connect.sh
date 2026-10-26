#!/bin/bash
# ==============================================================================
# FREY BLUETOOTH MANUAL CONNECTION MANAGER
# ==============================================================================
# Purpose: Manually connect/disconnect Bluetooth devices
# Usage: sudo frey-bluetooth-connect [MAC_ADDRESS|disconnect]
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="/etc/frey/bluetooth/device-priority.conf"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Show usage
show_usage() {
    echo -e "${BLUE}Frey Bluetooth Connection Manager${NC}"
    echo ""
    echo "Usage:"
    echo "  sudo frey-bluetooth-connect <MAC_ADDRESS>    # Connect to device"
    echo "  sudo frey-bluetooth-connect disconnect       # Disconnect all"
    echo "  sudo frey-bluetooth-connect list             # List paired devices"
    echo ""
}

# List paired devices
list_devices() {
    echo -e "${YELLOW}Paired Devices:${NC}"
    echo ""

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}No devices configured${NC}"
        echo "Run: sudo frey-bluetooth-pair"
        return 1
    fi

    local i=1
    while IFS='|' read -r name mac priority profiles; do
        [ -z "$mac" ] && continue
        [[ "$name" =~ ^# ]] && continue

        # Check if connected
        if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
            STATUS="${GREEN}[Connected]${NC}"
        else
            STATUS="${YELLOW}[Available]${NC}"
        fi

        echo -e "  $i. $name $STATUS"
        echo -e "     MAC: $mac | Priority: $priority"
        echo ""
        ((i++))
    done < "$CONFIG_FILE"
}

# Connect to device
connect_device() {
    local mac="$1"

    echo -e "${YELLOW}→ Connecting to $mac...${NC}"

    # Check if device is paired
    if ! bluetoothctl devices Paired | grep -q "$mac"; then
        echo -e "${RED}✗ Device not paired${NC}"
        echo "Run: sudo frey-bluetooth-pair"
        return 1
    fi

    # Trust device
    bluetoothctl trust "$mac" >/dev/null 2>&1 || true

    # Connect
    if bluetoothctl connect "$mac"; then
        echo -e "${GREEN}✓ Connected successfully${NC}"

        # Wait for audio to be ready
        sleep 3

        # Setup audio routing
        local pa_card=$(pactl list cards short | grep -i "bluez" | grep -i "${mac//:/_}" | awk '{print $1}' | head -n1)

        if [ -n "$pa_card" ]; then
            # Try headset profile first (includes mic), fallback to A2DP
            pactl set-card-profile "$pa_card" headset_head_unit 2>/dev/null || \
            pactl set-card-profile "$pa_card" a2dp_sink 2>/dev/null || true

            # Set as default sink
            local sink=$(pactl list sinks short | grep "bluez_card.${mac//:/_}" | awk '{print $1}' | head -n1)
            if [ -n "$sink" ]; then
                pactl set-default-sink "$sink" 2>/dev/null || true
                echo -e "${GREEN}✓ Audio routed to Bluetooth device${NC}"
            fi
        fi

        return 0
    else
        echo -e "${RED}✗ Connection failed${NC}"
        return 1
    fi
}

# Disconnect device
disconnect_device() {
    local mac="$1"

    echo -e "${YELLOW}→ Disconnecting from $mac...${NC}"

    if bluetoothctl disconnect "$mac" 2>&1 | grep -q "Successful"; then
        echo -e "${GREEN}✓ Disconnected successfully${NC}"

        # Switch back to local audio
        local local_sink=$(pactl list sinks short | grep -v "bluez" | head -n1 | awk '{print $1}')
        if [ -n "$local_sink" ]; then
            pactl set-default-sink "$local_sink" 2>/dev/null || true
            echo -e "${GREEN}✓ Switched to local audio${NC}"
        fi

        return 0
    else
        echo -e "${YELLOW}⚠ Device may already be disconnected${NC}"
        return 0
    fi
}

# Disconnect all devices
disconnect_all() {
    echo -e "${YELLOW}→ Disconnecting all Bluetooth devices...${NC}"

    local connected=$(bluetoothctl devices Connected 2>/dev/null)

    if [ -z "$connected" ]; then
        echo -e "${YELLOW}No devices connected${NC}"
        return 0
    fi

    echo "$connected" | while read -r line; do
        local mac=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | cut -d' ' -f3-)

        echo -e "  Disconnecting: $name"
        disconnect_device "$mac" >/dev/null 2>&1 || true
    done

    echo -e "${GREEN}✓ All devices disconnected${NC}"
}

# Main
main() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    case "$1" in
        list)
            list_devices
            ;;
        disconnect)
            if [ $# -eq 1 ]; then
                disconnect_all
            else
                disconnect_device "$2"
            fi
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            # Assume it's a MAC address
            if [[ "$1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                connect_device "$1"
            else
                echo -e "${RED}Error: Invalid MAC address format${NC}"
                echo "Expected format: AA:BB:CC:DD:EE:FF"
                exit 1
            fi
            ;;
    esac
}

main "$@"
