#!/bin/bash
# ==============================================================================
# FREY BLUETOOTH AUTO-CONNECTION DAEMON
# ==============================================================================
# Purpose: Automatically connect to Bluetooth devices based on priority
# Features:
#   - Priority-based device selection
#   - Automatic audio routing via PulseAudio
#   - MQTT status publishing for Home Assistant
#   - Automatic fallback on disconnection
# ==============================================================================

set -euo pipefail

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/etc/frey/bluetooth/device-priority.conf}"
STATE_DIR="${STATE_DIR:-/var/lib/frey/bluetooth}"
SCAN_INTERVAL="${SCAN_INTERVAL:-10}"
MQTT_BROKER="${MQTT_BROKER:-localhost}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_TOPIC="${MQTT_TOPIC:-frey/bluetooth}"

# State variables
CURRENT_DEVICE=""
CURRENT_MAC=""
CURRENT_PRIORITY=0

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | systemd-cat -t frey-bluetooth -p info
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | systemd-cat -t frey-bluetooth -p err
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# MQTT publishing
mqtt_publish() {
    local topic="$1"
    local message="$2"

    if command -v mosquitto_pub >/dev/null 2>&1; then
        mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" -t "${MQTT_TOPIC}/${topic}" -m "$message" -q 1 2>/dev/null || true
    fi
}

# Get list of known devices from config
get_known_devices() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    grep -v '^#' "$CONFIG_FILE" | grep -v '^$' || true
}

# Check if device is available (in range)
is_device_available() {
    local mac="$1"

    # Quick check via bluetoothctl
    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        return 0
    fi

    # Check if device is discoverable
    if timeout 5 bluetoothctl info "$mac" 2>/dev/null | grep -q "Device"; then
        return 0
    fi

    return 1
}

# Get current connection status
get_current_connection() {
    local connected_devices=$(bluetoothctl devices Connected 2>/dev/null || true)

    if [ -z "$connected_devices" ]; then
        CURRENT_DEVICE=""
        CURRENT_MAC=""
        CURRENT_PRIORITY=0
        return 1
    fi

    # Parse first connected device
    CURRENT_MAC=$(echo "$connected_devices" | head -n1 | awk '{print $2}')
    CURRENT_DEVICE=$(echo "$connected_devices" | head -n1 | cut -d' ' -f3-)

    # Get priority from config
    if [ -f "$CONFIG_FILE" ]; then
        CURRENT_PRIORITY=$(grep "$CURRENT_MAC" "$CONFIG_FILE" 2>/dev/null | cut -d'|' -f3 || echo "0")
    else
        CURRENT_PRIORITY=0
    fi

    return 0
}

# Connect to device
connect_device() {
    local name="$1"
    local mac="$2"
    local priority="$3"
    local profiles="$4"

    log "Attempting to connect to: $name ($mac) [Priority: $priority]"

    # Trust device (if not already trusted)
    bluetoothctl trust "$mac" >/dev/null 2>&1 || true

    # Connect
    if bluetoothctl connect "$mac" 2>&1 | grep -q "Connection successful\|already connected"; then
        log "✓ Connected to $name"

        # Wait for device to be fully ready
        sleep 3

        # Setup audio routing
        setup_audio_routing "$mac" "$profiles"

        # Update state
        CURRENT_DEVICE="$name"
        CURRENT_MAC="$mac"
        CURRENT_PRIORITY="$priority"

        # Publish to MQTT
        mqtt_publish "status/connected" "true"
        mqtt_publish "status/device_name" "$name"
        mqtt_publish "status/device_mac" "$mac"
        mqtt_publish "status/priority" "$priority"

        # Save connection history
        echo "$(date +%s)|$name|$mac|connected" >> "$STATE_DIR/connection_history.log"

        return 0
    else
        log_error "Failed to connect to $name"
        mqtt_publish "status/connected" "false"
        return 1
    fi
}

# Setup audio routing via PulseAudio
setup_audio_routing() {
    local mac="$1"
    local profiles="$2"

    log "Setting up audio routing for $mac"

    # Wait for PulseAudio to detect the device
    sleep 2

    # Find PulseAudio card for this Bluetooth device
    local pa_card=$(pactl list cards short | grep -i "bluez" | grep -i "${mac//:/_}" | awk '{print $1}' | head -n1)

    if [ -z "$pa_card" ]; then
        log "Warning: PulseAudio card not found for $mac"
        return 1
    fi

    log "Found PulseAudio card: $pa_card"

    # Set profile based on device capabilities
    if echo "$profiles" | grep -q "hsp_hs\|hfp_hf"; then
        # Device has microphone - use headset profile
        pactl set-card-profile "$pa_card" headset_head_unit 2>/dev/null || \
        pactl set-card-profile "$pa_card" a2dp_sink 2>/dev/null || true
        log "Set profile: headset (with microphone)"
    else
        # Audio output only - use A2DP
        pactl set-card-profile "$pa_card" a2dp_sink 2>/dev/null || true
        log "Set profile: A2DP (audio output only)"
    fi

    # Find sink (audio output) for this card
    local sink=$(pactl list sinks short | grep "bluez_card.${mac//:/_}" | awk '{print $1}' | head -n1)

    if [ -n "$sink" ]; then
        # Set as default sink
        pactl set-default-sink "$sink" 2>/dev/null || true
        log "Set default audio output to Bluetooth device"

        # Move existing audio streams to Bluetooth
        pactl list sink-inputs short | awk '{print $1}' | while read stream; do
            pactl move-sink-input "$stream" "$sink" 2>/dev/null || true
        done
    fi

    # Find source (microphone input) if available
    if echo "$profiles" | grep -q "hsp_hs\|hfp_hf"; then
        local source=$(pactl list sources short | grep "bluez_card.${mac//:/_}" | awk '{print $1}' | head -n1)

        if [ -n "$source" ]; then
            # Set as default source
            pactl set-default-source "$source" 2>/dev/null || true
            log "Set default microphone input to Bluetooth device"
        fi
    fi

    return 0
}

