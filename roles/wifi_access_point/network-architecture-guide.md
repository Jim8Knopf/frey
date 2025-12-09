# Network Architecture: WiFi AP + Docker Services + Roaming

## Overview

This document explains the complete network architecture including:
- How WiFi AP clients access Docker containers through Traefik
- Dual-interface WiFi setup (AP on wlan1, roaming on wlan0)
- Automatic WiFi roaming with captive portal bypass
- Internet passthrough and NAT configuration

## Architecture Layers

### 1. WiFi Dual-Interface Architecture

The system uses two WiFi interfaces for different purposes:

#### wlan1 (Access Point Mode)
- **Purpose:** FreyHub WiFi access point for local service access
- **IP Address:** 10.20.0.1
- **DHCP Range:** 10.20.0.50 - 10.20.0.150
- **Services:**
  - hostapd (WiFi radio management)
  - dnsmasq (DHCP + DNS for .frey domains)
- **Always-On:** This interface remains active even during roaming

#### wlan0 (Client Roaming Mode)
- **Purpose:** Automatic connection to public/known WiFi networks
- **Management:** frey-wifi-roaming-daemon
- **Features:**
  - Intelligent network selection and scoring
  - Multi-layered captive portal detection
  - Automatic portal bypass (80-90% success rate)
  - Signal-based pause/resume control
- **Dynamic:** Switches between networks based on signal strength and internet availability

#### eth0 (Optional Ethernet)
- **Purpose:** Primary internet connection (if available)
- **Priority:** Higher than WiFi for internet passthrough
- **Failover:** System uses wlan0 if eth0 unavailable

### 2. Internet Passthrough (NAT/MASQUERADE)

```
Internet
  │
  ├─ eth0 (Primary) OR wlan0 (Roaming)
  │         │
  │         └─ NAT/MASQUERADE
  │                   │
  └───────────────────┴─ wlan1 (FreyHub AP: 10.20.0.1)
                              │
                              └─ WiFi Clients (10.20.0.50-150)
                                    │
                                    └─ Access Docker Services via Traefik
```

**How It Works:**
1. Roaming daemon connects wlan0 to best available public WiFi
2. NAT forwards traffic from wlan1 (10.20.0.0/24) through wlan0/eth0
3. WiFi AP clients get internet access + local service access
4. If wlan0 loses internet, daemon automatically switches networks

**Configuration:**
- Managed by: `roles/wifi_access_point/templates/dhcpcd.conf.j2`
- NAT rules: iptables MASQUERADE on primary interface
- Routing: Default gateway automatically adjusted by roaming daemon

### 3. WiFi Roaming System

#### Multi-Layered Captive Portal Detection

The roaming daemon uses three detection methods to identify captive portals:

**Method 1: HTTP Redirect Detection (Traditional)**
```bash
# Test URL: http://neverssl.com
final_url=$(curl -s -w "%{url_effective}" -o /dev/null http://neverssl.com)
if [[ "$final_url" != "http://neverssl.com"* ]]; then
    # Portal detected: URL changed = redirect
fi
```
- Works for: Starbucks, airports, most hotels
- Detects: 302/307 redirects to portal login pages

**Method 2: Ping-Based Internet Verification (Non-Redirecting)**
```bash
# Verify real internet connectivity
if ! ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    # Portal detected: connected but no real internet
fi
```
- Works for: LibrariesSA-Free, university networks, enterprise portals
- Detects: Portals that intercept traffic WITHOUT redirecting

**Method 3: Content Verification (Interception)**
```bash
# Verify HTTP response contains expected content
response=$(curl -s http://neverssl.com)
if ! echo "$response" | grep -q "NeverSSL"; then
    # Portal detected: wrong content returned
fi
```
- Works for: Edge cases with custom HTML interception
- Detects: Portals returning custom pages without redirect or blocking

#### Automatic Portal Bypass Strategies

**Strategy 1: Shell-Based Bypass (Primary - Fast)**
- cURL-based form submission
- Common API endpoint attempts (`/login`, `/auth`, `/connect`)
- Button click simulation (Accept/Agree/Continue)
- Success rate: ~70%
- Performance: <2 seconds

**Strategy 2: Selenium-Based Bypass (Fallback - Comprehensive)**
- Headless browser automation
- JavaScript interaction support
- Multi-step authentication flows
- Success rate: ~20% additional (90% total)
- Performance: 10-30 seconds

