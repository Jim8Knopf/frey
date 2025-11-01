# 🌐 Frey WiFi Automatic Roaming System

## Overview

The Frey WiFi Automatic Roaming System provides intelligent, hands-free WiFi connectivity management for your Raspberry Pi. Perfect for travel and mobile use cases, it continuously monitors available networks and automatically connects to the best option with working internet access.

## ✨ Features

- **Fully Automatic** - Scans, evaluates, and connects to WiFi networks without manual intervention
- **Intelligent Network Selection** - Scores networks based on signal strength, known/unknown status, security, and historical performance
- **Captive Portal Handling** - Automatically attempts to bypass captive portals (Starbucks, hotels, airports, etc.)
- **Internet Verification** - Only connects to networks that provide actual internet access (filters out IoT devices, printers)
- **Adaptive Scanning** - Adjusts scan frequency based on connection quality (aggressive when no connection, conservative when stable)
- **Home Assistant Integration** - Full MQTT support for monitoring and control via Home Assistant/n8n
- **Always Accessible** - FreyHub AP remains active so you can always SSH into your Pi
- **Network Learning** - Tracks success rates and blacklists problematic networks

## 🚀 Quick Start

### 1. Enable in Configuration

Edit `group_vars/all/main.yml`:

```yaml
network:
  wifi:
    # Existing AP configuration...

    # WiFi Roaming Configuration
    roaming:
      enabled: true
      client_interface: "wlan0"  # Interface for connecting to public WiFi
      mqtt_topic: "frey/wifi/roaming"

# Optional: Define known networks
known_wifi_networks:
  - ssid: "Home WiFi"
    password: "mySecurePassword123"
    priority: 100  # Highest priority

  - ssid: "Office WiFi"
    password: "workPassword456"
    priority: 90

  - ssid: "Starbucks WiFi"
    password: ""  # Open network
    priority: 60

  - ssid: "Hotel Guest"
    password: ""
    priority: 40

# Optional: MQTT configuration (if not using defaults)
mqtt:
  broker: "localhost"
  port: 1883
```

### 2. Deploy

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags wifi
```

### 3. Verify

SSH into your Pi and check the service:

```bash
# Check service status
sudo systemctl status frey-wifi-roaming

# View real-time logs
sudo journalctl -u frey-wifi-roaming -f

# Check current WiFi connection
sudo wpa_cli -i wlan0 status
```

## 📊 How It Works

### Network Scoring Algorithm

Each available network is scored (0-100) based on:

| Criterion | Points | Description |
|-----------|--------|-------------|
| **Signal Strength** | 0-40 | Stronger signal = higher score |
| **Known Network** | 0-30 | Saved networks get priority bonus |
| **History** | 0-20 | Networks with good track record score higher |
| **Security** | 0 to -10 | Open networks get small penalty |
| **Failures** | -10 each | Recent connection failures reduce score |

**Example Scores:**
- Home WiFi (excellent signal, known, WPA2): 95
- Starbucks (good signal, known, open): 65
- Unknown cafe (weak signal, open): 25
- Printer WiFi (blacklisted): 0

### Adaptive Scanning States

The system adjusts scanning frequency based on connection state:

| State | Condition | Scan Interval |
|-------|-----------|---------------|
| **No Connection** | Not connected to any WiFi | Every 30 seconds (aggressive) |
| **No Internet** | Connected but no internet | Every 60 seconds (medium) |
| **Weak Signal** | Connected, internet OK, signal <-75 dBm | Every 2 minutes |
| **Good Connection** | Connected, internet OK, signal >-75 dBm | Every 10 minutes (conservative) |

### Captive Portal Auto-Authentication

When connected to a network with a captive portal, the system automatically tries:

1. **Simple Visit** - Many portals authenticate just by loading the page
2. **Form Auto-Submit** - Finds and clicks "Accept" / "Agree" buttons
3. **API Endpoints** - Tries common authentication APIs
4. **Button Detection** - Searches for and clicks acceptance links

**Success Rate:** ~80-90% of common captive portals are bypassed automatically

If automatic bypass fails, the network is temporarily blacklisted and the system tries a different network.

## 🏠 Home Assistant Integration

### MQTT Topics

**Status Topics (published by Pi):**
```
frey/wifi/roaming/status/state           # scanning|connecting|connected|failed
frey/wifi/roaming/status/current_ssid    # "Starbucks WiFi"
frey/wifi/roaming/status/signal_dbm      # -65
frey/wifi/roaming/status/has_internet    # true|false
frey/wifi/roaming/status/networks_found  # 7
```

**Control Topics (publish to these to control the Pi):**
```
frey/wifi/roaming/control/scan_interval  # Change scan frequency (seconds)
frey/wifi/roaming/control/enabled        # true|false (enable/disable roaming)
frey/wifi/roaming/control/mode           # aggressive|moderate|conservative
frey/wifi/roaming/control/rescan         # true (trigger immediate scan)
```

**Event Topic:**
```
frey/wifi/roaming/events  # JSON events: {"event":"switched","from":"X","to":"Y"}
```

### Home Assistant Configuration

Add to `configuration.yaml`:

```yaml
# WiFi Roaming Sensors
mqtt:
  sensor:
    - name: "Frey WiFi Network"
      state_topic: "frey/wifi/roaming/status/current_ssid"

    - name: "Frey WiFi Signal"
      state_topic: "frey/wifi/roaming/status/signal_dbm"
      unit_of_measurement: "dBm"

    - name: "Frey WiFi State"
      state_topic: "frey/wifi/roaming/status/state"

  binary_sensor:
    - name: "Frey Has Internet"
      state_topic: "frey/wifi/roaming/status/has_internet"
      payload_on: "true"
      payload_off: "false"

