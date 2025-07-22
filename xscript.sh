#!/bin/bash

# Pi5 Hub Ansible Projekt Setup Script
# Erstellt die komplette Verzeichnisstruktur und Basis-Dateien

PROJECT_NAME="pi5-hub-ansible"
PROJECT_DIR="$(pwd)/$PROJECT_NAME"

echo "🚀 Erstelle Raspberry Pi 5 Hub Ansible Projekt..."
echo "Zielverzeichnis: $PROJECT_DIR"

# Hauptverzeichnis erstellen
if [ -d "$PROJECT_DIR" ]; then
    echo "⚠️  Verzeichnis $PROJECT_DIR existiert bereits!"
    read -p "Möchten Sie fortfahren und existierende Dateien überschreiben? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Abbruch durch Benutzer"
        exit 1
    fi
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "📁 Erstelle Verzeichnisstruktur..."

# Hauptverzeichnisse erstellen
mkdir -p inventory
mkdir -p group_vars
mkdir -p playbooks
mkdir -p scripts
mkdir -p templates

# Roles-Verzeichnisse erstellen
mkdir -p roles/{common,security,ssd_optimization,docker,directories,dockge,monitoring,media_stack,ai_stack,photo_management,homeassistant,infrastructure,networking,file_management,backup,power_management}