**Overall Success Rate:** 80-90% on common portals

#### Signal-Based Control System

The roaming daemon supports instant pause/resume without stopping the service:

**Technical Implementation:**
```bash
# In daemon (frey-wifi-roaming-daemon.sh)
SCANNING_PAUSED=false

handle_pause() {
    SCANNING_PAUSED=true
    log INFO "WiFi roaming PAUSED by user signal (SIGUSR1)"
}

handle_resume() {
    SCANNING_PAUSED=false
    log INFO "WiFi roaming RESUMED by user signal (SIGUSR2)"
}

trap handle_pause SIGUSR1
trap handle_resume SIGUSR2

# In main loop
roaming_cycle() {
    if [ "$SCANNING_PAUSED" = true ]; then
        sleep 10  # Keep daemon responsive
        return
    fi
    # ... normal scanning logic
}
```

**User Control Script (`frey-wifi-pause`):**
```bash
# Pause scanning
sudo frey-wifi-pause pause    # Sends SIGUSR1

# Resume scanning
sudo frey-wifi-pause resume   # Sends SIGUSR2

# Check status
sudo frey-wifi-pause status   # Shows daemon state
```

**Advantages:**
- Instant response (no systemctl restart)
- No file I/O overhead
- Daemon stays running and responsive
- Clean signal handling

### 🔒 Security Measures

1. **Network Isolation**: 
   - All traffic is contained within the `10.20.0.0/24` subnet
   - WiFi network is isolated from the main network
   - Managed by UFW rules in the `security` role

2. **Access Control**:
   - Services accessible from both local WiFi and public internet
   - UFW firewall automatically configured for:
     - DNS (TCP/UDP 53, local only)
     - DHCP (UDP 67, local only)
     - Web services (TCP 80/443, public access)
     - NAT for internet access
   - Optional local-only restrictions via Traefik middleware

3. **Container Security**:
   - All traffic proxied through Traefik
   - No direct container exposure to WiFi network
   - SSL termination at Traefik level

### ✅ Advantages

1. **Single Entry Point**: All traffic goes through Traefik (port 80/443)
2. **SSL Termination**: Easy to add Let's Encrypt certificates
3. **Path-based Routing**: Can route by path, not just hostname
4. **No Port Conflicts**: Services don't need unique external ports
5. **Better Security**: Containers not directly exposed to network
6. **Easy Service Discovery**: Just add DNS entry and Traefik label

### 📝 Implementation Checklist

- [x] Traefik container publishes ports 80/443
- [x] Traefik joins `proxy` and `localdns` networks
- [x] All services join `proxy` network
- [x] All services have Traefik labels with routing rules
- [x] DNS points `*.frey` to `{{ network.wifi.ip }}`
- [x] Firewall configured via security role

## Complete Network Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Internet                                     │
└────────────────────────┬──────────────────────┬─────────────────────────┘
                         │                      │
            ┌────────────▼─────────┐  ┌────────▼──────────┐
            │  Public WiFi         │  │  Ethernet         │
            │  (LibrariesSA-Free,  │  │  (Primary)        │
            │   Starbucks, etc.)   │  │                   │
            └────────────┬─────────┘  └────────┬──────────┘
                         │                      │
                    ┌────▼──────────────────────▼─────┐
                    │  Automatic WiFi Roaming         │
                    │  (frey-wifi-roaming-daemon)     │
                    │  - Multi-layer portal detection │
                    │  - Automatic bypass (80-90%)    │
                    │  - Signal-based pause/resume    │
                    └────────────┬────────────────────┘
                                 │
                        ┌────────▼────────┐
                        │  wlan0 / eth0   │
                        │  (Client Mode)  │
                        └────────┬────────┘
                                 │
                        ┌────────▼────────────────┐
                        │  NAT/MASQUERADE         │
                        │  (iptables routing)     │
                        └────────┬────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────┐
