# Bluetooth Audio Setup Guide

Complete guide for setting up automatic Bluetooth audio connectivity on Frey.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Setup](#quick-setup)
- [Configuration](#configuration)
- [Management Commands](#management-commands)
- [Home Assistant Integration](#home-assistant-integration)
- [Voice Assistant Integration](#voice-assistant-integration)
- [Troubleshooting](#troubleshooting)
- [Use Cases](#use-cases)

---

## Overview

The Frey Bluetooth Audio system provides automatic, priority-based Bluetooth device connectivity with seamless audio routing. Once configured, your devices will automatically connect when in range and route all audio (including voice assistant TTS and STT) through your preferred Bluetooth device.

**Architecture:**
- **BlueZ** - Linux Bluetooth protocol stack
- **PulseAudio** - Audio routing and device management
- **Auto-connection daemon** - Priority-based device selection
- **MQTT integration** - Home Assistant monitoring and control
- **Wyoming protocol support** - Voice assistant audio routing

## Features

### Automatic Connection
- Devices automatically connect when in range
- Priority-based selection (headphones > car radio > speakers)
- Automatic fallback when primary device disconnects
- Seamless switching between devices

### Audio Routing
- All audio output automatically routes to Bluetooth speakers
- Microphone input from Bluetooth headsets
- Voice assistant TTS plays through Bluetooth
- Voice commands captured from Bluetooth microphone
- Media playback (Jellyfin, Audiobookshelf) routes to Bluetooth

### Management
- Interactive pairing wizard
- Status monitoring commands
- Manual connection control
- Home Assistant dashboard integration

### Smart Features
- Connection retry logic with backoff
- Audio profile selection (A2DP, HSP, HFP)
- Battery level monitoring (when supported)
- Automatic audio stream migration
- Falls back to local audio when disconnected

---

## Prerequisites

### Hardware
- Raspberry Pi 5 (or compatible) with Bluetooth adapter
- Bluetooth audio device(s):
  - Headphones/headset (with or without microphone)
  - Car audio system with Bluetooth
  - Portable Bluetooth speaker

### Software
- Frey base system installed
- Home Assistant running (optional, for dashboard integration)
- MQTT broker configured (for Home Assistant integration)
- Voice assistant services (Piper, Whisper) if using voice features

---

## Quick Setup

### 1. Enable Bluetooth Audio

Edit `group_vars/all/main.yml`:

```yaml
features:
  bluetooth_audio: true

bluetooth_audio:
  enabled: true
  auto_connect: true
  scan_interval: 10
```

### 2. Deploy Bluetooth Role

```bash
# Deploy only Bluetooth components
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags bluetooth

# Or deploy entire system
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### 3. Pair Your Devices

SSH to your Raspberry Pi and run the pairing wizard:

```bash
sudo frey-bluetooth-pair
```

**The wizard will:**
1. Scan for available Bluetooth devices (10 seconds)
2. Display found devices with numbered list
3. Prompt you to select a device
4. Automatically pair, trust, and connect
5. Assign smart priority based on device type
6. Save configuration and restart auto-connection service

**Priority assignment:**
- Headphones/Headset: Priority 100 (includes microphone)
- Car Audio: Priority 50 (audio only)
- Portable Speaker: Priority 30 (audio only)

### 4. Verify Operation

```bash
# Check connection status
sudo frey-bluetooth-status

# View daemon logs
sudo journalctl -u frey-bluetooth-auto-connect -f
```

**You're done!** Your devices will now automatically connect when in range.

---

## Configuration

### Full Configuration Options

Edit `group_vars/all/main.yml`:

```yaml
bluetooth_audio:
  # Enable/disable entire system
  enabled: true

  # Automatic connection settings
  auto_connect: true           # Enable auto-connection daemon
  scan_interval: 10            # Seconds between device scans

  # Paired devices (populated by pairing wizard)
  devices:
    - name: "My Headphones"
      mac_address: "AA:BB:CC:DD:EE:FF"
      priority: 100
      profiles: ["a2dp_sink", "hsp_hs"]  # Audio output + microphone

    - name: "Car Radio"
      mac_address: "11:22:33:44:55:66"
      priority: 50
      profiles: ["a2dp_sink"]              # Audio output only

  # Audio routing behavior
  audio_routing:
    default_sink: "bluetooth"    # Route audio to Bluetooth by default
    fallback_to_local: true      # Use local audio when disconnected
    auto_switch: true            # Automatically switch to newly connected devices

  # Home Assistant integration
  homeassistant:
    integration: true            # Enable MQTT sensors
    tts_to_bluetooth: true       # Route TTS to Bluetooth
    voice_from_bluetooth: true   # Use Bluetooth microphone for voice commands
    mqtt_topic: "frey/bluetooth" # MQTT topic prefix

  # Connection behavior
  connection:
    retry_attempts: 3            # Connection retry attempts
    retry_delay: 5               # Seconds between retries
    connection_timeout: 15       # Seconds to wait for connection
```

### Redeploy After Configuration Changes

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags bluetooth
```

---

## Management Commands

### Pairing Wizard

Interactive wizard for pairing new devices:

```bash
sudo frey-bluetooth-pair
```

**Features:**
- Automatic device discovery
- Numbered device selection
- Smart priority assignment
- Profile configuration
- Automatic service restart

### Status Check

View current Bluetooth status:

```bash
sudo frey-bluetooth-status
```

**Displays:**
- Connected devices with battery level
- Paired devices and priorities
- Current audio routing (Bluetooth vs Local)
- Daemon status and recent logs

### Manual Connection

Manually connect or disconnect devices:

```bash
# List paired devices
sudo frey-bluetooth-connect list

# Connect to specific device
sudo frey-bluetooth-connect AA:BB:CC:DD:EE:FF

# Disconnect all devices
sudo frey-bluetooth-connect disconnect

# Disconnect specific device
sudo frey-bluetooth-connect disconnect AA:BB:CC:DD:EE:FF
```

### Service Management

Control the auto-connection daemon:

```bash
# Check daemon status
sudo systemctl status frey-bluetooth-auto-connect

# Start daemon
sudo systemctl start frey-bluetooth-auto-connect

# Stop daemon
sudo systemctl stop frey-bluetooth-auto-connect

# Restart daemon
sudo systemctl restart frey-bluetooth-auto-connect

# View real-time logs
sudo journalctl -u frey-bluetooth-auto-connect -f

# View recent logs
sudo journalctl -u frey-bluetooth-auto-connect -n 50
```

### Bluetooth System Services

```bash
# Restart Bluetooth service
sudo systemctl restart bluetooth

# Restart PulseAudio
sudo systemctl restart pulseaudio

# Check BlueZ status
sudo bluetoothctl info

# List all Bluetooth devices
bluetoothctl devices
```

---

## Home Assistant Integration

### Automatic Setup

The Bluetooth role automatically creates Home Assistant integration at:
```
/opt/frey/appdata/homeassistant/config/packages/bluetooth.yaml
```

### Available Entities

**Sensors:**
- `sensor.frey_bluetooth_device` - Connected device name
- `sensor.frey_bluetooth_device_mac` - Device MAC address
- `sensor.frey_bluetooth_device_priority` - Device priority
- `sensor.frey_bluetooth_scan_interval` - Scan interval
- `sensor.frey_bluetooth_status` - Connection status text

**Binary Sensors:**
- `binary_sensor.frey_bluetooth_connected` - Connection status
- `binary_sensor.frey_bluetooth_available` - Devices available
- `binary_sensor.frey_bluetooth_daemon` - Daemon running status
- `binary_sensor.frey_bluetooth_configured` - Devices configured

**Controls:**
- `button.frey_bluetooth_force_rescan` - Trigger manual rescan

### Automations

**Pre-configured automations:**

1. **Connection notification:**
   ```yaml
   - alias: "Frey: Bluetooth Device Connected"
     trigger:
       - platform: state
         entity_id: binary_sensor.frey_bluetooth_connected
         to: "on"
     action:
       - service: notify.persistent_notification
         data:
           message: "Connected to {{ states('sensor.frey_bluetooth_device') }}"
   ```

2. **Disconnection notification:**
   ```yaml
   - alias: "Frey: Bluetooth Device Disconnected"
     trigger:
       - platform: state
         entity_id: binary_sensor.frey_bluetooth_connected
         to: "off"
     action:
       - service: notify.persistent_notification
         data:
           message: "Bluetooth audio device disconnected"
   ```

3. **TTS routing notification:**
   ```yaml
   - alias: "Frey: Route TTS to Bluetooth"
     trigger:
       - platform: state
         entity_id: binary_sensor.frey_bluetooth_connected
         to: "on"
     action:
       - service: notify.persistent_notification
         data:
           message: "TTS will now play through {{ states('sensor.frey_bluetooth_device') }}"
   ```

### Dashboard Card

Add this card to your Lovelace dashboard:

```yaml
type: entities
title: Frey Bluetooth Audio
entities:
  - entity: binary_sensor.frey_bluetooth_connected
    name: Connection Status
  - entity: sensor.frey_bluetooth_device
    name: Connected Device
  - entity: sensor.frey_bluetooth_status
    name: Status
  - type: divider
  - entity: button.frey_bluetooth_force_rescan
    name: Force Rescan
  - type: divider
  - entity: binary_sensor.frey_bluetooth_daemon
    name: Auto-Connection Daemon
  - entity: sensor.frey_bluetooth_scan_interval
    name: Scan Interval
```

### MQTT Topics

**Status topics (published by daemon):**
- `frey/bluetooth/status/connected` - "true" or "false"
- `frey/bluetooth/status/available` - "true" or "false"
- `frey/bluetooth/status/daemon` - "running" or "stopped"
- `frey/bluetooth/status/configured` - "true" or "false"
- `frey/bluetooth/status/device_name` - Connected device name
- `frey/bluetooth/status/device_mac` - Device MAC address
- `frey/bluetooth/status/priority` - Device priority number
- `frey/bluetooth/status/scan_interval` - Scan interval in seconds

**Control topics (subscribed by daemon):**
- `frey/bluetooth/control/rescan` - Send "true" to trigger rescan

---

## Voice Assistant Integration

The Bluetooth system automatically integrates with Frey's voice assistant services.

### Wyoming Protocol Support

**Piper TTS (Text-to-Speech):**
- TTS announcements automatically play through Bluetooth speakers
- Falls back to local audio when disconnected
- No configuration required

**Whisper STT (Speech-to-Text):**
- Voice commands captured from Bluetooth microphone
- Only works with devices that have microphone (HSP/HFP profile)
- Requires headset with priority 100

### Audio Routing Script

The system includes an automatic audio routing script:
```
/usr/local/bin/voice-assistant-audio-router
```

**Called automatically by:**
- Home Assistant voice pipeline
- Piper TTS service
- Wyoming Whisper service

**Behavior:**
1. Checks for active Bluetooth audio sink
2. Routes TTS output to Bluetooth if available
3. Checks for Bluetooth microphone source
4. Routes voice input from Bluetooth if available
5. Falls back to local devices when Bluetooth unavailable

### Testing Voice Integration

```bash
# Test TTS output
echo "Hello, this is a test" | piper --model en_US-lessac-medium --output-raw | \
  aplay -r 22050 -f S16_LE -c 1

# Check current audio routing
pactl list sinks short | grep bluez     # Bluetooth speakers
pactl list sources short | grep bluez   # Bluetooth microphone

# Test microphone input
arecord -d 5 -f cd test.wav
aplay test.wav
```

---

## Troubleshooting

### Device Won't Pair

**Symptoms:** Pairing wizard fails to pair device

**Solutions:**
1. **Put device in pairing mode** - Most devices require holding power button or pairing button
2. **Remove old pairing** - If device was previously paired, forget it from device settings
3. **Check Bluetooth service:**
   ```bash
   sudo systemctl status bluetooth
   sudo systemctl restart bluetooth
   ```
4. **Check device visibility:**
   ```bash
   bluetoothctl scan on
   # Wait 10 seconds, look for your device
   bluetoothctl scan off
   ```
5. **Manually pair:**
   ```bash
   bluetoothctl
   power on
   agent on
   default-agent
   scan on
   # Note device MAC address
   pair AA:BB:CC:DD:EE:FF
   trust AA:BB:CC:DD:EE:FF
   connect AA:BB:CC:DD:EE:FF
   ```

### Device Paired But Won't Connect

**Symptoms:** Device shows as paired but auto-connection fails

**Solutions:**
1. **Check daemon status:**
   ```bash
   sudo systemctl status frey-bluetooth-auto-connect
   sudo journalctl -u frey-bluetooth-auto-connect -n 50
   ```
2. **Verify device in config:**
   ```bash
   cat /etc/frey/bluetooth/device-priority.conf
   ```
3. **Manually test connection:**
   ```bash
   sudo frey-bluetooth-connect AA:BB:CC:DD:EE:FF
   ```
4. **Check device range** - Bluetooth range is ~10 meters, walls reduce range
5. **Restart Bluetooth stack:**
   ```bash
   sudo systemctl restart bluetooth
   sudo systemctl restart frey-bluetooth-auto-connect
   ```

### No Audio Output to Bluetooth

**Symptoms:** Device connected but no sound

**Solutions:**
1. **Check audio routing:**
   ```bash
   pactl list sinks short
   pactl list sinks | grep -A 10 bluez
   ```
2. **Check default sink:**
   ```bash
   pactl get-default-sink
   # Should show "bluez_sink.XX_XX_XX_XX_XX_XX"
   ```
3. **Manually set Bluetooth as default:**
   ```bash
   # Get sink name
   SINK=$(pactl list sinks short | grep bluez | awk '{print $2}' | head -n1)
   # Set as default
   pactl set-default-sink "$SINK"
   ```
4. **Check PulseAudio card profile:**
   ```bash
   pactl list cards
   # Look for bluez_card, check active profile
   ```
5. **Switch to A2DP profile:**
   ```bash
   CARD=$(pactl list cards short | grep bluez | awk '{print $1}' | head -n1)
   pactl set-card-profile "$CARD" a2dp_sink
   ```
6. **Restart PulseAudio:**
   ```bash
   sudo systemctl restart pulseaudio
   ```

### Microphone Not Working

**Symptoms:** Can't use Bluetooth microphone for voice commands

**Solutions:**
1. **Verify device has microphone** - Only headsets support microphone (HSP/HFP profile)
2. **Check audio profile:**
   ```bash
   pactl list cards | grep -A 20 bluez
   # Look for "Active Profile"
   # Should be "headset_head_unit" or "handsfree_head_unit"
   ```
3. **Switch to headset profile:**
   ```bash
   CARD=$(pactl list cards short | grep bluez | awk '{print $1}' | head -n1)
   pactl set-card-profile "$CARD" headset_head_unit
   ```
4. **Check default source:**
   ```bash
   pactl get-default-source
   # Should show "bluez_source.XX_XX_XX_XX_XX_XX"
   ```
5. **Manually set Bluetooth microphone:**
   ```bash
   SOURCE=$(pactl list sources short | grep bluez | grep -v monitor | awk '{print $2}' | head -n1)
   pactl set-default-source "$SOURCE"
   ```
6. **Test microphone:**
   ```bash
   arecord -d 5 -f cd test.wav
   aplay test.wav
   ```

### Device Connects But Immediately Disconnects

**Symptoms:** Device connects for 1-2 seconds then disconnects

**Solutions:**
1. **Check device battery** - Low battery causes connection issues
2. **Check for multiple hosts** - Device might be trying to connect to multiple hosts
3. **Trust the device:**
   ```bash
   bluetoothctl trust AA:BB:CC:DD:EE:FF
   ```
4. **Check Bluetooth logs:**
   ```bash
   sudo journalctl -u bluetooth -f
   # Connect device and watch for errors
   ```
5. **Disable other Bluetooth hosts** - Turn off Bluetooth on phones/computers that previously connected to device
6. **Remove and re-pair:**
   ```bash
   bluetoothctl remove AA:BB:CC:DD:EE:FF
   sudo frey-bluetooth-pair
   ```

### Wrong Device Connects

**Symptoms:** Lower priority device connects instead of preferred device

**Solutions:**
1. **Check device priorities:**
   ```bash
   cat /etc/frey/bluetooth/device-priority.conf
   ```
2. **Adjust priorities** - Higher number = higher priority:
   ```bash
   sudo nano /etc/frey/bluetooth/device-priority.conf
   # Change priority values
   # Recommended: Headphones=100, Car=50, Speaker=30
   ```
3. **Restart daemon:**
   ```bash
   sudo systemctl restart frey-bluetooth-auto-connect
   ```
4. **Force specific device:**
   ```bash
   sudo frey-bluetooth-connect AA:BB:CC:DD:EE:FF
   ```
5. **Check scan interval** - Increase for slower switching:
   ```yaml
   bluetooth_audio:
     scan_interval: 30  # Check every 30 seconds instead of 10
   ```

### Home Assistant Not Showing Bluetooth Entities

**Symptoms:** Bluetooth sensors not appearing in Home Assistant

**Solutions:**
1. **Check MQTT integration:**
   ```bash
   # Check if MQTT broker is running
   sudo systemctl status mosquitto

   # Test MQTT connection
   mosquitto_sub -h localhost -t 'frey/bluetooth/#' -v
   ```
2. **Verify configuration file:**
   ```bash
   ls -la /opt/frey/appdata/homeassistant/config/packages/
   cat /opt/frey/appdata/homeassistant/config/packages/bluetooth.yaml
   ```
3. **Enable packages in configuration.yaml:**
   ```yaml
   homeassistant:
     packages: !include_dir_named packages/
   ```
4. **Restart Home Assistant:**
   ```bash
   docker restart homeassistant
   ```
5. **Check Home Assistant logs:**
   ```bash
   docker logs homeassistant | grep -i bluetooth
   ```
6. **Manually reload MQTT:**
   - Go to Settings → Devices & Services → MQTT
   - Click "Reload" button

### Daemon Not Starting

**Symptoms:** `systemctl status frey-bluetooth-auto-connect` shows failed

**Solutions:**
1. **Check service logs:**
   ```bash
   sudo journalctl -u frey-bluetooth-auto-connect -n 100 --no-pager
   ```
2. **Verify script exists:**
   ```bash
   ls -la /usr/local/bin/frey-bluetooth-daemon
   ```
3. **Check script permissions:**
   ```bash
   sudo chmod +x /usr/local/bin/frey-bluetooth-daemon
   ```
4. **Verify dependencies:**
   ```bash
   which bluetoothctl pactl mosquitto_pub
   ```
5. **Manually run daemon:**
   ```bash
   sudo /usr/local/bin/frey-bluetooth-daemon
   # Watch for errors
   ```
6. **Redeploy Bluetooth role:**
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags bluetooth
   ```

### Audio Quality Issues

**Symptoms:** Choppy audio, stuttering, or poor quality

**Solutions:**
1. **Check Bluetooth signal strength** - Move closer to Raspberry Pi
2. **Reduce WiFi interference** - 2.4GHz WiFi interferes with Bluetooth
3. **Verify A2DP profile:**
   ```bash
   pactl list cards | grep -A 20 bluez
   # Active Profile should be "a2dp_sink" for best quality
   ```
4. **Adjust PulseAudio buffer settings** in `roles/bluetooth_audio/templates/pulseaudio-daemon.conf.j2`:
   ```ini
   default-fragment-size-msec = 50  # Increase from 25
   ```
5. **Disable WiFi during testing:**
   ```bash
   sudo iwconfig wlan0 txpower off
   # Test audio quality
   sudo iwconfig wlan0 txpower auto
   ```
6. **Check for USB interference** - USB 3.0 can interfere with Bluetooth

---

## Use Cases

### Use Case 1: Headphones for Voice Assistant

**Scenario:** You want voice commands to use your Bluetooth headset microphone and TTS responses to play through headphones.

**Setup:**
1. Pair headphones with priority 100:
   ```bash
   sudo frey-bluetooth-pair
   # Select your headphones
   # Wizard automatically assigns priority 100 and HSP profile
   ```

2. Verify voice assistant integration:
   ```yaml
   bluetooth_audio:
     homeassistant:
       tts_to_bluetooth: true
       voice_from_bluetooth: true
   ```

3. Test voice command:
   - Say wake word
   - Ask question
   - Response plays through headphones

**Expected behavior:**
- Headphones auto-connect when turned on
- Voice commands use headphone microphone
- TTS responses play through headphones
- Falls back to local audio when headphones disconnected

### Use Case 2: Car Radio Audio

**Scenario:** You want media playback and audiobooks to play through car radio when driving.

**Setup:**
1. Pair car radio with priority 50:
   ```bash
   sudo frey-bluetooth-pair
   # Select your car radio
   # Wizard automatically assigns priority 50 and A2DP profile
   ```

2. Start media playback:
   - Open Jellyfin app
   - Start movie or music
   - Audio routes to car speakers

**Expected behavior:**
- Car radio auto-connects when car started
- All audio plays through car speakers
- Disconnects when car turned off
- Falls back to local audio or headphones

### Use Case 3: Multiple Devices with Priority

**Scenario:** You have headphones, car radio, and portable speaker. You want headphones to always take priority.

**Setup:**
1. Pair all devices:
   ```bash
   sudo frey-bluetooth-pair
   # Pair headphones (priority 100)
   # Pair car radio (priority 50)
   # Pair speaker (priority 30)
   ```

2. Verify configuration:
   ```bash
   cat /etc/frey/bluetooth/device-priority.conf
   ```

**Expected behavior:**
- If headphones available → connects to headphones
- If only car radio available → connects to car
- If only speaker available → connects to speaker
- If headphones turn on while car connected → switches to headphones
- If headphones turn off while connected → switches to next best device

### Use Case 4: Manual Control

**Scenario:** You want to manually control which device connects.

**Setup:**
1. Stop auto-connection daemon:
   ```bash
   sudo systemctl stop frey-bluetooth-auto-connect
   ```

2. Manually connect devices:
   ```bash
   # List available devices
   sudo frey-bluetooth-connect list

   # Connect to specific device
   sudo frey-bluetooth-connect AA:BB:CC:DD:EE:FF

   # Disconnect when done
   sudo frey-bluetooth-connect disconnect
   ```

3. Re-enable auto-connection:
   ```bash
   sudo systemctl start frey-bluetooth-auto-connect
   ```

### Use Case 5: Home Assistant Automation

**Scenario:** You want to trigger automations based on Bluetooth connection status.

**Setup:**
1. Create automation in Home Assistant:
   ```yaml
   automation:
     - alias: "Welcome Home Audio"
       trigger:
         - platform: state
           entity_id: binary_sensor.frey_bluetooth_connected
           to: "on"
         - platform: template
           value_template: "{{ is_state_attr('sensor.frey_bluetooth_device', 'state', 'Car Radio') }}"
       action:
         - service: media_player.play_media
           target:
             entity_id: media_player.jellyfin
           data:
             media_content_type: playlist
             media_content_id: "welcome_home_playlist"
   ```

2. Monitor connection in dashboard:
   - View which device is connected
   - See connection status
   - Force manual rescan if needed

**Expected behavior:**
- Automation triggers when car connects
- Playlist starts playing through car speakers
- Dashboard shows current connection status

---

## Advanced Configuration

### Custom Device Profiles

Edit device configuration manually:

```bash
sudo nano /etc/frey/bluetooth/device-priority.conf
```

**Format:**
```
DEVICE_NAME|MAC_ADDRESS|PRIORITY|PROFILES
```

**Available profiles:**
- `a2dp_sink` - High-quality audio output (music, media)
- `hsp_hs` - Headset profile (lower quality, includes microphone)
- `hfp_hf` - Hands-free profile (phone calls, includes microphone)

**Examples:**
```
Premium Headphones|AA:BB:CC:DD:EE:FF|100|a2dp_sink,hsp_hs
Car Radio|11:22:33:44:55:66|50|a2dp_sink
Portable Speaker|22:33:44:55:66:77|30|a2dp_sink
Gaming Headset|33:44:55:66:77:88|90|hsp_hs
```

### Disable Auto-Connection

If you prefer manual control:

```yaml
bluetooth_audio:
  enabled: true
  auto_connect: false  # Disable daemon
```

Or temporarily:
```bash
sudo systemctl stop frey-bluetooth-auto-connect
sudo systemctl disable frey-bluetooth-auto-connect
```

### Custom Scan Interval

Adjust how frequently the daemon checks for devices:

```yaml
bluetooth_audio:
  scan_interval: 30  # Check every 30 seconds instead of 10
```

**Considerations:**
- Lower interval (5-10s) - Faster device switching, more CPU usage
- Higher interval (30-60s) - Slower switching, less CPU usage, longer battery life

### Disable Home Assistant Integration

If not using Home Assistant:

```yaml
bluetooth_audio:
  homeassistant:
    integration: false
```

### Disable Voice Assistant Integration

If not using voice assistant features:

```yaml
bluetooth_audio:
  homeassistant:
    tts_to_bluetooth: false
    voice_from_bluetooth: false
```

---

## Related Documentation

- **[USER_GUIDE.md](USER_GUIDE.md)** - Complete Frey system documentation
- **[QUICK_SETUP.md](QUICK_SETUP.md)** - 30-minute setup guide
- **[POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md)** - Manual configuration steps
- **[SETUP_CHECKLIST.md](SETUP_CHECKLIST.md)** - Deployment checklist

---

## Support and Feedback

For issues or feature requests:
- GitHub Issues: https://github.com/Jim8Knopf/frey/issues
- Check logs: `sudo journalctl -u frey-bluetooth-auto-connect -f`
- Status check: `sudo frey-bluetooth-status`

**Common Support Information to Include:**
```bash
# System info
uname -a
bluetoothctl --version
pactl --version

# Bluetooth status
sudo systemctl status bluetooth
sudo systemctl status frey-bluetooth-auto-connect

# Device list
bluetoothctl devices
cat /etc/frey/bluetooth/device-priority.conf

# Recent logs
sudo journalctl -u frey-bluetooth-auto-connect -n 50 --no-pager
sudo journalctl -u bluetooth -n 50 --no-pager
```