# Standard Ansible Role-Strukturen erstellen
for role in roles/*/; do
    mkdir -p "$role"/{tasks,handlers,templates,files,vars,defaults,meta}
done

echo "📝 Erstelle Basis-Dateien..."

# README.md erstellen
cat > README.md << 'EOF'
# Raspberry Pi 5 Hub Ansible Projekt

Ein umfassendes Ansible-Projekt zur automatisierten Einrichtung eines Raspberry Pi 5 als zentraler Hub für verschiedene Services.

## Features

- 🔧 **System-Setup**: Basis-Konfiguration und Optimierungen
- 🔒 **Sicherheit**: UFW Firewall, Fail2Ban
- 💾 **SSD-Optimierung**: Spezielle Optimierungen für SSD-Storage
- 🐳 **Docker Stack**: Containerisierte Services
- 📊 **Monitoring**: Prometheus, Grafana
- 🎬 **Media Stack**: Jellyfin, Sonarr, Radarr
- 🤖 **AI Stack**: Ollama, Open WebUI
- 📸 **Foto-Management**: Immich
- 🏠 **Home Assistant**: Smart Home Integration
- 🌐 **Netzwerk**: AdGuard, SpeedTest
- 📁 **File Management**: FileBrowser, Code Server
- 🗄️ **Backup**: Automatisierte Backup-Strategien

## Verwendung

1. Inventory anpassen: `inventory/hosts.yml`
2. Variablen konfigurieren: `group_vars/all.yml`
3. Deployment starten: `./deploy.sh`

## Struktur

```
pi5-hub-ansible/
├── README.md
├── deploy.sh                    # Haupt-Deployment-Script
├── ansible.cfg                  # Ansible Konfiguration
├── requirements.yml             # Ansible Collections
├── inventory/
├── group_vars/
├── playbooks/
├── roles/
├── scripts/
└── templates/
```

## Anforderungen

- Ansible >= 2.15
- Python >= 3.8
- SSH-Zugriff zum Raspberry Pi

## Lizenz

MIT License
EOF

# deploy.sh erstellen
cat > deploy.sh << 'EOF'
#!/bin/bash

# Pi5 Hub Ansible Deployment Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Banner
echo -e "${BLUE}"
cat << 'BANNER'
╔═══════════════════════════════════════════╗
║           Pi5 Hub Ansible Deploy          ║
║     Raspberry Pi 5 Automation Suite      ║
╚═══════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# Voraussetzungen prüfen
echo_info "Prüfe Voraussetzungen..."

if ! command -v ansible-playbook &> /dev/null; then
    echo_error "Ansible ist nicht installiert!"
    echo "Installiere Ansible: pip install ansible"
    exit 1
fi

if [ ! -f "inventory/hosts.yml" ]; then
    echo_error "Inventory-Datei nicht gefunden!"
    echo "Bitte inventory/hosts.yml konfigurieren"
    exit 1
fi

# Ansible Collections installieren
echo_info "Installiere Ansible Collections..."
ansible-galaxy install -r requirements.yml

# Syntax-Check
echo_info "Führe Syntax-Check durch..."
ansible-playbook --syntax-check -i inventory/hosts.yml playbooks/site.yml

# Deployment-Optionen
echo_info "Deployment-Optionen:"
echo "1) Vollständiges Deployment"
echo "2) Nur System-Setup (common, security, ssd_optimization)"
echo "3) Nur Docker Services"
echo "4) Dry-Run (Check-Modus)"
echo "5) Bestimmte Rolle ausführen"

read -p "Wählen Sie eine Option (1-5): " choice

case $choice in
    1)
        echo_info "Starte vollständiges Deployment..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml
        ;;
    2)
        echo_info "Starte System-Setup..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "system"
        ;;
    3)
        echo_info "Starte Docker Services..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "docker,services"
        ;;
    4)
        echo_info "Führe Dry-Run durch..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff
        ;;
    5)
        echo "Verfügbare Rollen:"
        ls -1 roles/ | sed 's/^/  - /'
        read -p "Rolle eingeben: " role_name
        if [ -d "roles/$role_name" ]; then
            ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "$role_name"
        else
            echo_error "Rolle '$role_name' nicht gefunden!"
            exit 1
        fi
        ;;
    *)
        echo_error "Ungültige Auswahl!"
        exit 1
        ;;
esac

echo_success "Deployment abgeschlossen!"
echo_info "Logs finden Sie in: /var/log/ansible/"
EOF

# ansible.cfg erstellen
cat > ansible.cfg << 'EOF'
[defaults]
inventory = inventory/hosts.yml
host_key_checking = False
timeout = 30
gathering = smart
fact_caching = memory
stdout_callback = yaml
log_path = ./ansible.log
roles_path = ./roles
collections_path = ./collections

[inventory]
enable_plugins = yaml

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF

# requirements.yml erstellen
cat > requirements.yml << 'EOF'
---
collections:
  - name: community.general
    version: ">=7.0.0"
  - name: community.docker
    version: ">=3.4.0"
  - name: ansible.posix
    version: ">=1.5.0"
  - name: community.crypto
    version: ">=2.14.0"

roles:
  - name: geerlingguy.docker
    version: ">=6.2.0"
  - name: geerlingguy.pip
    version: ">=2.2.0"
EOF

# inventory/hosts.yml erstellen
cat > inventory/hosts.yml << 'EOF'
---
all:
  children:
    pi5_hubs:
      hosts:
        pi5-hub-01:
          ansible_host: 192.168.1.100  # IP des Raspberry Pi 5 anpassen
          ansible_user: pi              # Benutzer anpassen
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          
  vars:
    # Globale SSH-Konfiguration
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_become: true
    ansible_become_method: sudo
    ansible_python_interpreter: /usr/bin/python3
EOF

# group_vars/all.yml erstellen
cat > group_vars/all.yml << 'EOF'
---
# Globale Konfigurationsvariablen für Pi5 Hub

# System-Konfiguration
timezone: "Europe/Berlin"
locale: "de_DE.UTF-8"
keyboard_layout: "de"

# Benutzer-Konfiguration
admin_user: "pi"
admin_groups: ["sudo", "docker"]

# SSD-Konfiguration
ssd_mount_point: "/mnt/ssd"
ssd_device: "/dev/sda1"  # Anpassen je nach Setup

# Docker-Konfiguration
docker_data_root: "/mnt/ssd/docker"
docker_compose_version: "2.24.0"

# Netzwerk-Konfiguration
domain_name: "pi5hub.local"
internal_network: "192.168.1.0/24"

# Service-Ports (Basis)
traefik_web_port: 80
traefik_websecure_port: 443
traefik_dashboard_port: 8080

# Monitoring
enable_monitoring: true
prometheus_port: 9090
grafana_port: 3000

# Media Services
jellyfin_port: 8096
sonarr_port: 8989
radarr_port: 7878

# AI Services
ollama_port: 11434
openwebui_port: 8081

# File Management
filebrowser_port: 8082
code_server_port: 8083

# Home Assistant
homeassistant_port: 8123

# Photo Management
immich_port: 2283

# Backup-Konfiguration
backup_enabled: true
backup_retention_days: 30
backup_location: "/mnt/ssd/backups"

# Update-Konfiguration
auto_update_enabled: false
reboot_after_update: false
EOF

# playbooks/site.yml erstellen
cat > playbooks/site.yml << 'EOF'
---
- name: Pi5 Hub Complete Setup
  hosts: pi5_hubs
  become: true
  gather_facts: true
  
  pre_tasks:
    - name: Update apt cache
      apt:
        update_cache: true
        cache_valid_time: 3600
      tags: always

  roles:
    # System Setup
    - role: common
      tags: [system, common]
    
    - role: security
      tags: [system, security]
    
    - role: ssd_optimization
      tags: [system, storage]
    
    - role: directories
      tags: [system, directories]
    
    # Docker Setup
    - role: docker
      tags: [docker, services]
    
    # Infrastructure Services
    - role: infrastructure
      tags: [docker, services, infrastructure]
    
    # Management Tools
    - role: dockge
      tags: [docker, services, management]
    
    # Monitoring Stack
    - role: monitoring
      tags: [docker, services, monitoring]
      when: enable_monitoring | default(true)
    
    # Application Stacks
    - role: media_stack
      tags: [docker, services, media]
    
    - role: ai_stack
      tags: [docker, services, ai]
    
    - role: photo_management
      tags: [docker, services, photos]
    
    - role: homeassistant
      tags: [docker, services, homeautomation]
    
    - role: networking
      tags: [docker, services, networking]
    
    - role: file_management
      tags: [docker, services, files]
    
    # System Optimization
    - role: power_management
      tags: [system, power]
    
    # Backup Strategy
    - role: backup
      tags: [system, backup]
      when: backup_enabled | default(true)

  post_tasks:
    - name: Reboot notification
      debug:
        msg: "Setup completed! Consider rebooting the system for all changes to take effect."
      tags: always
EOF

# Scripts erstellen
cat > scripts/maintenance.sh << 'EOF'
#!/bin/bash

# Pi5 Hub Maintenance Script

echo "🔧 Pi5 Hub Wartung gestartet..."

# Docker Cleanup
echo "🐳 Docker Cleanup..."
docker system prune -f
docker image prune -f

# Update System
echo "📦 System Updates..."
sudo apt update && sudo apt upgrade -y

# Check Disk Space
echo "💾 Speicherplatz prüfen..."
df -h /mnt/ssd

# Service Status
echo "⚙️  Service Status..."
docker compose -f /mnt/ssd/docker/docker-compose.yml ps

echo "✅ Wartung abgeschlossen!"
EOF

cat > scripts/health_check.sh << 'EOF'
#!/bin/bash

# Pi5 Hub Health Check Script

echo "🏥 Pi5 Hub Gesundheitscheck..."

# System Load
echo "📊 System Load:"
uptime

# Memory Usage
echo "💾 Memory Usage:"
free -h

# Disk Usage
echo "💽 Disk Usage:"
df -h

# Docker Services
echo "🐳 Docker Services:"
docker compose -f /mnt/ssd/docker/docker-compose.yml ps

# Temperature
echo "🌡️  CPU Temperature:"
vcgencmd measure_temp

echo "✅ Health Check abgeschlossen!"
EOF

cat > scripts/optimize.sh << 'EOF'
#!/bin/bash

# Pi5 Hub Performance Optimization Script

echo "⚡ Pi5 Performance Optimierung..."

# GPU Memory Split
sudo raspi-config nonint do_memory_split 16

# Enable SSD TRIM
sudo fstrim -v /mnt/ssd

# Optimize Docker
docker system prune -af

# Clear Logs
sudo journalctl --vacuum-time=7d

echo "✅ Optimierung abgeschlossen!"
EOF

# Templates erstellen
cat > templates/.env.j2 << 'EOF'
# Pi5 Hub Environment Variables
# Generated by Ansible

# Domain Configuration
DOMAIN={{ domain_name }}
INTERNAL_NETWORK={{ internal_network }}

# Data Paths
DATA_ROOT={{ docker_data_root }}
SSD_MOUNT={{ ssd_mount_point }}

# Service Ports
TRAEFIK_WEB_PORT={{ traefik_web_port }}
TRAEFIK_WEBSECURE_PORT={{ traefik_websecure_port }}
TRAEFIK_DASHBOARD_PORT={{ traefik_dashboard_port }}

JELLYFIN_PORT={{ jellyfin_port }}
SONARR_PORT={{ sonarr_port }}
RADARR_PORT={{ radarr_port }}

OLLAMA_PORT={{ ollama_port }}
OPENWEBUI_PORT={{ openwebui_port }}

PROMETHEUS_PORT={{ prometheus_port }}
GRAFANA_PORT={{ grafana_port }}

HOMEASSISTANT_PORT={{ homeassistant_port }}
IMMICH_PORT={{ immich_port }}

FILEBROWSER_PORT={{ filebrowser_port }}
CODE_SERVER_PORT={{ code_server_port }}

# User Configuration
PUID=1000
PGID=1000
TZ={{ timezone }}

# Backup Configuration
BACKUP_ENABLED={{ backup_enabled | lower }}
BACKUP_LOCATION={{ backup_location }}
BACKUP_RETENTION={{ backup_retention_days }}
EOF

# Beispiel-Dateien für einige Rollen erstellen
echo "📝 Erstelle Beispiel-Dateien für Rollen..."

# Common Role
cat > roles/common/tasks/main.yml << 'EOF'
---
- name: Update and upgrade system packages
  apt:
    upgrade: dist
    update_cache: true
    cache_valid_time: 3600
  register: apt_upgrade_result

- name: Install essential packages
  apt:
    name:
      - curl
      - wget
      - git
      - vim
      - htop
      - tree
      - unzip
      - software-properties-common
    state: present

- name: Set timezone
  timezone:
    name: "{{ timezone }}"
  notify: restart cron

- name: Configure locale
  locale_gen:
    name: "{{ locale }}"
    state: present
EOF

cat > roles/common/handlers/main.yml << 'EOF'
---
- name: restart cron
  service:
    name: cron
    state: restarted
EOF

# Docker Role Beispiel
cat > roles/docker/tasks/main.yml << 'EOF'
---
- name: Install Docker dependencies
  apt:
    name:
      - apt-transport-https
      - ca-certificates
      - gnupg
      - lsb-release
    state: present

- name: Add Docker GPG key
  apt_key:
    url: https://download.docker.com/linux/debian/gpg
    state: present

- name: Add Docker repository
  apt_repository:
    repo: "deb [arch=arm64] https://download.docker.com/linux/debian {{ ansible_distribution_release }} stable"
    state: present

- name: Install Docker
  apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
    state: present
    update_cache: true

- name: Add user to docker group
  user:
    name: "{{ admin_user }}"
    groups: docker
    append: true

- name: Start and enable Docker service
  systemd:
    name: docker
    state: started
    enabled: true
    daemon_reload: true
EOF

# Verzeichnisse Role
cat > roles/directories/tasks/main.yml << 'EOF'
---
- name: Create main data directories
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ admin_user }}"
    group: "{{ admin_user }}"
    mode: '0755'
  loop:
    - "{{ docker_data_root }}"
    - "{{ docker_data_root }}/configs"
    - "{{ docker_data_root }}/data"
    - "{{ docker_data_root }}/logs"
    - "{{ backup_location }}"
EOF

# Ausführbare Berechtigung setzen
chmod +x deploy.sh
chmod +x scripts/*.sh

echo "✅ Struktur erstellt!"
echo ""
echo "📋 Nächste Schritte:"
echo "1. Wechseln Sie in das Projektverzeichnis: cd $PROJECT_NAME"
echo "2. Passen Sie die Inventory-Datei an: nano inventory/hosts.yml"
echo "3. Konfigurieren Sie die Variablen: nano group_vars/all.yml"
echo "4. Starten Sie das Deployment: ./deploy.sh"
echo ""
echo "📁 Projektstruktur wurde erfolgreich erstellt!"
echo "📍 Speicherort: $PROJECT_DIR"