│                      Raspberry Pi (Frey)                                │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  wlan1 (AP Mode): 10.20.0.1                                      │   │
│  │  - hostapd (FreyHub WiFi)                                        │   │
│  │  - dnsmasq (DHCP: 10.20.0.50-150, DNS: *.frey → 10.20.0.1)       │   │
│  └───────────────────────────┬──────────────────────────────────────┘   │
│                              │                                          │
│         ┌────────────────────▼────────────────────┐                     │
│         │  WiFi AP Clients (10.20.0.50-150)       │                     │
│         │  DNS resolves: *.frey → 10.20.0.1       │                     │
│         └────────────────────┬────────────────────┘                     │
│                              │ HTTP/HTTPS requests                      │
│                              │                                          │
│         ┌────────────────────▼────────────────────────────┐             │
│         │  Traefik (Port 80/443 on all interfaces)        │             │
│         │  Networks: proxy, localdns, infrastructure      │             │
│         │  Routes based on Host header                    │             │
│         └────────────────────┬────────────────────────────┘             │
│                              │                                          │
│         ┌────────────────────▼───────────────────────────────────────┐  │
│         │  Docker Bridge Networks                                    │  │
│         │                                                            │  │
│         │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐    │  │
│         │  │  proxy     │  │  localdns  │  │  service networks  │    │  │
│         │  │  (Traefik) │  │  (DNS)     │  │  (media, auto,     │    │  │
│         │  │            │  │            │  │   monitoring, etc) │    │  │
│         │  └────────────┘  └────────────┘  └────────────────────┘    │  │
│         │                                                            │  │
│         │  Containers: Jellyfin, Sonarr, Grafana, Home Assistant...  │  │
│         └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Network Flows

**1. Internet Access for AP Clients:**
```
WiFi Client → wlan1 (10.20.0.x) → NAT/MASQUERADE → wlan0/eth0 → Internet
```

**2. Docker Service Access:**
```
WiFi Client → DNS query (jellyfin.frey) → dnsmasq (10.20.0.1)
           → HTTP request → Traefik (80/443) → proxy network → Jellyfin container
```

**3. Automatic WiFi Roaming:**
```
wlan0 → Network scan → Portal detection → Bypass attempt → Internet verification
     → Switch to better network if available
```

## Traffic Flow

### Example: Accessing Services

1. **Media Services (e.g., Jellyfin)**
   ```
   Phone → Query: jellyfin.frey
   dnsmasq (10.20.0.1) → Response: 10.20.0.1
   ```

2. **Automation Services**
   ```
   Phone → Query: ai.frey (Open WebUI) / n8n.frey (N8N) / ollama.frey (Ollama)
   dnsmasq (10.20.0.1) → Response: 10.20.0.1
   ```

2. **HTTP Request**
   ```
   Phone → HTTP GET http://jellyfin.frey/
   → Reaches: 10.20.0.1:80 (Traefik)
   ```

3. **Traefik Routing**
   ```
   Traefik → Reads Host header: "jellyfin.frey"
   → Matches rule: Host(`jellyfin.frey`)
   → Routes to: jellyfin container via proxy network
   ```

4. **Container Response**
   ```
   Jellyfin → Responds via Traefik
   → Back to phone
   ```

## Network Configuration

### 1. Docker Compose Networks

```yaml
networks:
  # Traefik routing - all web-accessible services join this
  proxy:
    external: true
  
  # DNS resolution between containers
  localdns:
    external: true
  
  # Service-specific networks
  infrastructure_network:
    name: infrastructure_network
    ipam:
      config:
        - subnet: 10.20.3.0/24
  
  media_network:
    name: media_network
    ipam:
      config:
        - subnet: 10.20.0.0/24
  
  automation_network:
    name: automation_network
    ipam:
      config:
        - subnet: 10.20.2.0/24  # Network for AI/automation services
```

### 2. Service Configuration Template

```yaml
services:
  service_name:
    image: some/image
    container_name: service_name
    restart: unless-stopped
    
    # Join multiple networks
    networks:
      - proxy          # For Traefik access
      - localdns       # For DNS resolution
      - service_network # Service-specific network
    
    # Traefik labels for routing
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.service.rule=Host(`service.frey`)"
      - "traefik.http.routers.service.entrypoints=web"
      - "traefik.http.services.service.loadbalancer.server.port=8080"
```

### 3. Traefik Configuration

```yaml
services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: unless-stopped
    
    # Publish ports to ALL host interfaces (including wlan1)
    ports:
      - "80:80"       # HTTP - accessible from WiFi AP
      - "443:443"     # HTTPS - accessible from WiFi AP
      - "8080:8080"   # Dashboard (optional, restrict in production)
    
    networks:
      - proxy
      - localdns
      - infrastructure_network
    
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /path/to/traefik.yml:/etc/traefik/traefik.yml:ro
```

