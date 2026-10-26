# Network Architecture: WiFi AP + Docker Services

## Overview

This document explains how WiFi AP clients access Docker containers through Traefik.

## Network## Security

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
- [x] Firewall configured via security role────────────────────────────────────────────────────────┐
│ WiFi AP Clients (10.20.0.x)                                │
└────────────────────────┬────────────────────────────────────┘
                         │ DNS: *.frey → 10.20.0.1
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ Raspberry Pi (wlan1: 10.20.0.1)                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Traefik (Port 80/443 published to host)             │  │
│  │ Networks: proxy, localdns, infrastructure_network   │  │
│  └───────────────────────┬──────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────┴──────────────────────────────┐  │
│  │ Docker Bridge Networks                               │  │
│  │                                                       │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │  │
│  │  │ proxy       │  │ localdns     │  │ media_net   │ │  │
│  │  │ (Traefik    │  │ (DNS         │  │ (Services)  │ │  │
│  │  │  routing)   │  │  resolution) │  │             │ │  │
│  │  └─────────────┘  └──────────────┘  └─────────────┘ │  │
│  │                                                       │  │
│  │  Containers: Jellyfin, Sonarr, Portainer, etc.      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
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
