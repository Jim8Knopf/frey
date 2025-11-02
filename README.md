# 🏰 Frey - Raspberry Pi 5 Home Server

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible](https://img.shields.io/badge/Ansible-2.15%2B-EE0000?logo=ansible)](https://www.ansible.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://www.docker.com/)

**A comprehensive, production-ready Ansible automation project that transforms your Raspberry Pi 5 into a fully-featured home server with media management, home automation, monitoring, and intelligent WiFi capabilities.**

---

## 🎯 What is Frey?

Frey is an Infrastructure-as-Code solution that deploys a complete, self-hosted home server stack on a Raspberry Pi 5. With a single command, you get:

- 📺 **Media Server** - Stream movies, TV shows, music, and audiobooks
- 🏠 **Home Automation** - Control smart devices and automate your home
- 🔐 **Single Sign-On** - One login for all services via Authentik
- 📊 **Monitoring** - Real-time metrics, logs, and alerts
- 🌐 **WiFi Access Point** - Dual-interface WiFi with automatic roaming
- 🤖 **AI Services** - Local LLM inference with Ollama
- 📸 **Photo Management** - Self-hosted Google Photos alternative
- 🍳 **Recipe Manager** - Digital cookbook with meal planning

**Everything configured, integrated, and production-ready in under 30 minutes.**

---

## ✨ Key Features

### 🎬 Media Management
- **Jellyfin** - Netflix-like media streaming with hardware transcoding
- ***arr Suite** - Automatic TV/movie/music downloading and organization
  - Sonarr (TV shows), Radarr (movies), Lidarr (music), Bazarr (subtitles)
- **Audiobookshelf** - Beautiful audiobook and podcast server
- **Jellyseerr** - User-friendly media request system
- **qBittorrent** - Torrent download client with VPN support

### 🏠 Home Automation
- **Home Assistant** - Smart home control and automation
- **Piper TTS** - Natural text-to-speech (Wyoming protocol)
- **Wyoming Whisper** - Speech-to-text (optional, resource-intensive)
- **n8n** - Visual workflow automation (Zapier alternative)
- **MQTT** - Device messaging and integration

### 🤖 AI & Automation
- **Ollama** - Local Large Language Model inference
- **Open WebUI** - ChatGPT-like interface for Ollama
- **n8n Workflows** - Automate everything with 300+ integrations

### 🔐 Infrastructure & Security
- **Traefik** - Automatic reverse proxy and routing
- **Authentik** - Single Sign-On (OAuth/OIDC/LDAP)
- **Portainer** - Docker container management
- **Dockge** - Docker Compose stack editor
- **AdGuard Home** - DNS server with ad blocking
- **UFW + Fail2Ban** - Firewall and intrusion prevention

### 📊 Monitoring & Analytics
- **Grafana** - Beautiful dashboards and visualizations
- **Prometheus** - Metrics collection and time-series database
- **Loki** - Centralized log aggregation
- **Uptime Kuma** - Service uptime monitoring with alerts
- **Speedtest Tracker** - Internet performance tracking
- **Watchtower** - Automatic container updates

### 🌐 WiFi Capabilities
- **FreyHub Access Point** - Dual-interface WiFi (wlan1 AP + eth0/wlan0 client)
- **Automatic WiFi Roaming** - Intelligent public WiFi management
  - Automatic captive portal bypass (80-90% success rate)
  - Internet verification (filters non-internet networks)
  - Network scoring and intelligent selection
  - Adaptive scanning (aggressive → conservative based on connection)
  - Home Assistant/n8n integration via MQTT
  - Network history tracking and blacklisting

### 📸 Photos & Media
- **Immich** - Self-hosted Google Photos alternative
  - Mobile auto-backup (iOS/Android)
  - Face recognition and object detection
  - Hardware acceleration (Raspberry Pi 5)
  - OAuth SSO integration

### 🍳 Recipe Management
- **Mealie** - Digital cookbook and meal planner
  - Recipe scraping from URLs
  - Shopping list generation
  - Meal planning calendar

---

## 🚀 Quick Start

### Prerequisites

- Raspberry Pi 5 (4GB+ RAM recommended)
- MicroSD card (32GB+) or SSD
- Raspberry Pi OS Lite 64-bit installed
- Ansible installed on control machine: `pip install ansible`
- SSH access configured

### Installation

```bash
# 1. Clone repository
git clone https://github.com/Jim8Knopf/frey.git
cd frey

# 2. Configure inventory (set your Pi's IP)
nano inventory/hosts.yml

# 3. Configure main settings
nano group_vars/all/main.yml

# 4. Create vault password file
openssl rand -base64 32 > .vault_pass
chmod 600 .vault_pass

# 5. Configure secrets (passwords, API keys)
ansible-vault edit group_vars/all/secrets.yml

# 6. Deploy everything
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

**Deployment time:** 15-30 minutes (depends on internet speed)

### Post-Deployment

After deployment, complete these manual steps:

1. **Create Authentik admin account** - `http://auth.frey`
2. **Configure service SSO** - Grafana (automatic), Home Assistant, Immich, Audiobookshelf, Jellyfin

**See:** [QUICK_SETUP.md](docs/QUICK_SETUP.md) for step-by-step guide

---

## 📚 Documentation

- **[QUICK_SETUP.md](docs/QUICK_SETUP.md)** - Get running in 30 minutes ⚡
- **[USER_GUIDE.md](docs/USER_GUIDE.md)** - Complete feature reference 📖
- **[WIFI_ROAMING_SETUP.md](docs/WIFI_ROAMING_SETUP.md)** - WiFi automation guide 🌐
- **[POST_INSTALLATION_MANUAL_STEPS.md](docs/POST_INSTALLATION_MANUAL_STEPS.md)** - Detailed SSO setup 🔧
- **[SETUP_CHECKLIST.md](docs/SETUP_CHECKLIST.md)** - Step-by-step checklist ✅
- **[CLAUDE.md](CLAUDE.md)** - Developer guide for Claude Code 🤖

---

## 🏗️ Architecture

### System Design

```
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT DEVICES                           │
│  (Phones, Laptops, Tablets via WiFi or Ethernet)           │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                  NETWORK LAYER                              │
│  ┌──────────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │  WiFi AP     │  │  AdGuard    │  │  Traefik Proxy   │   │
│  │  FreyHub     │  │  DNS        │  │  Routing         │   │
│  │  10.20.0.1   │  │  .frey      │  │  Port 80/443     │   │
│  └──────────────┘  └─────────────┘  └──────────────────┘   │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│              APPLICATION LAYER                              │
│  Media • Automation • Infrastructure • Monitoring • Photos  │
│  40+ Docker containers orchestrated by Ansible             │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                 STORAGE LAYER                               │
│         /opt/frey/ (Base Directory)                         │
│  Config • Media Library • Photos • Docker Stacks           │
└─────────────────────────────────────────────────────────────┘
```

### Service Organization

**Infrastructure** (Traefik, Authentik, Portainer, Dockge, AdGuard)
- Core services that everything else depends on
- Reverse proxy, SSO, container management, DNS

**Media** (Jellyfin, Sonarr, Radarr, Audiobookshelf, qBittorrent)
- Media streaming, downloading, and organization
- Automatic quality upgrades and library management

**Automation** (Home Assistant, n8n, Ollama, Open WebUI)
- Smart home control and workflow automation
- Local AI inference and voice services

**Monitoring** (Grafana, Prometheus, Loki, Uptime Kuma)
- System metrics, logs, and alerts
- Performance tracking and health monitoring

**Photos** (Immich)
- Photo and video management
- Face recognition, object detection, mobile backup

**WiFi** (hostapd, dnsmasq, roaming daemon)
- Dual-interface WiFi access point
- Automatic roaming and captive portal bypass

---

## 📋 Service URLs

All services accessible via friendly `.frey` domains:

| Category | Service | URL |
|----------|---------|-----|
| **Infrastructure** | Traefik Dashboard | http://traefik.frey:8082 |
| | Authentik (SSO) | http://auth.frey |
| | Portainer | http://portainer.frey |
| | Dockge | http://dockge.frey |
| | AdGuard Home | http://adguard.frey |
| **Media** | Jellyfin | http://jellyfin.frey |
| | Sonarr | http://sonarr.frey |
| | Radarr | http://radarr.frey |
| | Audiobookshelf | http://audiobookshelf.frey |
| | Jellyseerr | http://jellyseerr.frey |
| **Automation** | Home Assistant | http://homeassistant.frey |
| | n8n | http://n8n.frey |
| | Open WebUI | http://ai.frey |
| **Monitoring** | Grafana | http://grafana.frey |
| | Prometheus | http://prometheus.frey |
| | Uptime Kuma | http://uptime-kuma.frey |
| **Photos** | Immich | http://immich.frey |
| **Cookbook** | Mealie | http://cookbook.frey |

---

## ⚙️ Configuration

### Feature Toggles

Enable/disable entire service stacks in `group_vars/all/main.yml`:

```yaml
features:
  infrastructure: true      # Traefik, Portainer, Authentik
  networking: true          # AdGuard DNS
  wifi_access_point: true   # FreyHub AP
  media: true               # Jellyfin, *arr suite
  monitoring: true          # Grafana, Prometheus
  automation: true          # n8n, Ollama
  homeassistant: true       # Home Assistant + voice
  immich: true              # Photo management
  cookbook: true            # Recipe manager
  authentication: false     # Enable Authentik (after infrastructure)
```

### WiFi Configuration

```yaml
network:
  wifi:
    ssid: "FreyHub"
    password: "{{ wifi_ap.password }}"  # In secrets.yml
    interface: "wlan1"       # AP interface
    client_interface: "eth0" # Internet interface

    # Automatic roaming (optional)
    roaming:
      enabled: false         # Set to true to enable
      mqtt_topic: "frey/wifi/roaming"

# Pre-configured networks
networks.wifi.known:
  - ssid: "Home WiFi"
    password: "myPassword123"
    priority: 100
```

### Storage Paths

```yaml
storage:
  base_dir: /opt/frey
  appdata_dir: /opt/frey/appdata  # Service configs
  stacks: /opt/frey/stacks        # Docker Compose files

# Media organized under /opt/frey/media/
# - movies, tv, music, audiobooks, podcasts
```

---

## 🔧 Common Tasks

### Service Management

```bash
# SSH into Pi
ssh pi@frey

# View all containers
docker ps

# Start/stop/restart service
docker restart jellyfin

# View logs
docker logs -f jellyfin

# Restart entire stack
cd /opt/frey/stacks/media
docker compose restart
```

### Selective Deployment

```bash
# Deploy only specific services
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags wifi
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring

# Dry run (check mode)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check
```

### Updating Configuration

```bash
# Edit main configuration
nano group_vars/all/main.yml

# Edit secrets
ansible-vault edit group_vars/all/secrets.yml

# Apply changes
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

---

## 🔐 Security Features

- **UFW Firewall** - Automatic port configuration based on enabled services
- **Fail2Ban** - Brute-force attack prevention
- **Ansible Vault** - Encrypted secrets management
- **Single Sign-On** - Centralized authentication via Authentik
- **DoH Blocking** - Forces clients to use local DNS (prevents DNS bypass)
- **Isolated Networks** - Docker networks separate services
- **User Isolation** - Each stack runs under dedicated user/group

---

## 📊 Monitoring & Observability

- **System Metrics** - CPU, RAM, disk, network via Prometheus + Node Exporter
- **Container Stats** - Per-container resource usage via cAdvisor
- **Centralized Logs** - All logs aggregated in Loki, queryable via Grafana
- **Service Health** - HTTP/TCP monitoring via Uptime Kuma
- **Internet Speed** - Scheduled speed tests with historical data
- **Auto-Updates** - Watchtower keeps containers up-to-date
- **Alerting** - Grafana alerts with notification integrations

---

## 🗂️ Project Structure

```
frey/
├── README.md                    # This file
├── ansible.cfg                  # Ansible configuration
├── playbooks/
│   └── site.yml                 # Main playbook
├── inventory/
│   └── hosts.yml                # Target Pi configuration
├── group_vars/
│   └── all/
│       ├── main.yml            # Main configuration
│       └── secrets.yml         # Encrypted secrets (Ansible Vault)
├── roles/                       # Service deployment roles
│   ├── infrastructure/         # Traefik, Portainer, Authentik
│   ├── media/                  # Jellyfin, *arr suite
│   ├── automation/             # n8n, Ollama, Home Assistant
│   ├── monitoring/             # Grafana, Prometheus
│   ├── immich/                 # Photo management
│   ├── cookbook/               # Recipe manager
│   ├── wifi_access_point/      # WiFi AP + roaming
│   ├── networking/             # AdGuard DNS
│   ├── security/               # UFW, Fail2Ban
│   └── docker_minimal/         # Base Docker setup
├── docs/                        # Documentation
│   ├── QUICK_SETUP.md          # 30-minute setup guide
│   ├── USER_GUIDE.md           # Comprehensive reference
│   ├── WIFI_ROAMING_SETUP.md   # WiFi automation guide
│   └── ...
└── scripts/                     # Maintenance utilities
```

---

## 🎯 Use Cases

### Home Media Server
- Stream your movie/TV collection with Jellyfin
- Automatically download new episodes with Sonarr
- Listen to audiobooks with Audiobookshelf
- Request content via Jellyseerr

### Smart Home Hub
- Control lights, switches, sensors via Home Assistant
- Voice announcements with Piper TTS
- Automate workflows with n8n
- Monitor everything with Grafana

### Travel Companion
- FreyHub AP provides SSH access anywhere
- Automatic WiFi roaming connects to best available network
- Captive portal bypass (airports, hotels, cafes)
- Access media library offline

### Development Server
- n8n for workflow automation and prototyping
- Local Ollama LLMs for AI development
- Portainer/Dockge for container management
- Grafana for metrics visualization

---

## 🤝 Contributing

Contributions welcome! To contribute:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

**Please include:**
- Clear description of changes
- Test results (deployment logs)
- Updated documentation if needed

---

## 🐛 Troubleshooting

### Service won't start
```bash
docker logs <service>
docker ps -a
```

### Can't access via .frey domains
```bash
# Check DNS
nslookup jellyfin.frey 10.20.0.1

# Check Traefik
curl -I http://traefik.frey:8082
```

### WiFi AP not working
```bash
sudo systemctl status hostapd
sudo systemctl status dnsmasq
sudo journalctl -u hostapd -n 50
```

**See:** [USER_GUIDE.md - Troubleshooting](docs/USER_GUIDE.md#troubleshooting) for detailed solutions

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details

---

## 🙏 Acknowledgments

Built with:
- [Ansible](https://www.ansible.com/) - Infrastructure automation
- [Docker](https://www.docker.com/) - Container platform
- [Traefik](https://traefik.io/) - Reverse proxy
- [Authentik](https://goauthentik.io/) - SSO authentication
- [Jellyfin](https://jellyfin.org/) - Media server
- [Home Assistant](https://www.home-assistant.io/) - Home automation
- [Grafana](https://grafana.com/) - Observability platform
- [Immich](https://immich.app/) - Photo management
- And many more amazing open-source projects!

---

## 📞 Support

- **Documentation**: [docs/](docs/) directory
- **Issues**: [GitHub Issues](https://github.com/Jim8Knopf/frey/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Jim8Knopf/frey/discussions)

---

**🎉 Transform your Raspberry Pi 5 into a powerful home server with a single command!**

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```
