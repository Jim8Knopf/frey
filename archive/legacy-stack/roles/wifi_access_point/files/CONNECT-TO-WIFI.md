# Connecting to Public WiFi on FreyHub

This guide explains how to connect your Raspberry Pi to public WiFi networks (like cafe WiFi) while keeping the FreyHub Access Point running.

## Overview

Your Pi has two WiFi interfaces:

- **wlan0**: Free interface - use this to connect to public WiFi
- **wlan1**: Access Point interface - broadcasts FreyHub (don't modify)

When wlan0 connects to a WiFi network with internet, the NAT Manager automatically enables internet passthrough for FreyHub clients.

---

## Method 1: TUI Manager (Easiest - Recommended)

The easiest way to connect to WiFi using a visual menu interface:

```bash
sudo frey-wifi-tui
```

### Main Menu:

```
┌─ Frey WiFi Manager ────────────────────────┐
│ Choose an action:                          │
│                                            │
│  1. Scan and connect to WiFi network      │
│  2. Disconnect from WiFi                  │
│  3. Show current status                   │
│  4. Exit                                   │
└────────────────────────────────────────────┘
```

### How to Connect:

1. **Run `sudo frey-wifi-tui`**
2. **Select option 1** - "Scan and connect to WiFi network"
3. **Wait for scanning** (3-5 seconds)
4. **Select your network** from the list with arrow keys:

```
┌─ Available WiFi Networks ──────────────────┐
│                                            │
│  CafeWiFi         [▮▮▮▮] WPA              │
│  HomeNetwork      [▮▮▮▯] WPA              │
│  FreePublicWiFi   [▮▮▯▯] Open             │
└────────────────────────────────────────────┘
```

5. **Enter password** if needed
6. **Watch progress** bar as it connects
7. **See confirmation** with IP address

### Features:

- **Network scanning** - Shows all available WiFi networks
- **Signal strength** - Visual bars (▮▮▮▮ = strong, ▮▯▯▯ = weak)
- **Security indicators** - WPA, WPA2, or Open
- **Password entry** - Secure hidden password input
- **Progress bar** - Real-time connection progress
- **Status display** - Check current connection anytime
- **Auto-saves** - Networks are remembered
- **Safe** - Only manages wlan0 (doesn't touch wlan1 AP)

---

## Method 2: Quick Command Line Script

For quick connections without the TUI:

```bash
sudo frey-connect-wifi "WiFiNetworkName" "password"
```

**Examples:**

```bash
# Connect to a cafe WiFi
sudo frey-connect-wifi "Starbucks WiFi" "password123"

# Connect to home WiFi
sudo frey-connect-wifi "MyHomeWiFi" "mySecretPass"

# Connect to open WiFi (no password)
sudo frey-connect-wifi "FreePublicWiFi"
```

**Check connection:**

```bash
# View wlan0 status
ip addr show wlan0

# Check if you have internet
ping -c 3 8.8.8.8

# View NAT status (should show wlan0 as upstream)
sudo journalctl -u frey-nat-manager -n 20
```

**Disconnect from WiFi:**

```bash
sudo frey-disconnect-wifi
```

---

## Manual Method: Using wpa_cli Interactive Mode

If you prefer manual control or the script doesn't work:

### Step 1: Create wpa_supplicant Configuration

```bash
sudo tee /etc/wpa_supplicant/wpa_supplicant-wlan0.conf > /dev/null << 'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=US
EOF
```

### Step 2: Start wpa_supplicant on wlan0

```bash
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
```

### Step 3: Use wpa_cli Interactive Mode

```bash
sudo wpa_cli -i wlan0
```

**Inside wpa_cli prompt:**

```
> scan                          # Scan for available networks
> scan_results                  # Show available networks
> add_network                   # Returns network ID (usually 0)
> set_network 0 ssid "WiFiName" # Set network name
> set_network 0 psk "password"  # Set password
> enable_network 0              # Connect to network
> save_config                   # Save configuration
> status                        # Check connection status
> quit                          # Exit wpa_cli
```

**For open WiFi (no password):**
```
> add_network
> set_network 0 ssid "OpenWiFi"
> set_network 0 key_mgmt NONE
> enable_network 0
> save_config
> quit
```

### Step 4: Get IP Address

```bash
sudo dhcpcd wlan0
```

### Step 5: Verify Connection

```bash
# Check IP address
ip addr show wlan0

# Test internet connectivity
ping -c 3 8.8.8.8

# Check default route
ip route

# View NAT manager logs
sudo journalctl -u frey-nat-manager -n 20 --no-pager
```

---

## Advanced: wpa_cli Commands

**Useful wpa_cli commands:**

```bash
# Scan for networks
sudo wpa_cli -i wlan0 scan
sudo wpa_cli -i wlan0 scan_results

# Check current status
sudo wpa_cli -i wlan0 status

# List saved networks
sudo wpa_cli -i wlan0 list_networks

# Remove a network (where 0 is network ID)
sudo wpa_cli -i wlan0 remove_network 0

# Disable/enable network
sudo wpa_cli -i wlan0 disable_network 0
sudo wpa_cli -i wlan0 enable_network 0

# Reconnect
sudo wpa_cli -i wlan0 reconnect

# Disconnect
sudo wpa_cli -i wlan0 disconnect
```

---

## Troubleshooting

### Problem: Can't connect to WiFi

**Check wpa_supplicant is running:**
```bash
ps aux | grep wpa_supplicant
```

**Restart wpa_supplicant:**
```bash
sudo killall wpa_supplicant
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
```

**Check logs:**
```bash
sudo journalctl -u wpa_supplicant -n 50
```

### Problem: Connected but no internet

**Check default route:**
```bash
ip route
# Should show: default via X.X.X.X dev wlan0
```

**Check DNS:**
```bash
cat /etc/resolv.conf
# Should have nameserver entries
```

**Test connectivity:**
```bash
# Test DNS resolution
nslookup google.com

# Test direct IP
ping -c 3 8.8.8.8

# Test with hostname
ping -c 3 google.com
```

### Problem: FreyHub stopped working

**Check wlan1 status:**
```bash
ip addr show wlan1
# Should show: 10.20.0.1/24

iw dev wlan1 info
# Should show: type AP, ssid FreyHub
```

**Check services:**
```bash
sudo systemctl status hostapd
sudo systemctl status dnsmasq
sudo systemctl status frey-nat-manager
```

**Restart WiFi AP:**
```bash
ansible-playbook playbooks/site.yml -i inventory/hosts.yml --tags wifi
```

### Problem: NetworkManager breaks everything

**If you accidentally started NetworkManager and lost connection:**

1. **Reboot the Pi** (safest option):
   ```bash
   sudo reboot
   ```

2. **Or fix manually:**
   ```bash
   # Stop and mask NetworkManager
   sudo systemctl stop NetworkManager
   sudo systemctl mask NetworkManager

   # Restart dhcpcd
   sudo systemctl restart dhcpcd

   # Restart WiFi AP services
   sudo systemctl restart hostapd
   sudo systemctl restart dnsmasq
   ```

---

## How NAT Passthrough Works

When you connect wlan0 to public WiFi:

1. **wlan0 gets IP** from the public WiFi router
2. **Default route** is added via wlan0
3. **NAT Manager detects** the new upstream interface (wlan0)
4. **Automatically enables** iptables MASQUERADE for FreyHub clients
5. **FreyHub clients** can now access internet through wlan0

**View NAT status:**
```bash
# Check NAT manager logs
sudo journalctl -u frey-nat-manager -f

# View iptables NAT rules
sudo iptables -t nat -L POSTROUTING -v -n

# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1
```

---

## Network Priority

When multiple interfaces have internet:

1. **eth0** (LAN) - Highest priority
2. **wlan0** (WiFi) - Medium priority
3. **wlan1** (AP) - Never used as upstream

The NAT manager automatically selects the best available upstream interface.

---

## Use Cases

### Scenario 1: Cafe WiFi
1. Sit in cafe with laptop
2. Connect Pi to cafe WiFi via wlan0
3. Connect laptop to FreyHub
4. Both Pi and laptop use cafe's internet

### Scenario 2: Hotel WiFi
1. Connect Pi to hotel WiFi via wlan0
2. All your devices connect to FreyHub
3. Only need to accept hotel WiFi terms once (on Pi)
4. All devices share the connection

### Scenario 3: Mobile Hotspot
1. Enable hotspot on phone
2. Connect Pi to phone's hotspot via wlan0
3. Other devices connect to FreyHub
4. Share mobile data across all devices

### Scenario 4: Completely Offline
1. No eth0, no wlan0 connection
2. FreyHub still works (local network only)
3. Services like Immich, media servers work fine
4. No internet passthrough

---

## Security Notes

- **WPA2 passwords** are stored in `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`
- File has **600 permissions** (root only)
- **Never share** your wpa_supplicant config file
- **Open WiFi** networks are not encrypted (use VPN if needed)
- **FreyHub password** is separate and not affected

---

## Files and Locations

| File/Location | Purpose |
|---------------|---------|
| `/usr/local/bin/frey-wifi-tui` | TUI WiFi manager (dialog-based, easiest method) |
| `/usr/local/bin/frey-connect-wifi` | CLI WiFi connection helper script |
| `/usr/local/bin/frey-disconnect-wifi` | WiFi disconnection helper script |
| `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` | WiFi credentials for wlan0 (auto-saved) |
| `/var/log/frey-nat-manager.log` | NAT manager logs |
| `/usr/local/bin/frey-nat-manager.sh` | NAT manager script |

---

## Quick Reference

```bash
# Connect to WiFi (TUI - easiest)
sudo frey-wifi-tui

# Connect to WiFi (command line)
sudo frey-connect-wifi "WiFiName" "password"

# Disconnect from WiFi
sudo frey-disconnect-wifi

# Check wlan0 status
ip addr show wlan0

# Check internet
ping -c 3 8.8.8.8

# View NAT status
sudo journalctl -u frey-nat-manager -n 20

# Restart WiFi AP
sudo systemctl restart hostapd dnsmasq

# Check all services
sudo systemctl status hostapd dnsmasq dhcpcd frey-nat-manager
```

---

## Getting Help

If you encounter issues:

1. **Check service status:**
   ```bash
   sudo systemctl status hostapd dnsmasq dhcpcd frey-nat-manager
   ```

2. **View logs:**
   ```bash
   sudo journalctl -u hostapd -n 50
   sudo journalctl -u dnsmasq -n 50
   sudo journalctl -u frey-nat-manager -n 50
   ```

3. **Redeploy WiFi configuration:**
   ```bash
   ansible-playbook playbooks/site.yml -i inventory/hosts.yml --tags wifi,networking
   ```

4. **Last resort - reboot:**
   ```bash
   sudo reboot
   ```

---

**Remember:** Never start NetworkManager or wpa_supplicant.service - they will break your setup. Always use wlan0 for WiFi connections and leave wlan1 alone.
