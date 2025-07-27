# Frey - A Raspberry Pi 5 Hub Ansible Project

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive Ansible project for the automated setup of a Raspberry Pi 5 as a central hub for various services.

## Features

- 🔧 **System Setup**: Base configuration and optimizations
- 🔒 **Security**: UFW Firewall, Fail2Ban
- 💾 **SSD Optimization**: Special optimizations for SSD storage
- 🐳 **Docker Stack**: Containerized services
- 📊 **Monitoring**: Prometheus, Grafana
- 🎬 **Media Stack**: Jellyfin, Sonarr, Radarr
- 🤖 **AI Stack**: Ollama, Open WebUI
- 📸 **Photo Management**: Immich
- 🏠 **Home Assistant**: Smart Home Integration
- 🌐 **Network**: AdGuard, SpeedTest
- 📁 **File Management**: FileBrowser, Code Server
- 🗄️ **Backup**: Automated backup strategies

## Usage

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Jim8Knopf/frey.git
    cd frey
    ```
2.  **Configure your setup:**
    - Adjust the inventory in `inventory/hosts.yml` to match your Raspberry Pi's IP address.
    - Configure the main variables in `group_vars/all.yml`. See the Configuration section below for details.
3.  **Start the deployment:**
    ```bash
    ./deploy.sh
    ```
    The script will present a menu with different deployment options.

## Configuration

The main configuration file is `group_vars/all.yml`. Here are some of the most important variables to review:

-   `domain_name`: The local domain for your services (e.g., `frey`). This will make your services available at `http://jellyfin.frey`, `http://grafana.frey`, etc.
-   `media_uid` & `media_gid`: The user and group ID for file permissions. Use the `id` command on your host to find the correct values.
-   `timezone`: Set your local timezone (e.g., `Europe/Berlin`).
-   `*_port`: Review the default ports for all services to avoid conflicts on your network.

## Post-Installation

After a successful deployment, your services will be available at the domains configured via Traefik and AdGuard. For example, if your `domain_name` is `frey`:

-   **Jellyfin:** `http://jellyfin.frey`
-   **Grafana:** `http://grafana.frey`
-   **Portainer:** `http://portainer.frey`

## Structure

```
frey/ 
 ├── README.md 
 ├── deploy.sh # Main Deployment Script 
 ├── ansible.cfg # Ansible Configuration 
 ├── requirements.yml # Ansible Collections 
 ├── inventory/ 
 ├── group_vars/ 
 ├── playbooks/ 
 ├── roles/ 
 ├── scripts/ 
 └── templates/
```

## Requirements

- Ansible >= 2.15
- Python >= 3.8
- SSH access to the Raspberry Pi

## License

MIT License
