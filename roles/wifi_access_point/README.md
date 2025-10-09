# WiFi Access Point Role

This Ansible role configures a Raspberry Pi to act as a WiFi Access Point while maintaining its existing WiFi client connection. This dual-interface setup allows the Pi to both connect to an existing WiFi network and provide its own WiFi network.

## Table of Contents

- [Overview](#overview)
- [Network Architecture](#network-architecture)
- [Requirements](#requirements)
- [Role Variables](#role-variables)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)

## Overview

This role creates a fully functional WiFi access point that:
- Broadcasts a configurable SSID
- Provides DHCP services to connected clients
- Offers local DNS resolution for `.frey` domains
- Routes internet traffic from AP clients through the primary WiFi connection
- Maintains stable operation alongside other system services

## Network Architecture

### Interface Configuration

| Interface | Purpose | Network | Details |
|-----------|---------|---------|---------|
| **wlan0** | Client | Existing WiFi | Connects to your primary WiFi network for internet access |
| **wlan1** | Access Point | 10.20.0.0/24 | Creates a new WiFi network for clients |

### Network Configuration

- **AP IP Address**: 10.20.0.1
- **DHCP Range**: 10.20.0.50 - 10.20.0.150
- **Subnet**: 10.20.0.0/24
- **DNS Domain**: .frey
- **Frequency**: 2.4GHz (Channel 7 by default)

### Traffic Flow

```
Client Device (10.20.0.x)
    ↓
wlan1 (AP Interface - 10.20.0.1)
    ↓
NAT/Masquerading
    ↓
wlan0 (Client Interface - Primary WiFi)
    ↓
Internet
```

## Requirements

### Hardware
- Raspberry Pi (tested on Pi 4/5)
- Two WiFi interfaces:
  - Built-in WiFi (wlan0) for client connection
  - USB WiFi adapter (wlan1) for access point
- USB WiFi adapter must support AP mode

### Software
- Debian-based OS (Raspberry Pi OS recommended)
- Root/sudo access
- Ansible 2.9+

### Collections
```yaml
collections:
  - ansible.posix
  - community.general
```

## Role Variables

### Required Variables

```yaml
wifi:
  # SSID of the access point
  ssid: "FreyHub"
  
  # WPA2 password (minimum 8 characters)
  password: "YourSecurePassword"
  
  # WiFi interface to use for AP
  interface: "wlan1"
  
  # WiFi interface connected to internet
  client_interface: "wlan0"
  
  # IP address of the AP
  ip: "10.20.0.1"
  
  # Network range for the AP
  network: "10.20.0.0/24"
  
  # DHCP range start
  dhcp_range_start: "10.20.0.50"
  
  # DHCP range end
  dhcp_range_end: "10.20.0.150"
  
  # WiFi channel (1-13 for 2.4GHz)
  channel: 7
  
  # ISO country code for regulatory compliance
  country: "AU"
```

### Optional Variables

```yaml
wifi:
  # Hardware mode (g=2.4GHz, a=5GHz)
  hw_mode: g
  
  # Enable 802.11n
  ieee80211n: 1
  
  # Enable WMM (WiFi Multimedia)
  wmm_enabled: 1
  
  # MAC address access control (0=disabled)
  macaddr_acl: 0
  
  # Authentication algorithms (1=open, 2=shared, 3=both)
  auth_algs: 1
  
  # Hide SSID (0=broadcast, 1=hidden)
  ignore_broadcast_ssid: 0
```

### DNS Configuration

```yaml
network:
  domain_name: frey
  dns_rewrites:
    - name: jellyfin
    - name: portainer
    - name: traefik
    # Add more services as needed
```

## Usage

### Basic Playbook

```yaml
---
- hosts: raspberry_pi
  become: yes
  roles:
    - wifi_access_point
```

### With Custom Variables

```yaml
---
- hosts: raspberry_pi
  become: yes
  vars:
    wifi:
      ssid: "MyCustomAP"
      password: "SuperSecure123!"
      channel: 11
      country: "US"
  roles:
    - wifi_access_point
```

### Running the Playbook

```bash
# Run with default variables
ansible-playbook site.yml --tags wifi_access_point

# Run with custom inventory
ansible-playbook -i inventory.yml site.yml

# Check mode (dry run)
ansible-playbook site.yml --tags wifi_access_point --check
```

## How It Works

### 1. Package Installation
Installs `hostapd` (creates AP), `dnsmasq` (DHCP/DNS), and utilities.

### 2. Conflict Resolution
- Disables `systemd-resolved` (conflicts with dnsmasq)
- Configures NetworkManager to ignore the AP interface
- Unblocks WiFi interfaces via rfkill

### 3. Network Configuration
- Sets static IP via dhcpcd
- Configures hostapd for WiFi broadcast
- Sets up dnsmasq for DHCP and local DNS

### 4. Service Startup Order
**Critical**: Services must start in this order:
1. **hostapd** - Activates the wireless radio
2. **dnsmasq** - Binds to the now-active interface

### 5. NAT Configuration
- Enables IP forwarding
- Creates iptables MASQUERADE rule
- Routes AP traffic through wlan0

### 6. DNS Resolution
- Clients get `.frey` domain resolution
- Services are accessible via friendly names
- Upstream DNS (8.8.8.8, 8.8.4.4) for internet

## Troubleshooting

### Network Not Visible

```bash
# Check if hostapd is running
sudo systemctl status hostapd

# View hostapd logs
sudo journalctl -u hostapd -n 50

# Verify interface is UP
ip addr show wlan1
```

**Common causes:**
- Channel not allowed in your country
- USB adapter doesn't support AP mode
- Interface has NO-CARRIER (hostapd not started)

### Can't Get IP Address

```bash
# Check dnsmasq status
sudo systemctl status dnsmasq

# Watch DHCP logs
sudo tail -f /var/log/dnsmasq.log

# Verify DHCP is configured
sudo dnsmasq --test -C /etc/dnsmasq.d/01-wifi-ap.conf
```

**Common causes:**
- dnsmasq started before hostapd
- Firewall blocking port 67 (DHCP)
- Configuration syntax error

### Connected But No Internet

```bash
# Verify IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# Check NAT rules
sudo iptables -t nat -L POSTROUTING -n -v

# Add NAT rule manually if missing
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o wlan0 -j MASQUERADE
```

**Common causes:**
- IP forwarding disabled
- NAT rule not active
- UFW blocking forwarding

### Services Show Bad Gateway

```bash
# Check DNS resolution
nslookup jellyfin.frey 10.20.0.1

# Verify services are accessible from Pi
curl -I http://jellyfin.frey:8096
```

**Solution:** Services should resolve to `10.20.0.1` (the AP gateway) from WiFi clients. The Pi will route traffic to the actual service.

### Useful Commands

```bash
# View all WiFi interfaces
iw dev

# Check AP mode support
iw list | grep -A 10 "Supported interface modes"

# Scan for networks (from wlan0)
sudo iw dev wlan0 scan | grep SSID

# Check connected clients
sudo hostapd_cli -i wlan1 all_sta

# View DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Live DHCP activity
sudo journalctl -u dnsmasq -f

# Test dnsmasq config
sudo dnsmasq --test -C /etc/dnsmasq.d/01-wifi-ap.conf
```

## Architecture Decisions

### Why Two Separate Networks?
- Isolation: AP clients are on separate subnet (10.20.0.0/24)
- Flexibility: Can apply different firewall rules per network
- Simplicity: Clear routing path via NAT

### Why Channel 7?
- 2.4GHz band has better range than 5GHz
- Channel 7 avoids common channels 1, 6, 11
- Less interference with primary WiFi on 5GHz

### Why dnsmasq.d Instead of dnsmasq.conf?
- Debian's dnsmasq service only reads from `/etc/dnsmasq.d/`
- Allows multiple configuration snippets
- Prevents conflicts with system defaults

### Service Startup Order
hostapd activates the wireless radio and establishes carrier on the interface. dnsmasq needs an active interface to bind to. Starting them in wrong order causes "Cannot assign requested address" errors.

## Integration with Frey

This role is part of the Frey home server stack:
- Works with UFW firewall (opens required ports)
- Integrates with Traefik reverse proxy
- Provides DNS for all Frey services
- Compatible with monitoring stack

## Security Considerations

- WPA2-PSK encryption enabled by default
- Change default password immediately
- Consider MAC filtering for production
- Review UFW rules for AP network
- Regularly update firmware

## License

MIT

## Author

Frey Project Contributors