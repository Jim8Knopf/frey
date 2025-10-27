 # wifi_access_point — minimal role for AP, local DNS and optional NAT

This file documents the downsized `wifi_access_point` role. It explains what the role now contains, the variables it uses, safe deployment steps (so you don't disconnect a live ssh session), how it integrates with the rest of the Frey project (Traefik/docker in `roles/infrastructure`), and how to verify behavior.

Keep in mind: Traefik and Docker are important to the overall Frey architecture and live in `roles/infrastructure`; this role has been intentionally focused on only AP/DNS/NAT functions. I did not remove `roles/infrastructure` or its templates — only trimmed non-essential content from this role's templates and tasks.

What was kept in the role
- Templates: `hostapd.conf.j2`, `dnsmasq.conf.j2`, `dhcpcd.conf.j2` (network persistence)
- Tasks: `tasks/main.yml` — installs packages, deploys templates, starts services, and now includes safety checks to avoid reconfiguring the control interface
- Handlers: `handlers/main.yml` — graceful reloads (hostapd_cli reconfigure, systemctl reload dnsmasq) and restart fallbacks
- Defaults: `defaults/main.yml` — minimal variables under `network.wifi.*` (AP interface, client/uplink interface, IPs, DHCP range, NAT flag)
- Tests: `tests/verify.yml` — explicit verification play

What was removed or simplified
- Docker/Traefik-specific configuration and verbose examples were removed from the templates in this role (they belong under `roles/infrastructure`).
- Verbose dnsmasq logging and Docker internal DNS references were removed from the role's dnsmasq template to keep the AP role minimal and stable.

Top-level variables (defaults)
The role relies on a small set of variables. Put these in your playbook `vars` or inventory/group_vars when needed.

- `network.wifi.interface` (string) — AP interface, recommended a secondary adapter like `wlan1` (default: `wlan1`)
- `network.wifi.client_interface` (string) — uplink interface with internet access, e.g. `wlan0` or `eth0` (default: `wlan0`)
- `network.wifi.ip` (string) — AP gateway IP (default `10.20.0.1`)
- `network.wifi.network` (string) — AP subnet (default `10.20.0.0/24`)
- `network.wifi.dhcp_range_start` / `network.wifi.dhcp_range_end` — DHCP pool
- `network.wifi.ssid` / `network.wifi.password` — AP SSID and PSK
- `network.domain_name` — short domain used in dnsmasq (default `frey`)
- `network.dns_rewrites` — list of `{ name: <short-name> }` records that will be served by dnsmasq pointing to the AP IP
- `network.wifi.enable_nat` (bool) — when `true` the role will expect NAT rules to be present (default `false`). NAT policy is normally managed by the `security` role; enabling this causes verification to check for a MASQUERADE rule.

Safety and deployment rules (important — read before running)

1. Do not change the interface you use for SSH/web management.
   - The play now checks `ansible_default_ipv4.interface` against `network.wifi.interface` and will fail unless `force_apply: true` is set.
   - If you only have a single WiFi adapter, do this work from physical console or wired network.

2. Prefer a separate adapter for AP (recommended: `wlan1`).

3. The role applies configuration changes non-disruptively when possible:
   - `hostapd` changes use `hostapd_cli -i <iface> reconfigure` when possible (no client disconnect).
   - `dnsmasq` uses `systemctl reload dnsmasq` with a restart fallback.
   - `dhcpcd` is updated persistently via `templates/dhcpcd.conf.j2` and the service is restarted only when necessary.

4. NAT and firewall
   - The role includes an optional `enable_nat` flag but does not force complex firewall changes.
   - If you want the AP clients to reach the internet via `network.wifi.client_interface`, create an iptables/nftables MASQUERADE rule for the AP subnet to the uplink interface. We recommend managing persistent firewall rules in `roles/security` or in `roles/infrastructure` if you prefer.

Sample NAT (run manually or via security role)
```bash
sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o wlan0 -j MASQUERADE
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
```

Integration with `roles/infrastructure` (Traefik / Docker)
- Traefik and Docker are central to the Frey project but are outside the scope of this role.
- For service discovery and reverse proxying, your containers and Traefik should be configured in `roles/infrastructure`. This role provides DNS for `.frey` names so clients on the AP can resolve service names to the AP gateway (Traefik listens on the Pi and routes to containers as needed).
- If you use Traefik locally and want `*.frey` to resolve to the Pi, add the services to `network.dns_rewrites` or manage the DNS entries centrally via `roles/infrastructure`.

How to use (quick)

1. Ensure you have a separate WiFi adapter for AP (recommended).
2. Add any overrides in `group_vars/all/main.yml` or in your playbook:

```yaml
network:
  wifi:
    interface: wlan1
    client_interface: wlan0
    ip: 10.20.0.1
    ssid: MyAP
    password: VerySecurePass
  domain_name: frey
  dns_rewrites:
    - name: jellyfin
    - name: portainer
```

3. Run the role (from a management host that is not on `wlan1`):

```bash
ansible-playbook -i inventory site.yml --tags wifi_access_point
```

4. Verify with the tests playbook:

```bash
ansible-playbook -i inventory roles/wifi_access_point/tests/verify.yml
```

Verification checklist (what the tests do)
- Interface exists and has the configured AP IP
- `hostapd` is active
- `dnsmasq` is active and answers queries for configured names and wildcard `*.{{ network.domain_name }}`
- `net.ipv4.ip_forward` is `1` (if NAT expected)
- Optional: NAT MASQUERADE rule present when `network.wifi.enable_nat: true`

Notes & edge cases
- NetworkManager and other network services can interact with `dhcpcd` and `hostapd` — this role expects `dhcpcd` on Debian-like systems. If you use NetworkManager, you may need to adapt the role or disable NM for the AP interface.
- If `hostapd_cli reconfigure` is unsupported on your platform, the handler falls back to a restart.
- For nftables, replace iptables steps with nft atomic replace logic in the `security` role.

If you want, I can:
- (A) add an idempotent NAT task to this role (creates/persists MASQUERADE when `enable_nat: true`), or
- (B) add an interactive preview task that prints planned changes and requires a confirmation variable before applying, or
- (C) leave NAT to the `security` role and add clear cross-role docs (I recommend this for separation of concerns).

— End of wifi_access_point README —
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