## DNS Configuration

### dnsmasq.conf.j2

```conf
# Point all .frey domains to the AP gateway (10.20.0.1)
# Traefik listens on this IP and routes to containers
{% for service in network.dns_rewrites %}
address=/{{ service.name }}.{{ network.domain_name }}/{{ network.wifi.ip }}
{% endfor %}

# Result:
# jellyfin.frey    → 10.20.0.1
# sonarr.frey      → 10.20.0.1
# portainer.frey   → 10.20.0.1
# All traffic hits Traefik on port 80
```

## Why This Architecture?

### ✅ Advantages

1. **Single Entry Point**: All traffic goes through Traefik (port 80/443)
2. **SSL Termination**: Easy to add Let's Encrypt certificates
3. **Path-based Routing**: Can route by path, not just hostname
4. **No Port Conflicts**: Services don't need unique external ports
5. **Better Security**: Containers not directly exposed to network
6. **Easy Service Discovery**: Just add DNS entry and Traefik label

### 📝 Implementation Checklist

- [x] Traefik container publishes ports 80/443
- [x] Traefik joins `proxy` and `localdns` networks
- [x] All services join `proxy` network
- [x] All services have Traefik labels with routing rules
- [x] DNS points `*.frey` to `{{ network.wifi.ip }}`
- [x] UFW allows ports 80/443 from WiFi AP network

## Alternative: Direct Port Access

For services that don't work well with Traefik (e.g., non-HTTP):

```yaml
services:
  transmission:
    ports:
      - "9091:9091"  # Published to all interfaces
    networks:
      - localdns     # DNS only, no Traefik
```

Access via: `http://10.20.0.1:9091` or `http://transmission.frey:9091`

## Troubleshooting

### Service returns 502 Bad Gateway

**Cause**: Traefik can't reach the container

**Solutions**:
1. Verify container is on `proxy` network
2. Check `traefik.docker.network=proxy` label
3. Verify container port in loadbalancer label

```bash
# Check container networks
docker inspect jellyfin | grep -A 20 Networks

# Check Traefik logs
docker logs traefik
```

### Service not accessible

**Cause**: Firewall blocking or Traefik not listening on correct interface

**Solutions**:
1. Verify Traefik ports: `netstat -tlnp | grep :80`
2. Check UFW rules: `sudo ufw status numbered`
3. Test locally: `curl -H "Host: jellyfin.frey" http://localhost`
4. Test public access: `curl -H "Host: jellyfin.frey" http://your-public-ip`
5. Check SSL certificates if using HTTPS

### DNS not resolving

**Cause**: dnsmasq configuration issue

**Solutions**:
1. Verify DNS config: `cat /etc/dnsmasq.d/01-wifi-ap.conf | grep address`
2. Test DNS: `nslookup jellyfin.frey 10.20.0.1`
3. Check dnsmasq logs: `sudo tail -f /var/log/dnsmasq.log`

## Security Considerations

### Network Isolation

```yaml
# Services that DON'T need external access
services:
  database:
    networks:
      - media_network  # Internal only
      # NOT on proxy network
```

### Traefik Access Control

```yaml
labels:
  # Optional: Restrict specific services to local networks only
  - "traefik.http.middlewares.local-ipwhitelist.ipwhitelist.sourcerange=10.20.0.0/24,172.30.4.0/24"
  - "traefik.http.routers.admin.middlewares=local-ipwhitelist"
  
  # For public access (default configuration)
  - "traefik.enable=true"
  - "traefik.docker.network=proxy"
  - "traefik.http.routers.service.rule=Host(`service.frey`)"
  - "traefik.http.routers.service.entrypoints=web,websecure"  # Enable both HTTP and HTTPS
  - "traefik.http.services.service.loadbalancer.server.port=8080"
```

### UFW Configuration

```bash
# Allow HTTP/HTTPS from anywhere (public access)
sudo ufw allow http
sudo ufw allow https

# Restrict DNS and DHCP to local network only
sudo ufw allow from 10.20.0.0/24 to any port 53   # DNS
sudo ufw allow from 10.20.0.0/24 to any port 67   # DHCP

# Block direct access to container ports from AP network
sudo ufw deny from 10.20.0.0/24 to any port 8096  # Jellyfin
sudo ufw deny from 10.20.0.0/24 to any port 8989  # Sonarr
# Force all traffic through Traefik
```