# Disconnect from device
disconnect_device() {
    local mac="$1"

    if [ -z "$mac" ]; then
        return 0
    fi

    log "Disconnecting from $mac"
    bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true

    # Reset to local audio
    local local_sink=$(pactl list sinks short | grep -v "bluez" | head -n1 | awk '{print $1}')
    if [ -n "$local_sink" ]; then
        pactl set-default-sink "$local_sink" 2>/dev/null || true
        log "Switched back to local audio output"
    fi

    # Update state
    CURRENT_DEVICE=""
    CURRENT_MAC=""
    CURRENT_PRIORITY=0

    # Publish to MQTT
    mqtt_publish "status/connected" "false"
    mqtt_publish "status/device_name" "none"

    return 0
}

# Main connection logic
process_connections() {
    get_current_connection || true

    # Read known devices and sort by priority (highest first)
    local devices=$(get_known_devices | sort -t'|' -k3 -rn)

    if [ -z "$devices" ]; then
        log "No devices configured. Run: sudo frey-bluetooth-pair"
        mqtt_publish "status/configured" "false"
        return 0
    fi

    mqtt_publish "status/configured" "true"

    # Find highest priority available device
    local best_device=""
    local best_mac=""
    local best_priority=0
    local best_profiles=""

    while IFS='|' read -r name mac priority profiles; do
        # Skip empty lines
        [ -z "$mac" ] && continue

        # Check if device is available
        if is_device_available "$mac"; then
            log "Found available device: $name ($mac) [Priority: $priority]"

            # If this is higher priority than current best, select it
            if [ "$priority" -gt "$best_priority" ]; then
                best_device="$name"
                best_mac="$mac"
                best_priority="$priority"
                best_profiles="$profiles"
            fi
        fi
    done <<< "$devices"

    # Decision logic
    if [ -z "$best_mac" ]; then
        # No devices available
        if [ -n "$CURRENT_MAC" ]; then
            log "No devices available, maintaining current connection"
        else
            log "No Bluetooth devices available"
            mqtt_publish "status/available" "false"
        fi
        return 0
    fi

    mqtt_publish "status/available" "true"

    # If no current connection, connect to best device
    if [ -z "$CURRENT_MAC" ]; then
        connect_device "$best_device" "$best_mac" "$best_priority" "$best_profiles"
        return 0
    fi

    # If already connected to best device, do nothing
    if [ "$CURRENT_MAC" = "$best_mac" ]; then
        log "Already connected to best available device: $CURRENT_DEVICE"
        return 0
    fi

    # If better device available, switch
    if [ "$best_priority" -gt "$CURRENT_PRIORITY" ]; then
        log "Found higher priority device: $best_device (Priority: $best_priority > $CURRENT_PRIORITY)"
        disconnect_device "$CURRENT_MAC"
        sleep 2
        connect_device "$best_device" "$best_mac" "$best_priority" "$best_profiles"
    else
        log "Current device has higher priority, keeping connection"
    fi
}

# Initialize
initialize() {
    log "Frey Bluetooth Auto-Connection Daemon starting..."
    log "Config file: $CONFIG_FILE"
    log "Scan interval: ${SCAN_INTERVAL}s"
    log "MQTT broker: ${MQTT_BROKER}:${MQTT_PORT}"

    # Ensure directories exist
    mkdir -p "$STATE_DIR"

    # Ensure Bluetooth is powered on
    bluetoothctl power on >/dev/null 2>&1 || true

    # Publish startup
    mqtt_publish "status/daemon" "running"
    mqtt_publish "status/scan_interval" "$SCAN_INTERVAL"

    log "✓ Daemon initialized successfully"
}

# Cleanup on exit
cleanup() {
    log "Daemon shutting down..."
    mqtt_publish "status/daemon" "stopped"
    exit 0
}

# Signal handlers
trap cleanup SIGTERM SIGINT

# Main loop
main() {
    initialize

    while true; do
        process_connections
        sleep "$SCAN_INTERVAL"
    done
}

# Run
main
