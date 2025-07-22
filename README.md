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