# Control Buttons
button:
  - platform: mqtt
    name: "Frey Force WiFi Rescan"
    command_topic: "frey/wifi/roaming/control/rescan"
    payload_press: "true"

# Scan Mode Selector
input_select:
  frey_wifi_scan_mode:
    name: "Frey WiFi Scan Mode"
    options:
      - aggressive
      - moderate
      - conservative
    initial: moderate
    icon: mdi:wifi-sync

# Automation to apply scan mode
automation:
  - alias: "Frey: Apply WiFi Scan Mode"
    trigger:
      - platform: state
        entity_id: input_select.frey_wifi_scan_mode
    action:
      - service: mqtt.publish
        data:
          topic: "frey/wifi/roaming/control/mode"
          payload: "{{ states('input_select.frey_wifi_scan_mode') }}"
```

### Dashboard Card

```yaml
type: entities
title: Frey WiFi Roaming
entities:
  - entity: sensor.frey_wifi_network
    name: Current Network
  - entity: sensor.frey_wifi_signal
    name: Signal Strength
  - entity: binary_sensor.frey_has_internet
    name: Internet Access
  - entity: sensor.frey_wifi_state
    name: Connection State
  - type: divider
  - entity: input_select.frey_wifi_scan_mode
    name: Scan Mode
  - entity: button.frey_force_wifi_rescan
    name: Force Rescan
```

## ⚙️ Configuration

### Scan Interval Tuning

Edit `/etc/frey/wifi-roaming.conf` on the Pi:

```bash
# For travel (aggressive switching)
SCAN_INTERVAL_DEFAULT=60           # 1 minute
SCAN_INTERVAL_NO_CONNECTION=20     # 20 seconds
SCAN_INTERVAL_GOOD=120             # 2 minutes

# For stationary use (conservative)
SCAN_INTERVAL_DEFAULT=300          # 5 minutes
SCAN_INTERVAL_GOOD=900             # 15 minutes
```

After editing, restart the service:
```bash
sudo systemctl restart frey-wifi-roaming
```

### Network Blacklist Patterns

To avoid connecting to specific network types, edit `/etc/frey/wifi-roaming.conf`:

```bash
BLACKLIST_PATTERNS=(
    ".*-printer.*"
    ".*-iot.*"
    "HP-.*"
    "Canon_.*"
    "MySmartTV.*"
    "Chromecast-.*"
)
```

### Known Networks

Add trusted networks with passwords to `/etc/frey/known-networks.conf`:

```
# Format: SSID|PASSWORD|PRIORITY(0-100)
Home WiFi|mypassword123|100
Office WiFi|workpass456|90
Starbucks WiFi||60
Hotel Guest||40
```

## 🛠️ Management Commands

```bash
# Service control
sudo systemctl start frey-wifi-roaming
sudo systemctl stop frey-wifi-roaming
sudo systemctl restart frey-wifi-roaming
sudo systemctl status frey-wifi-roaming

# View logs
sudo journalctl -u frey-wifi-roaming -f          # Follow live
sudo journalctl -u frey-wifi-roaming -n 100      # Last 100 lines
sudo journalctl -u frey-wifi-roaming --since "1 hour ago"

# Monitor with grep
sudo journalctl -u frey-wifi-roaming -f | grep -E "(Switching|Connected|Portal)"

# View detailed log file
sudo tail -f /var/log/frey-wifi-roaming.log

# Check current WiFi status
sudo wpa_cli -i wlan0 status
sudo wpa_cli -i wlan0 scan_results

# View network history
sudo cat /var/lib/frey/wifi-network-history.json | jq

