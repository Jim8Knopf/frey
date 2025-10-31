# 📖 Frey User Guide

**Complete reference for understanding, configuring, and managing your Frey system**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture-overview)
3. [Service Categories](#service-categories)
4. [Special Features](#special-features)
5. [Configuration Guide](#configuration-guide)
6. [Common Tasks](#common-tasks)
7. [Advanced Topics](#advanced-topics)
8. [Troubleshooting](#troubleshooting)

---

## Introduction

### What is Frey?

Frey is a comprehensive Ansible-based automation project that transforms your Raspberry Pi 5 into a fully-featured home server. It provides:

- **Media Management** - Movies, TV shows, music, audiobooks with automatic downloading and organization
- **Home Automation** - Smart home control, voice assistants, and workflow automation
- **Infrastructure Services** - Reverse proxy, container management, and SSO authentication
- **Monitoring & Analytics** - System metrics, logging, and uptime tracking
- **WiFi Access Point** - Dual-interface WiFi with automatic roaming and captive portal bypass

### Key Benefits

- **Infrastructure as Code** - Entire system defined in version-controlled configuration files
- **Single Sign-On** - Authenticate once, access all services via Authentik SSO
- **Automatic Updates** - Watchtower keeps Docker containers up-to-date
- **Local DNS** - Access services via friendly names like `http://jellyfin.frey`
- **Fully Automated** - Deploy complete stack with a single command

### Quick Links

- **Quick Setup**: [QUICK_SETUP.md](QUICK_SETUP.md) - Get running in 30 minutes
- **WiFi Roaming**: [WIFI_ROAMING_SETUP.md](WIFI_ROAMING_SETUP.md) - Automatic WiFi management
- **Manual Steps**: [POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md) - Detailed post-deployment configuration
- **Setup Checklist**: [SETUP_CHECKLIST.md](SETUP_CHECKLIST.md) - Step-by-step deployment tracking

---

## Architecture Overview

### System Design

Frey uses a layered architecture with Docker containers orchestrated by Ansible:

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
│  │  (wlan1)     │  │  DNS        │  │  (Routing)       │   │
│  │  10.20.0.1   │  │  .frey      │  │  Port 80/443     │   │
│  └──────────────┘  └─────────────┘  └──────────────────┘   │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│              APPLICATION LAYER                              │
│  ┌──────────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │ Media Stack  │  │ Automation  │  │  Infrastructure  │   │
│  │ Jellyfin     │  │ Home Asst   │  │  Authentik SSO   │   │
│  │ *arr Suite   │  │ n8n         │  │  Portainer       │   │
│  │ Audiobooksh  │  │ Ollama AI   │  │  Dockge          │   │
│  └──────────────┘  └─────────────┘  └──────────────────┘   │
│  ┌──────────────┐  ┌─────────────┐                         │
│  │ Monitoring   │  │  Photos     │                         │
│  │ Grafana      │  │  Immich     │                         │
│  │ Prometheus   │  │             │                         │
│  └──────────────┘  └─────────────┘                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                 STORAGE LAYER                               │
│         /opt/frey/ (Base Directory)                         │
│  ┌──────────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │   appdata/   │  │   media/    │  │    stacks/       │   │
│  │  (configs)   │  │  (content)  │  │  (compose files) │   │
│  └──────────────┘  └─────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Network Architecture

**Docker Networks:**
- **proxy** - Traefik reverse proxy network (all web services connect here)
- **localdns** - DNS resolution network (services needing .frey DNS)
- **media_network** - Isolated network for media services (10.20.0.0/24)
- **automation_network** - Network for automation services
- **monitoring_network** - Network for monitoring stack

**WiFi Networks:**
- **wlan1** (AP mode) - FreyHub access point (10.20.0.1)
- **eth0/wlan0** (Client mode) - Internet connection interface

**Service Discovery:**
- Traefik routes `http://<service>.frey` to appropriate containers
- AdGuard Home provides DNS resolution for `.frey` domain
- All services accessible without remembering ports

### Directory Structure

```
/opt/frey/                    # Base directory (configurable)
├── appdata/                  # Service configuration and data
│   ├── jellyfin/            # Jellyfin config
│   ├── sonarr/              # Sonarr config
│   ├── grafana/             # Grafana config
│   └── ...                  # One directory per service
├── stacks/                   # Docker Compose files
│   ├── infrastructure/      # Infrastructure compose
│   ├── media/               # Media compose
│   ├── automation/          # Automation compose
│   └── monitoring/          # Monitoring compose
├── media/                    # Media library
│   ├── movies/              # Movie files
│   ├── tv/                  # TV show files
│   ├── music/               # Music library
│   ├── audiobooks/          # Audiobook library
│   └── podcasts/            # Podcast episodes
├── downloads/                # Download client staging
└── photos/                   # Immich photo library
```

### User & Group System

Each service stack runs under a dedicated user for security and permission management:

| Stack | User | UID | Group | GID |
|-------|------|-----|-------|-----|
| Infrastructure | infrastructure_manager | 46372 | infrastructure | 46372 |
| Media | media_manager | 63342 | media | 63342 |
| Automation | automation_manager | 463288672 | automation | 2886 |
| Monitoring | monitoring_manager | 12341 | monitoring | 12341 |
| Photos | photos_manager | 74686 | photos | 74686 |
| Home Assistant | homeassistant_manager | 8123 | homeassistant | 8123 |

---

## Service Categories

### Infrastructure Services

**Purpose:** Core system services that everything else depends on

#### Traefik (Reverse Proxy)
- **URL:** `http://traefik.frey:8082`
- **Purpose:** Routes HTTP traffic to services based on domain names
- **Key Features:**
  - Automatic service discovery via Docker labels
  - HTTP routing without port numbers
  - Dashboard showing all routes and services
  - SSL termination (future enhancement)

**Configuration:**
```yaml
infrastructure:
  services:
    traefik:
      enabled: true
      ports:
        http: 80        # Main HTTP entry point
        https: 443      # HTTPS (future)
        dashboard: 8082 # Management dashboard
```

#### Portainer (Container Management)
- **URL:** `http://portainer.frey`
- **Purpose:** Web-based Docker container management
- **Key Features:**
  - Visual container management (start/stop/restart)
  - Log viewing and monitoring
  - Resource usage statistics
  - Template deployment

#### Dockge (Stack Management)
- **URL:** `http://dockge.frey`
- **Purpose:** Docker Compose stack editor and manager
- **Key Features:**
  - Edit compose files in web UI
  - Real-time container logs
  - Stack deployment and updates
  - Interactive terminal access

#### Authentik (Single Sign-On)
- **URL:** `http://auth.frey`
- **Purpose:** Centralized authentication for all services
- **Key Features:**
  - OAuth2/OIDC provider for modern apps
  - LDAP provider for legacy apps (Jellyfin)
  - User and group management
  - Automatic provisioning via blueprints
  - Role-based access control

**Integrated Services:**
- ✅ **Grafana** - Automatic OAuth (works out of the box)
- ⚙️ **Home Assistant** - Manual OIDC configuration required
- ⚙️ **Immich** - Manual OAuth configuration required
- ⚙️ **Audiobookshelf** - Manual OIDC configuration required
- ⚙️ **Jellyfin** - Manual LDAP configuration required

**Configuration:**
```yaml
infrastructure:
  services:
    authentik:
      enabled: true  # Enable after infrastructure is deployed
      port: 9300
```

#### AdGuard Home (DNS & Ad Blocking)
- **URL:** `http://adguard.frey`
- **Purpose:** Local DNS server with ad blocking
- **Key Features:**
  - Resolves `.frey` domains to local services
  - Network-wide ad blocking
  - DNS query logging and statistics
  - Upstream DNS configuration

### Media Services

**Purpose:** Media library management, streaming, and organization

#### Jellyfin (Media Server)
- **URL:** `http://jellyfin.frey`
- **Purpose:** Stream movies, TV shows, and music
- **Key Features:**
  - Netflix-like interface
  - Hardware transcoding (Raspberry Pi 5)
  - Multi-user support with profiles
  - Mobile apps (iOS/Android)
  - LDAP authentication via Authentik

**Directory Structure:**
```
/opt/frey/media/
├── movies/        # Radarr manages this
├── tv/            # Sonarr manages this
├── music/         # Lidarr manages this
└── audiobooks/    # Audiobookshelf manages this
```

#### Sonarr (TV Show Manager)
- **URL:** `http://sonarr.frey`
- **Purpose:** Automatic TV show downloading and organization
- **Key Features:**
  - Episode tracking and calendar
  - Automatic quality upgrades
  - Integration with download clients (qBittorrent)
  - Prowlarr indexer integration

#### Radarr (Movie Manager)
- **URL:** `http://radarr.frey`
- **Purpose:** Automatic movie downloading and organization
- **Key Features:**
  - Movie library management
  - Automatic quality upgrades
  - Integration with download clients
  - Prowlarr indexer integration

#### Prowlarr (Indexer Manager)
- **URL:** `http://prowlarr.frey`
- **Purpose:** Centralized indexer management for *arr apps
- **Key Features:**
  - Single configuration for all indexers
  - Automatic sync to Sonarr/Radarr/Lidarr
  - Indexer health monitoring
  - FlareSolverr integration for Cloudflare-protected sites

#### Bazarr (Subtitle Manager)
- **URL:** `http://bazarr.frey`
- **Purpose:** Automatic subtitle downloading
- **Key Features:**
  - Multi-language subtitle support
  - Integration with Sonarr/Radarr
  - Automatic subtitle syncing
  - Quality scoring for subtitle selection

#### Lidarr (Music Manager)
- **URL:** `http://lidarr.frey`
- **Purpose:** Music library management
- **Key Features:**
  - Artist and album tracking
  - Automatic music downloads
  - Metadata management
  - Integration with music players

#### Audiobookshelf (Audiobook Server)
- **URL:** `http://audiobookshelf.frey`
- **Purpose:** Audiobook and podcast server
- **Key Features:**
  - Beautiful audiobook player interface
  - Progress tracking across devices
  - Podcast support with auto-downloading
  - Mobile apps with offline download
  - OIDC authentication via Authentik

**Directory Structure:**
```
/opt/frey/media/
├── audiobooks/
│   ├── Author Name/
│   │   └── Book Title/
│   │       ├── cover.jpg
│   │       └── book.m4b
└── podcasts/
    └── Podcast Name/
        └── episodes/
```

#### qBittorrent (Download Client)
- **URL:** `http://qbittorrent.frey`
- **Purpose:** Torrent download client
- **Key Features:**
  - Web-based interface
  - Integration with *arr apps
  - VPN support (optional)
  - Automatic category management

#### Jellyseerr (Request Management)
- **URL:** `http://jellyseerr.frey`
- **Purpose:** Media request system
- **Key Features:**
  - Request movies and TV shows
  - User-friendly interface
  - Integration with Sonarr/Radarr
  - Approval workflows

**Configuration:**
```yaml
media:
  services:
    jellyfin:
      enabled: true
      port: 8096
    sonarr:
      enabled: true
      port: 8989
    radarr:
      enabled: true
      port: 7878
    # ... (see group_vars/all/main.yml for all options)
```

### Automation Services

**Purpose:** Workflow automation, AI services, and home control

#### Home Assistant (Home Automation)
- **URL:** `http://homeassistant.frey`
- **Purpose:** Central hub for smart home automation
- **Key Features:**
  - Smart device control (lights, switches, sensors)
  - Automation and scenes
  - Voice control integration
  - MQTT integration
  - OIDC authentication via Authentik
  - Wyoming protocol voice services

**Voice Services:**
- **Piper TTS** - Text-to-Speech (port 10200, Wyoming protocol)
- **Wyoming Whisper** - Speech-to-Text (port 10300, optional)

**Configuration:**
```yaml
homeassistant:
  services:
    homeassistant:
      enabled: true
      port: 8123
    piper:
      enabled: true
      port: 10200
      default_voice: "en_US-lessac-medium"
    wyoming_whisper:
      enabled: false  # Resource-intensive
      port: 10300
```

#### n8n (Workflow Automation)
- **URL:** `http://n8n.frey`
- **Purpose:** Visual workflow automation (Zapier alternative)
- **Key Features:**
  - 300+ service integrations
  - Visual workflow editor
  - Scheduling and webhooks
  - Data transformation
  - Self-hosted (no cloud dependency)

**Use Cases:**
- Automate media library cleanup
- Notification workflows
- Data synchronization
- API integrations
- Home Assistant automation triggers

#### Ollama (Local AI)
- **URL:** `http://ai.frey:11434`
- **Purpose:** Local Large Language Model inference
- **Key Features:**
  - Run LLMs locally (Llama, Mistral, etc.)
  - No cloud dependency
  - REST API for integrations
  - Model management

**Configuration:**
```yaml
automation:
  ollama:
    port: 11434
```

#### Open WebUI (AI Chat Interface)
- **URL:** `http://ai.frey`
- **Purpose:** ChatGPT-like interface for Ollama
- **Key Features:**
  - Beautiful chat interface
  - Conversation history
  - Model switching
  - Image generation support
  - Ollama backend integration

**Configuration:**
```yaml
automation:
  services:
    homeassistant:
      enabled: true
    piper:
      enabled: true  # TTS for Home Assistant
    wyoming_whisper:
      enabled: false  # STT (optional, resource-heavy)
  n8n:
    port: 5678
  ollama:
    port: 11434
  openwebui:
    port: 3002
```

### Monitoring Services

**Purpose:** System health, metrics, logging, and alerting

#### Grafana (Visualization & Dashboards)
- **URL:** `http://grafana.frey`
- **Purpose:** Metrics visualization and monitoring dashboards
- **Key Features:**
  - Beautiful dashboards
  - Multiple data sources (Prometheus, Loki)
  - Alerting and notifications
  - OAuth SSO with Authentik (automatic)
  - Role-based access (Admin/Editor/Viewer via Authentik groups)

**Pre-configured Dashboards:**
- System metrics (CPU, RAM, disk, network)
- Docker container stats
- Service availability
- Network speed tests
- Custom dashboards (add your own)

#### Prometheus (Metrics Collection)
- **URL:** `http://prometheus.frey`
- **Purpose:** Time-series metrics database
- **Key Features:**
  - Collects metrics from exporters
  - PromQL query language
  - Alerting rules
  - Service discovery

**Metrics Sources:**
- **Node Exporter** - System metrics (CPU, RAM, disk, network)
- **cAdvisor** - Container metrics (per-container stats)
- **Speedtest Tracker** - Internet speed metrics

#### Loki (Log Aggregation)
- **URL:** `http://loki.frey:3100`
- **Purpose:** Centralized log storage and querying
- **Key Features:**
  - LogQL query language (Prometheus-like)
  - Integration with Grafana
  - Low resource usage
  - Efficient log compression

#### Promtail (Log Collector)
- **Purpose:** Collects logs and sends to Loki
- **Sources:**
  - Docker container logs
  - System logs (/var/log)
  - Service-specific logs

#### Uptime Kuma (Uptime Monitoring)
- **URL:** `http://uptime-kuma.frey`
- **Purpose:** Service availability monitoring
- **Key Features:**
  - Beautiful status page
  - HTTP/HTTPS monitoring
  - TCP/UDP port monitoring
  - Keyword monitoring
  - Notifications (ntfy, Discord, Telegram, etc.)

#### Speedtest Tracker (Internet Speed)
- **URL:** `http://speedtest.frey`
- **Purpose:** Automatic internet speed testing
- **Key Features:**
  - Scheduled speed tests
  - Historical speed data
  - Grafana dashboard integration
  - ISP performance tracking

#### Watchtower (Auto-Updates)
- **Purpose:** Automatic Docker container updates
- **Key Features:**
  - Monitors container images for updates
  - Pulls and restarts containers automatically
  - Configurable schedules
  - Notification support

**Configuration:**
```yaml
monitoring:
  grafana:
    enabled: true
    port: 3000
  prometheus:
    enabled: true
    port: 9090
  loki:
    enabled: true
    port: 3100
  promtail:
    enabled: true
  uptime-kuma:
    enabled: true
    port: 3001
  speedtest-tracker:
    enabled: true
    port: 8181
  watchtower:
    enabled: true
```

### Photo Management

#### Immich (Photo & Video Library)
- **URL:** `http://immich.frey`
- **Purpose:** Self-hosted Google Photos alternative
- **Key Features:**
  - Automatic photo backup from mobile
  - Face recognition
  - Object detection
  - Map-based photo browsing
  - Timeline view
  - Album creation and sharing
  - Hardware acceleration (Raspberry Pi 5)
  - OAuth authentication via Authentik

**Mobile Apps:**
- iOS: Available on App Store
- Android: Available on Google Play

**Storage:**
```
/opt/frey/photos/
└── library/           # Uploaded photos and videos
```

**Configuration:**
```yaml
immich:
  services:
    immich:
      enabled: true
      port: 2283
      hw_accel: "rkmpp"  # RK3588 hardware acceleration
```

### Recipe Management

#### Mealie (Cookbook)
- **URL:** `http://cookbook.frey`
- **Purpose:** Recipe manager and meal planner
- **Key Features:**
  - Recipe scraping from URLs
  - Meal planning calendar
  - Shopping list generation
  - Recipe categorization and tagging
  - Multi-user support
  - Mobile-responsive interface

**Configuration:**
```yaml
cookbook:
  services:
    mealie:
      enabled: true
      port: 9925
      allow_signup: false  # Admin creates users
```

### WiFi Access Point

**Purpose:** Provide WiFi network for client devices with automatic roaming

#### FreyHub Access Point
- **SSID:** `FreyHub` (configurable)
- **IP:** `10.20.0.1`
- **DHCP Range:** `10.20.0.50 - 10.20.0.150`
- **Purpose:** Always-on WiFi for accessing services and SSH

**Features:**
- DNS server for `.frey` domains
- DHCP server for automatic IP assignment
- NAT/routing to internet via eth0/wlan0
- DoH blocking (forces local DNS usage)

#### WiFi Automatic Roaming System
- **Purpose:** Automatically connect to best available public WiFi
- **Status:** See [WIFI_ROAMING_SETUP.md](WIFI_ROAMING_SETUP.md)

**Key Features:**
- Internet verification (filters non-internet networks)
- Automatic captive portal bypass (80-90% success rate)
- Intelligent network scoring and selection
- Adaptive scanning (30s aggressive → 10min stable)
- MQTT integration for Home Assistant control
- Network history and blacklisting
- Always keeps FreyHub AP running

**Configuration:**
```yaml
network:
  wifi:
    ssid: "FreyHub"
    password: "{{ wifi_ap.password }}"  # In secrets.yml
    interface: "wlan1"         # AP interface
    client_interface: "eth0"   # Internet interface
    ip: "10.20.0.1"

    roaming:
      enabled: true  # Enable automatic WiFi roaming
      client_interface: "wlan0"  # For connecting to public WiFi
      mqtt_topic: "frey/wifi/roaming"

# Optional: Pre-configure known networks
known_wifi_networks:
  - ssid: "Home WiFi"
    password: "myPassword123"
    priority: 100
  - ssid: "Office WiFi"
    password: "workPassword"
    priority: 90
```

---

## Special Features

### Single Sign-On (SSO) with Authentik

**What is SSO?**

Single Sign-On allows you to authenticate once with Authentik and access all integrated services without entering passwords again.

**How It Works:**

1. Visit any integrated service (e.g., `http://grafana.frey`)
2. Click "Sign in with Authentik"
3. Authenticate with Authentik credentials
4. Automatically logged into the service
5. Access other services without re-authenticating

**Integrated Services:**

| Service | Integration Type | Configuration |
|---------|-----------------|---------------|
| **Grafana** | OAuth2/OIDC | ✅ Automatic - works out of the box |
| **Home Assistant** | OIDC | ⚙️ Manual - configure in HA UI |
| **Immich** | OAuth2 | ⚙️ Manual - configure in Immich UI |
| **Audiobookshelf** | OIDC | ⚙️ Manual - configure in ABS UI |
| **Jellyfin** | LDAP | ⚙️ Manual - install LDAP plugin |

**Setup Instructions:**

See [POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md) for detailed configuration steps.

**Authentik Groups:**

Access control is managed via Authentik groups:

- `grafana_admins` - Full Grafana admin access
- `grafana_editors` - Can edit dashboards
- `grafana_viewers` - Read-only access
- `jellyfin_users` - Can access Jellyfin
- `jellyfin_admins` - Jellyfin administration

**Creating Users:**

```
1. Login to http://auth.frey with admin account
2. Admin → Directory → Users → Create
3. Add user to appropriate groups
4. User can now login to integrated services
```

### WiFi Automatic Roaming

**Overview:**

The WiFi Automatic Roaming System intelligently manages WiFi connections, automatically connecting to the best available network with working internet access.

**Perfect For:**
- Daily commuters (train/bus WiFi → office WiFi → home WiFi)
- Travelers (airport → hotel → cafe WiFi)
- Remote workers (home → coworking → coffee shop)

**Key Features:**

#### 1. Internet Verification
Ensures connected networks actually provide internet (not just WiFi):
- Ping test (basic connectivity)
- DNS resolution test
- HTTP test (captive portal detection)
- HTTPS test (full internet confirmation)

**Filters out:**
- Smart home devices (TV WiFi, printer WiFi)
- IoT networks without internet
- Networks with DNS but no routing

#### 2. Automatic Captive Portal Bypass
Automatically authenticates with common captive portals:

**5 Authentication Methods:**
1. Simple visit (many portals auto-authenticate)
2. Form auto-submit (find and submit forms)
3. API endpoints (try common auth APIs)
4. Button detection (click "Accept"/"Agree" buttons)
5. Generic form submission (fallback)

**Success Rate:** 80-90% on common portals (Starbucks, hotels, airports)

If automatic bypass fails, network is temporarily blacklisted.

#### 3. Intelligent Network Scoring
Ranks networks 0-100 based on multiple factors:

| Factor | Points | Description |
|--------|--------|-------------|
| **Signal Strength** | 0-40 | Stronger signal = higher score |
| **Known Network** | 0-30 | Saved networks get priority |
| **History** | 0-20 | Networks with good track record |
| **Security** | 0 to -10 | Open networks get penalty |
| **Failures** | -10 each | Recent failures reduce score |

**Examples:**
- Home WiFi (excellent signal, known, WPA2): 95
- Starbucks (good signal, known, open): 65
- Unknown cafe (weak signal, open): 25

#### 4. Adaptive Scanning
Adjusts scan frequency based on connection state:

| State | Condition | Scan Interval |
|-------|-----------|---------------|
| **No Connection** | Not connected | Every 30 seconds |
| **No Internet** | Connected but no internet | Every 60 seconds |
| **Weak Signal** | Signal < -75 dBm | Every 2 minutes |
| **Good Connection** | Connected, good signal, internet OK | Every 10 minutes |

**MQTT Control:**

Change scan behavior via Home Assistant or n8n:

```bash
# Publish to MQTT to control roaming
mosquitto_pub -h localhost -t "frey/wifi/roaming/control/mode" -m "aggressive"
mosquitto_pub -h localhost -t "frey/wifi/roaming/control/scan_interval" -m "60"
mosquitto_pub -h localhost -t "frey/wifi/roaming/control/rescan" -m "true"
```

#### 5. Network History & Learning
Tracks connection success rates:

```json
{
  "Home WiFi": {
    "successes": 127,
    "failures": 2,
    "success_rate": 98.4,
    "last_success": 1698765432
  },
  "Starbucks WiFi": {
    "successes": 45,
    "failures": 12,
    "success_rate": 78.9,
    "last_success": 1698761234
  }
}
```

Networks with low success rates get deprioritized.

**Configuration:**

See [WIFI_ROAMING_SETUP.md](WIFI_ROAMING_SETUP.md) for complete setup and usage guide.

**Home Assistant Integration:**

Monitor and control via Home Assistant:

```yaml
# Sensors
sensor.frey_wifi_network      # Current SSID
sensor.frey_wifi_signal        # Signal strength (dBm)
sensor.frey_wifi_state         # Connection state
binary_sensor.frey_has_internet  # Internet status

# Controls
button.frey_force_wifi_rescan  # Trigger immediate scan
input_select.frey_wifi_scan_mode  # aggressive/moderate/conservative
```

### Voice Services (Home Assistant)

**Overview:**

Frey includes voice services for Home Assistant via the Wyoming protocol:

#### Piper (Text-to-Speech)
- **Port:** 10200 (Wyoming protocol)
- **Purpose:** Convert text to natural-sounding speech
- **Default Voice:** en_US-lessac-medium
- **Available Voices:**
  - `en_US-lessac-medium` - US English, medium quality
  - `en_AU-southern-female` - Australian English

**Home Assistant Integration:**
```yaml
# configuration.yaml
tts:
  - platform: wyoming
    uri: "tcp://piper:10200"
```

#### Wyoming Whisper (Speech-to-Text)
- **Port:** 10300 (Wyoming protocol)
- **Purpose:** Convert speech to text
- **Models:** tiny-int8, base-int8, small-int8
- **Note:** Resource-intensive, disabled by default

**Enable in `group_vars/all/main.yml`:**
```yaml
homeassistant:
  services:
    wyoming_whisper:
      enabled: true
      model: "tiny-int8"  # Start with smallest model
```

**Use Cases:**
- Voice announcements
- Smart home notifications
- Voice commands (with Whisper)
- Custom automations

### Audiobook & Music Playback

#### Audiobook Bridge (Audiobookshelf Integration)

**Purpose:** Sync audiobook playback progress with Home Assistant

**Features:**
- Real-time progress tracking
- Playback control from Home Assistant
- Integration with n8n workflows
- Local network only (no external API calls)

**Configuration:**
```yaml
media:
  services:
    audiobook_bridge:
      enabled: true
      sync_interval: 5  # Progress sync every 5 seconds
```

**Home Assistant Sensors:**
```yaml
sensor.audiobook_current_title
sensor.audiobook_progress_percent
sensor.audiobook_current_chapter
binary_sensor.audiobook_is_playing
```

**Setup:**
1. Enable audiobook_bridge in `group_vars/all/main.yml`
2. Generate API token in Audiobookshelf UI
3. Add token to `group_vars/all/secrets.yml`: `audiobookshelf_api_token`
4. Redeploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media`

#### Mopidy (Music Player)

**Status:** Disabled (no ARM64-compatible image)

**Alternative:** Use Jellyfin directly for music playback

```yaml
media:
  services:
    mopidy:
      enabled: false  # No ARM64 support
```

**TODO:** Build custom ARM64 Mopidy image or use alternative

---

## Configuration Guide

### Understanding group_vars/all/main.yml

This is the primary configuration file that controls all aspects of Frey.

#### Feature Toggles

Enable/disable entire service stacks:

```yaml
features:
  infrastructure: true      # Traefik, Portainer, Authentik
  networking: true          # AdGuard DNS, WiFi AP
  wifi_access_point: true   # FreyHub AP
  media: true               # Jellyfin, *arr suite
  monitoring: true          # Grafana, Prometheus
  automation: true          # n8n, Ollama, Home Assistant
  homeassistant: true       # Home Assistant + voice
  immich: true              # Photo management
  cookbook: true            # Mealie recipe manager
  authentication: false     # Enable Authentik (after infrastructure)
  backup: false             # Automated backups (future)
```

**Deployment:**

Only enabled features are deployed. To change:

1. Edit `group_vars/all/main.yml`
2. Set feature to `true` or `false`
3. Run: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml`

#### Network Configuration

```yaml
network:
  domain_name: frey          # Base domain for services
  timezone: Australia/Hobart # System timezone

  # WiFi Access Point
  wifi:
    ssid: "FreyHub"          # WiFi network name
    password: "{{ wifi_ap.password }}"  # From secrets.yml
    interface: "wlan1"       # AP interface
    client_interface: "eth0" # Internet interface
    ip: "10.20.0.1"          # AP IP address
    dhcp_range_start: "10.20.0.50"
    dhcp_range_end: "10.20.0.150"

    # WiFi Roaming (optional)
    roaming:
      enabled: false         # Set to true to enable
      client_interface: "wlan0"
      mqtt_topic: "frey/wifi/roaming"
```

#### Storage Paths

```yaml
storage:
  base_dir: /opt/frey                       # Main directory
  appdata_dir: "{{ storage.base_dir }}/appdata"  # Service configs
  stacks: "{{ storage.base_dir }}/stacks"        # Compose files

# Media paths (derived from base_dir)
# /opt/frey/media/movies
# /opt/frey/media/tv
# /opt/frey/media/music
# /opt/frey/downloads
```

#### Service-Specific Configuration

Each service stack has its own section:

```yaml
# Example: Media stack configuration
media:
  # User/Group (for file permissions)
  user:
    name: media_manager
    uid: 63342
  group:
    name: media
    gid: 63342

  # Storage
  dir: "{{ storage.base_dir }}/media"
  downloads: "{{ storage.base_dir }}/downloads"

  # Individual services
  services:
    jellyfin:
      enabled: true
      version: "latest"
      port: 8096

    sonarr:
      enabled: true
      version: "latest"
      port: 8989

    # ... more services
```

**Pattern for all stacks:**
- User/group configuration
- Directory paths
- Individual service toggles
- Version pinning
- Port assignments

#### Security Settings

```yaml
security:
  fail2ban:
    enable: true             # Brute-force protection
  ufw:
    enable: true             # Firewall
  ssh_port: 22               # SSH port

  # Firewall automatically opens ports for enabled services
  firewall_tcp_ports: "{{ ... }}"  # Auto-calculated from features
```

### Managing Secrets (Ansible Vault)

**Secrets File:** `group_vars/all/secrets.yml`

**Edit Secrets:**
```bash
ansible-vault edit group_vars/all/secrets.yml
```

**Required Secrets:**

```yaml
# Ansible
vault_ansible_become_pass: "YourSudoPassword"

# WiFi
wifi_ap.password: "YourWiFiPassword"

# Authentik (SSO)
authentik_secret_key: "GENERATE_RANDOM_50_CHARS"
authentik_postgres_password: "GENERATE_RANDOM_32_CHARS"

# OAuth Client Secrets
grafana_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
homeassistant_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
immich_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
audiobookshelf_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
authentik_ldap_bind_password: "GENERATE_RANDOM_32_CHARS"

# API Tokens (generate after deployment)
jellyfin_api_token: "CHANGE_AFTER_DEPLOYMENT"
audiobookshelf_api_token: "CHANGE_AFTER_DEPLOYMENT"

# Database passwords
mealie_db_password: "GENERATE_RANDOM_32_CHARS"
```

**Generate Random Passwords:**
```bash
# 32-character password
openssl rand -base64 32

# 50-character password
openssl rand -base64 50 | head -c 50
```

### DNS Rewrites Configuration

Control which services get `.frey` DNS entries:

```yaml
network:
  dns_rewrites:
    - name: traefik         # http://traefik.frey
    - name: portainer       # http://portainer.frey
    - name: jellyfin        # http://jellyfin.frey
    - name: grafana         # http://grafana.frey
    # Add more as needed
```

Each entry creates:
- DNS A record: `<name>.frey` → Raspberry Pi IP
- Traefik routing: `<name>.frey` → Docker container

---

## Common Tasks

### Starting and Stopping Services

**Via Docker:**
```bash
# SSH into Pi
ssh pi@frey

# View all containers
docker ps -a

# Start/stop/restart a service
docker start jellyfin
docker stop jellyfin
docker restart jellyfin

# View logs
docker logs -f jellyfin
docker logs --tail 100 sonarr
```

**Via Portainer:**
1. Open `http://portainer.frey`
2. Click Containers
3. Use Start/Stop/Restart buttons

**Via Docker Compose:**
```bash
# Navigate to stack directory
cd /opt/frey/stacks/media

# Restart entire stack
docker compose restart

# Restart specific service
docker compose restart jellyfin

# Stop entire stack
docker compose down

# Start entire stack
docker compose up -d
```

### Viewing Logs

**Container Logs:**
```bash
# Follow logs (real-time)
docker logs -f jellyfin

# Last 100 lines
docker logs --tail 100 sonarr

# Logs since 1 hour ago
docker logs --since 1h radarr

# All logs
docker logs jellyfin
```

**System Logs:**
```bash
# WiFi AP hostapd
sudo journalctl -u hostapd -f

# WiFi AP dnsmasq
sudo journalctl -u dnsmasq -f

# WiFi roaming daemon
sudo journalctl -u frey-wifi-roaming -f

# System logs
sudo journalctl -f
```

**Grafana Loki (Centralized):**
1. Open `http://grafana.frey`
2. Explore → Loki
3. Query: `{container="jellyfin"}`

### Updating Services

**Automatic (Watchtower):**

Watchtower automatically checks for and applies updates:
- Checks every 24 hours (configurable)
- Pulls new images
- Restarts containers with updated images
- No manual intervention needed

**Manual Update:**
```bash
# SSH into Pi
ssh pi@frey

# Pull new image
docker pull lscr.io/linuxserver/jellyfin:latest

# Recreate container
cd /opt/frey/stacks/media
docker compose up -d jellyfin
```

**Update All:**
```bash
# Update all containers in a stack
cd /opt/frey/stacks/media
docker compose pull
docker compose up -d
```

### Backing Up Configuration

**Manual Backup:**
```bash
# From your workstation
ssh pi@frey

# Backup appdata (service configs)
sudo tar -czf /tmp/frey-appdata-backup-$(date +%Y%m%d).tar.gz \
  /opt/frey/appdata

# Download backup
scp pi@frey:/tmp/frey-appdata-backup-*.tar.gz ~/backups/

# Backup Ansible configuration
tar -czf ~/backups/frey-ansible-$(date +%Y%m%d).tar.gz \
  ~/Projects/frey/
```

**Important Files to Backup:**
- `/opt/frey/appdata/` - All service configurations
- `group_vars/all/main.yml` - Main configuration
- `group_vars/all/secrets.yml` - Encrypted secrets
- `.vault_pass` - Vault password file

**Future:** Automated backup system (feature in development)

### Adding New Users (Authentik)

```bash
# Option 1: Web UI
1. Open http://auth.frey
2. Login as admin
3. Admin → Directory → Users → Create
4. Fill in user details
5. Add to appropriate groups
6. User can now login to integrated services

# Option 2: Bulk import (future feature)
# CSV import coming in future version
```

### Monitoring System Health

**Grafana Dashboards:**
1. Open `http://grafana.frey`
2. Login (or use SSO)
3. Dashboards → Browse

**Key Dashboards:**
- System Overview - CPU, RAM, disk, network
- Docker Containers - Per-container stats
- Service Status - Uptime tracking
- Network Speed - Internet performance

**Uptime Kuma:**
1. Open `http://uptime-kuma.frey`
2. View real-time service status
3. Setup notifications (ntfy, Discord, email)

**Prometheus Metrics:**
1. Open `http://prometheus.frey`
2. Graph → Query metrics
3. Example: `container_memory_usage_bytes{name="jellyfin"}`

### Troubleshooting Network Access

**Can't access services via `.frey` domain:**

```bash
# 1. Check DNS (from WiFi client)
nslookup jellyfin.frey 10.20.0.1

# Expected: Should return Pi's IP
# If no result: DNS not working

# 2. Check if connected to FreyHub WiFi
# Make sure you're on the right network

# 3. Check AdGuard Home
# Open http://10.20.0.1:3030
# Login → Query Log → Check DNS queries

# 4. Try IP address directly
# http://192.168.x.x:8096  (Jellyfin)
# If works via IP: DNS issue
# If fails: Service or Traefik issue

# 5. Check Traefik
# Open http://<pi-ip>:8082
# Check Routes tab - should show all services
```

**Service not responding:**

```bash
# 1. Check if container is running
docker ps | grep jellyfin

# If not running:
docker start jellyfin

# 2. Check container logs
docker logs jellyfin

# 3. Check Traefik routing
curl -H "Host: jellyfin.frey" http://localhost

# 4. Restart Traefik
docker restart traefik
```

---

## Advanced Topics

### Adding Custom Services

**Example: Adding a new service to media stack**

1. **Update configuration** (`group_vars/all/main.yml`):
```yaml
media:
  services:
    myservice:
      enabled: true
      version: "latest"
      port: 8888
```

2. **Update Compose template** (`roles/media/templates/docker-compose-media.yml.j2`):
```yaml
{% if media.services.myservice.enabled %}
  myservice:
    image: "myorg/myservice:{{ media.services.myservice.version }}"
    container_name: myservice
    restart: unless-stopped
    ports:
      - "{{ media.services.myservice.port }}:8888"
    volumes:
      - "{{ storage.appdata_dir }}/myservice:/config"
    networks:
      - proxy
      - media_network
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.myservice.rule=Host(`myservice.{{ network.domain_name }}`)"
      - "traefik.http.services.myservice.loadbalancer.server.port=8888"
{% endif %}
```

3. **Add DNS rewrite** (`group_vars/all/main.yml`):
```yaml
network:
  dns_rewrites:
    - name: myservice
```

4. **Add firewall port**:
```yaml
security:
  firewall_tcp_ports: "{{ ... + [media.services.myservice.port] }}"
```

5. **Deploy:**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

### Custom Traefik Configuration

**Location:** `/opt/frey/appdata/traefik/traefik.yml`

**Enable HTTPS (Self-signed):**
```yaml
# Add to traefik.yml
entryPoints:
  websecure:
    address: ":443"
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https

# Generate self-signed cert
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout /opt/frey/appdata/traefik/cert.key \
  -out /opt/frey/appdata/traefik/cert.crt \
  -days 365 -subj "/CN=*.frey"
```

### Performance Tuning

**Optimize for SSD:**
```yaml
system:
  ssd_optimization:
    enabled: true
    trim: true
```

**Reduce Monitoring Overhead:**
```yaml
monitoring:
  cadvisor:
    enabled: false  # Disable per-container stats if not needed
  speedtest-tracker:
    enabled: false  # Disable if bandwidth is concern
```

**Adjust Watchtower Frequency:**
```yaml
automation:
  watchtower_interval: 86400  # 24 hours (default)
  # watchtower_interval: 604800  # 7 days (less frequent)
```

### Custom WiFi Roaming Behavior

**Edit on Pi:** `/etc/frey/wifi-roaming.conf`

```bash
# Aggressive switching (for travel)
SCAN_INTERVAL_DEFAULT=60
SCAN_INTERVAL_NO_CONNECTION=20
SCAN_INTERVAL_GOOD=120
SWITCH_THRESHOLD=10  # Switch more readily

# Conservative (for stationary use)
SCAN_INTERVAL_DEFAULT=300
SCAN_INTERVAL_GOOD=900
SWITCH_THRESHOLD=25  # Only switch for much better networks

# Restart to apply
sudo systemctl restart frey-wifi-roaming
```

### Backup and Restore

**Backup Strategy:**

1. **Configuration Backup** (version controlled):
   - `git commit` your Frey project directory
   - `git push` to remote repository

2. **Service Data Backup:**
```bash
# Create backup script
cat > /opt/frey/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/frey/backups"
DATE=$(date +%Y%m%d-%H%M%S)

# Stop services (optional, ensures consistency)
cd /opt/frey/stacks/media && docker compose stop

# Backup appdata
tar -czf "$BACKUP_DIR/appdata-$DATE.tar.gz" /opt/frey/appdata

# Backup media metadata (not media files)
tar -czf "$BACKUP_DIR/metadata-$DATE.tar.gz" \
  /opt/frey/appdata/jellyfin \
  /opt/frey/appdata/sonarr \
  /opt/frey/appdata/radarr

# Start services
cd /opt/frey/stacks/media && docker compose start

# Cleanup old backups (keep 7 days)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
EOF

chmod +x /opt/frey/backup.sh
```

3. **Schedule Backups:**
```bash
# Add to crontab
crontab -e

# Daily at 3 AM
0 3 * * * /opt/frey/backup.sh
```

**Restore:**
```bash
# Stop services
cd /opt/frey/stacks/media && docker compose down

# Restore appdata
tar -xzf appdata-20240101-030000.tar.gz -C /

# Start services
cd /opt/frey/stacks/media && docker compose up -d
```

### Development Mode

**Test changes without affecting production:**

```bash
# Create test inventory
cp inventory/hosts.yml inventory/hosts-test.yml

# Edit test inventory (different Pi or VM)
# ansible_host: 192.168.1.200  # Test machine

# Deploy to test
ansible-playbook -i inventory/hosts-test.yml playbooks/site.yml

# Once verified, deploy to production
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

---

## Troubleshooting

### Service Won't Start

**Check container status:**
```bash
docker ps -a | grep jellyfin
```

**Check logs:**
```bash
docker logs jellyfin
```

**Common causes:**
- Port already in use
- Missing environment variables
- Volume mount errors
- Network conflicts

**Solutions:**
```bash
# Check port availability
sudo netstat -tlnp | grep 8096

# Verify volume permissions
ls -la /opt/frey/appdata/jellyfin

# Recreate container
cd /opt/frey/stacks/media
docker compose up -d --force-recreate jellyfin
```

### WiFi AP Not Working

**Check hostapd:**
```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
```

**Check dnsmasq:**
```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

**Common issues:**
- WiFi interface not available
- Conflicting services (NetworkManager)
- Country code mismatch
- Interface already in use

**Solutions:**
```bash
# Check interface exists
ip link show wlan1

# Bring up interface
sudo ip link set wlan1 up

# Unblock WiFi
sudo rfkill unblock wifi

# Restart services
sudo systemctl restart hostapd dnsmasq
```

### Authentik SSO Not Working

**Check Authentik is running:**
```bash
docker ps | grep authentik
```

**Check Authentik logs:**
```bash
docker logs authentik_server
docker logs authentik_worker
```

**Common issues:**
- Client secret mismatch
- Incorrect redirect URIs
- Authentik not fully initialized
- Application not created (blueprints failed)

**Solutions:**
```bash
# Verify secrets match
# Compare group_vars/all/secrets.yml with service configuration

# Check Authentik applications
# http://auth.frey → Admin → Applications
# Should see: grafana, homeassistant, immich, audiobookshelf

# Redeploy blueprints
# Admin → Blueprints → Apply
```

### Can't Access Services

**Diagnosis steps:**

1. **Check FreyHub WiFi connection:**
   - Connected to FreyHub network?
   - IP address in 10.20.0.x range?

2. **Check DNS resolution:**
```bash
nslookup jellyfin.frey 10.20.0.1
```

3. **Check service is running:**
```bash
ssh pi@frey
docker ps | grep jellyfin
```

4. **Check Traefik routing:**
```bash
# From Pi
curl -H "Host: jellyfin.frey" http://localhost

# Check Traefik dashboard
# http://<pi-ip>:8082
```

5. **Try direct IP:**
```bash
# http://192.168.x.x:8096
# If this works: DNS/Traefik issue
# If this fails: Service issue
```

### High Resource Usage

**Check resource usage:**
```bash
# Overall system
htop

# Per-container
docker stats

# Disk usage
df -h
du -sh /opt/frey/*
```

**Common culprits:**
- Transcoding (Jellyfin) - Use hardware acceleration
- Wyoming Whisper - Very CPU intensive, disable if not needed
- Logs - Old logs filling disk

**Solutions:**
```bash
# Clean Docker resources
docker system prune -a

# Clean logs
sudo journalctl --vacuum-time=7d

# Disable resource-heavy services
# Edit group_vars/all/main.yml
homeassistant:
  services:
    wyoming_whisper:
      enabled: false  # Disable STT

monitoring:
  cadvisor:
    enabled: false  # Disable if not using
```

### Deployment Failures

**Check Ansible output:**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vvv
```

**Common causes:**
- SSH connection issues
- Vault password incorrect
- Missing required variables
- Docker not installed

**Solutions:**
```bash
# Test SSH connection
ssh pi@frey

# Verify vault password
ansible-vault edit group_vars/all/secrets.yml

# Check Docker
ssh pi@frey "docker ps"

# Retry deployment with specific tags
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

---

## Support and Resources

### Documentation

- **[QUICK_SETUP.md](QUICK_SETUP.md)** - Fast deployment guide
- **[WIFI_ROAMING_SETUP.md](WIFI_ROAMING_SETUP.md)** - WiFi roaming system
- **[POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md)** - Manual configuration steps
- **[SETUP_CHECKLIST.md](SETUP_CHECKLIST.md)** - Deployment checklist
- **[CLAUDE.md](../CLAUDE.md)** - Developer guide (for Claude Code)

### Getting Help

1. **Check logs first:**
   - Service logs: `docker logs <service>`
   - System logs: `sudo journalctl -u <service> -n 50`

2. **Review documentation:**
   - Most common issues covered in this guide
   - Check service-specific docs

3. **GitHub Issues:**
   - Search existing issues
   - Create new issue with logs and configuration

### Contributing

Contributions welcome! To add features or fix bugs:

1. Fork the repository
2. Create feature branch
3. Test changes thoroughly
4. Submit pull request with description

---

## Appendix

### Default Ports Reference

| Service | Port | URL |
|---------|------|-----|
| **Infrastructure** |
| Traefik Dashboard | 8082 | http://traefik.frey:8082 |
| Portainer | 9000 | http://portainer.frey |
| Dockge | 5001 | http://dockge.frey |
| Authentik | 9300 | http://auth.frey |
| AdGuard Home | 3030 | http://adguard.frey |
| **Media** |
| Jellyfin | 8096 | http://jellyfin.frey |
| Sonarr | 8989 | http://sonarr.frey |
| Radarr | 7878 | http://radarr.frey |
| Prowlarr | 9696 | http://prowlarr.frey |
| Bazarr | 6767 | http://bazarr.frey |
| Lidarr | 8686 | http://lidarr.frey |
| Audiobookshelf | 13378 | http://audiobookshelf.frey |
| qBittorrent | 8080 | http://qbittorrent.frey |
| Jellyseerr | 5055 | http://jellyseerr.frey |
| **Automation** |
| Home Assistant | 8123 | http://homeassistant.frey |
| n8n | 5678 | http://n8n.frey |
| Ollama | 11434 | http://ai.frey:11434 |
| Open WebUI | 3002 | http://ai.frey |
| **Monitoring** |
| Grafana | 3000 | http://grafana.frey |
| Prometheus | 9090 | http://prometheus.frey |
| Uptime Kuma | 3001 | http://uptime-kuma.frey |
| Speedtest | 8181 | http://speedtest.frey |
| **Photos** |
| Immich | 2283 | http://immich.frey |
| **Cookbook** |
| Mealie | 9925 | http://cookbook.frey |

### Network Diagram

```
Internet
  │
  ├─ eth0/wlan0 (Client) ─┐
  │                        │
  └─ [Raspberry Pi 5]     │
       │                   │
       ├─ NAT/Routing ─────┘
       │
       ├─ wlan1 (AP) ─── FreyHub WiFi (10.20.0.1)
       │                     │
       │                     └─ DHCP: 10.20.0.50-150
       │
       ├─ Docker Networks:
       │    ├─ proxy (Traefik routing)
       │    ├─ localdns (AdGuard DNS)
       │    ├─ media_network
       │    ├─ automation_network
       │    └─ monitoring_network
       │
       └─ Storage: /opt/frey/
            ├─ appdata/
            ├─ media/
            └─ stacks/
```

### File Permissions

| Directory | Owner | Group | Permissions |
|-----------|-------|-------|-------------|
| /opt/frey | root | root | 755 |
| /opt/frey/appdata/<service> | <stack>_manager | <stack> | 755 |
| /opt/frey/media/* | media_manager | media | 775 |
| /opt/frey/stacks/* | root | root | 755 |

### Environment Variables Reference

**Authentik:**
- `AUTHENTIK_SECRET_KEY` - Main secret key
- `AUTHENTIK_POSTGRES_PASSWORD` - Database password
- `AUTHENTIK_BOOTSTRAP_PASSWORD` - Initial admin password

**Grafana:**
- `GF_AUTH_GENERIC_OAUTH_ENABLED` - Enable OAuth
- `GF_AUTH_GENERIC_OAUTH_CLIENT_ID` - OAuth client ID
- `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` - OAuth secret

**Immich:**
- `DB_PASSWORD` - Database password
- `OAUTH_ENABLED` - Enable OAuth
- `OAUTH_ISSUER` - OAuth issuer URL
- `OAUTH_CLIENT_ID` - OAuth client ID
- `OAUTH_CLIENT_SECRET` - OAuth secret

---

**Version:** 1.0
**Last Updated:** 2024-10-31
**For:** Frey Raspberry Pi 5 Home Server System