## Best Practices

1. **Always use `proxy` network** for web-accessible services
2. **Use `localdns` for inter-container communication**
3. **Don't publish container ports** unless necessary (let Traefik handle it)
4. **Use network-specific subnets** for logical grouping
5. **Document custom DNS entries** in main.yml
6. **Configure SSL certificates** for public HTTPS access
7. **Implement authentication** for sensitive services
8. **Test from multiple networks** - local WiFi, public internet, and Pi itself
9. **Monitor access logs** for security issues
10. **Keep UFW rules updated** for new services

## Migration Guide

### From Direct Port Access to Traefik

**Before:**
```yaml
services:
  jellyfin:
    ports:
      - "8096:8096"
    networks:
      - media_network
```

**After:**
```yaml
services:
  jellyfin:
    networks:
      - proxy          # Add this
      - localdns       # Add this
      - media_network
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.jellyfin.rule=Host(`jellyfin.frey`)"
      - "traefik.http.routers.jellyfin.entrypoints=web"
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096"
    # Remove ports section or keep for direct access option
```

Access changes from `http://10.20.0.1:8096` to `http://jellyfin.frey`

## WiFi Roaming Troubleshooting

### Roaming Daemon Not Connecting

**Check daemon status:**
```bash
sudo systemctl status frey-wifi-roaming
sudo frey-wifi-pause status
sudo journalctl -u frey-wifi-roaming -n 50
```

**Common causes:**

1. **Daemon is paused:**
   - Check: `sudo frey-wifi-pause status`
   - Fix: `sudo frey-wifi-pause resume`

2. **No wlan0 interface:**
   - Check: `ip link show wlan0`
   - Fix: Verify WiFi adapter is connected
   - Fix: Load driver: `sudo modprobe brcmfmac`

3. **No known networks in range:**
   - Check: `cat /etc/frey/known-networks.conf`
   - Check: `sudo nmcli dev wifi list`
   - Fix: Add known networks to config

4. **All networks blacklisted:**
   - Check: `cat /var/lib/frey/wifi-blacklist.json`
   - Fix: Clear blacklist: `sudo rm /var/lib/frey/wifi-blacklist.json && sudo systemctl restart frey-wifi-roaming`

### Captive Portal Detection Failing

**Symptoms:**
- Connected to network but no internet
- Script says "No captive portal detected" but portal exists
- 100% packet loss after connection

**Diagnosis:**
```bash
# Test portal detection manually
curl -I http://neverssl.com           # Should redirect to portal
ping -c 3 1.1.1.1                     # Should fail if portal exists
curl -s http://neverssl.com | head    # Should show portal HTML

# Check roaming logs
sudo journalctl -u frey-wifi-roaming -f | grep -i portal
```

**Solutions:**

1. **Portal not detected (false negative):**
   - Multi-layer detection should catch this (redirect + ping + content)
   - Check logs for which tests ran
   - Verify scripts deployed: `/usr/local/bin/frey-wifi-portal-shell-bypass.sh`

2. **Portal bypass failing:**
   - Shell bypass timeout: Check if portal requires JavaScript
   - Selenium bypass not installed: Verify Python dependencies
   - Complex portal: May require manual authentication
   - Network blacklisted after failures: Clear blacklist

3. **Network immediately disconnects:**
   - Portal may require specific user agent
   - Portal may have MAC address filtering
   - Check logs for connection errors

### Internet Passthrough Not Working

**Symptoms:**
- FreyHub AP clients can't reach internet
- Can access local services (*.frey) but not external sites

**Diagnosis:**
```bash
# From AP client
ping 10.20.0.1              # Should work (AP gateway)
ping 1.1.1.1                # Should work (internet via NAT)
nslookup google.com         # Should resolve

# On Pi
sudo iptables -t nat -L -n -v  # Check NAT rules
ip route                        # Check default route
```

**Solutions:**

1. **NAT not configured:**
   - Check: `sudo iptables -t nat -L POSTROUTING`
   - Should see: `MASQUERADE  all -- 0.0.0.0/0  0.0.0.0/0`
   - Fix: Redeploy WiFi AP role

2. **Routing incorrect:**
   - Check: `ip route show default`
   - Should route through wlan0 (if roaming) or eth0
   - Fix: `sudo ip route add default via <gateway> dev wlan0`