# View blacklist
sudo cat /var/lib/frey/wifi-blacklist.json | jq
```

## 🧪 Testing

### Test Internet Verification

```bash
sudo /usr/local/bin/frey-wifi-internet-verify --interface wlan0 --verbose
```

Expected output if working:
```
[INFO] Starting internet verification on interface: wlan0
[INFO] Interface IP: 192.168.1.100
[INFO] ✓ IP connectivity confirmed
[INFO] ✓ DNS resolution working
[INFO] ✓ HTTP connectivity confirmed (no captive portal)
[INFO] ✓ HTTPS connectivity confirmed
[INFO] ✅ Full internet access confirmed
```

### Test Captive Portal Detection

```bash
sudo /usr/local/bin/frey-wifi-captive-portal-auto --interface wlan0 --verbose
```

### Test Network Scoring

```bash
sudo /usr/local/bin/frey-wifi-network-scorer --ssid "Test Network" --signal -65 --security "WPA2" --verbose
```

## 📝 Troubleshooting

### Problem: Service won't start

**Check:**
```bash
sudo systemctl status frey-wifi-roaming
sudo journalctl -u frey-wifi-roaming -n 50
```

**Common causes:**
- Missing dependencies (w3m, jq, mosquitto-clients)
- Incorrect interface name in config
- Permissions issues

**Fix:**
```bash
sudo apt install w3m jq mosquitto-clients
sudo systemctl restart frey-wifi-roaming
```

### Problem: Not connecting to any networks

**Check:**
1. Is wlan0 interface available and up?
   ```bash
   ip link show wlan0
   sudo ip link set wlan0 up
   ```

2. Is wpa_supplicant running?
   ```bash
   sudo systemctl status wpa_supplicant
   ```

3. Check roaming daemon logs for errors:
   ```bash
   sudo journalctl -u frey-wifi-roaming -f
   ```

### Problem: Connected but no internet

**Check:**
1. Run internet verification manually:
   ```bash
   sudo /usr/local/bin/frey-wifi-internet-verify --interface wlan0 --verbose
   ```

2. Check for captive portal:
   ```bash
   curl -I http://captive.apple.com
   ```

3. Check if it's a DNS issue:
   ```bash
   nslookup google.com 8.8.8.8
   ```

### Problem: Constantly switching networks

**Solution:** Increase the switch threshold in `/etc/frey/wifi-roaming.conf`:

```bash
SWITCH_THRESHOLD=20  # Higher = less frequent switches
```

### Problem: Can't connect to FreyHub to SSH

FreyHub should always stay running. Check:
```bash
# From another device, scan for FreyHub SSID
# If missing, check hostapd service
sudo systemctl status hostapd
sudo systemctl restart hostapd
```

## 🎯 Use Cases

### Scenario 1: Daily Commute
- Pi in backpack
- Automatically connects to train WiFi
- Switches to office WiFi when you arrive
- Connects back to train WiFi on way home
- Connects to home WiFi when you get home

### Scenario 2: Travel
- Airport: Connects to airport free WiFi
- Hotel: Auto-bypasses hotel portal
- Cafe: Connects to Starbucks WiFi
- Conference: Switches to conference network
- All automatic, no manual switching needed

### Scenario 3: Remote Work
- Home: Uses home WiFi (priority 100)
- Coffee shop: Connects to cafe WiFi
- Coworking: Connects to coworking space
- Returns home: Automatically switches back to home WiFi

## 🔒 Security Considerations

- **Open Networks:** System will connect to open WiFi if `ALLOW_OPEN_NETWORKS=true`
- **Auto-Connect Risk:** Connecting to any open WiFi has security implications
- **Recommendation:** Use VPN when on public WiFi
- **Known Networks:** Use `known_wifi_networks` to limit to trusted networks only

### Restrict to Known Networks Only

Edit `/etc/frey/wifi-roaming.conf`:
```bash
ALLOW_OPEN_NETWORKS=false  # Only connect to networks in known-networks.conf
```

## 📊 Network History

The system tracks connection attempts and maintains history:

```bash
# View history
sudo cat /var/lib/frey/wifi-network-history.json | jq
```

Example output:
```json
{
  "Home WiFi": {
    "successes": 127,
    "failures": 2,
    "attempts": 129,
    "last_success": 1698765432
  },
  "Starbucks WiFi": {
    "successes": 45,
    "failures": 12,
    "attempts": 57,
    "last_success": 1698761234
  }
}
```

## 🆘 Getting Help

1. Check logs: `sudo journalctl -u frey-wifi-roaming -f`
2. Review configuration: `/etc/frey/wifi-roaming.conf`
3. Test individual components (internet verify, captive portal, scoring)
4. Check GitHub issues: https://github.com/yourrepo/frey

## 📈 Future Enhancements

Planned features:
- [ ] Web UI for configuration and monitoring
- [ ] Machine learning for network quality prediction
- [ ] VPN auto-enable on public networks
- [ ] Bandwidth testing and speed-based scoring
- [ ] Mobile app for remote control
- [ ] Network quality heatmaps