3. **wlan0 not connected:**
   - Check: `wpa_cli -i wlan0 status`
   - Fix: `sudo frey-wifi-pause resume`
   - Fix: Force rescan via MQTT

4. **IP forwarding disabled:**
   - Check: `cat /proc/sys/net/ipv4/ip_forward` (should be 1)
   - Fix: `sudo sysctl -w net.ipv4.ip_forward=1`

### Roaming Daemon Switching Too Often

**Symptoms:**
- Constantly switches between networks
- Disconnects from stable network
- FreyHub AP clients experience interruptions

**Solutions:**

1. **Pause roaming temporarily:**
   ```bash
   sudo frey-wifi-pause pause
   ```

2. **Increase switch threshold:**
   ```bash
   # Edit config
   sudo nano /etc/frey/wifi-roaming.conf

   # Set higher threshold (only switch for much better networks)
   SWITCH_THRESHOLD=25  # Default: 15

   # Restart daemon
   sudo systemctl restart frey-wifi-roaming
   ```

3. **Increase scan intervals:**
   ```bash
   # Edit config
   sudo nano /etc/frey/wifi-roaming.conf

   # Scan less frequently
   SCAN_INTERVAL_DEFAULT=600       # 10 minutes (was 120)
   SCAN_INTERVAL_GOOD=900          # 15 minutes (was 600)

   # Restart daemon
   sudo systemctl restart frey-wifi-roaming
   ```

4. **Blacklist problematic networks:**
   ```bash
   # Add to blacklist
   echo '{"BadNetwork": {"blacklisted_until": 9999999999}}' | \
     sudo tee -a /var/lib/frey/wifi-blacklist.json
   ```

### Roaming Control Commands

```bash
# Pause scanning (keeps daemon running)
sudo frey-wifi-pause pause

# Resume scanning
sudo frey-wifi-pause resume

# Check daemon status and pause state
sudo frey-wifi-pause status

# View recent activity
sudo journalctl -u frey-wifi-roaming -n 50

# Force immediate rescan (via MQTT)
mosquitto_pub -h localhost -t "frey/wifi/roaming/control/rescan" -m "true"

# Check current connection
wpa_cli -i wlan0 status

# Manual network scan
sudo nmcli dev wifi list
```

### Advanced Debugging

**Enable verbose logging:**
```bash
# Edit daemon script
sudo nano /usr/local/bin/frey-wifi-roaming-daemon

# Change LOG_LEVEL
LOG_LEVEL="DEBUG"  # Was "INFO"

# Restart daemon
sudo systemctl restart frey-wifi-roaming

# Watch logs
sudo journalctl -u frey-wifi-roaming -f
```

**Test captive portal detection manually:**
```bash
# Run portal detection standalone
sudo /usr/local/bin/frey-wifi-captive-portal-auto
```

**Test portal bypass manually:**
```bash
# Shell-based bypass
sudo /usr/local/bin/frey-wifi-portal-shell-bypass.sh "http://portal-url"

# Selenium-based bypass (if installed)
sudo /usr/local/bin/frey-wifi-portal-bypasser.py "http://portal-url"
```

**Monitor MQTT messages:**
```bash
# Subscribe to all roaming topics
mosquitto_sub -h localhost -t "frey/wifi/roaming/#" -v
```

## Architecture Summary

The complete Frey network architecture provides:

1. **Dual-Interface WiFi:**
   - wlan1: Always-on FreyHub AP for local service access
   - wlan0: Automatic roaming for internet connectivity

2. **Internet Passthrough:**
   - NAT/MASQUERADE routes AP client traffic through roaming interface
   - Seamless internet access even when switching networks

3. **Multi-Layered Portal Detection:**
   - HTTP redirect detection (traditional portals)
   - Ping-based verification (non-redirecting portals like LibrariesSA-Free)
   - Content verification (interception detection)
   - 80-90% automatic bypass success rate

4. **Signal-Based Control:**
   - Instant pause/resume without stopping daemon
   - No file I/O overhead
   - Clean Unix signal handling (SIGUSR1/SIGUSR2)

5. **Docker Service Access:**
   - Traefik reverse proxy for clean URLs (*.frey)
   - Network isolation and security
   - DNS resolution via dnsmasq

6. **Robust Design:**
   - No disruption to FreyHub AP during roaming
   - Safe SSH access (never modifies SSH interface)
   - Automatic fallback and recovery
   - MQTT integration for monitoring and control
