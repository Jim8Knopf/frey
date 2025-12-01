# Gemini Code Assistant Context: Frey Home Server

This document provides a comprehensive overview of the "Frey" project, designed to serve as a persistent context for the Gemini Code Assistant. It details the project's architecture, key technologies, configuration, and operational procedures.

## 1. Project Overview

Frey is a comprehensive, production-ready Ansible automation project that transforms a Raspberry Pi 5 into a fully-featured home server. It uses an Infrastructure-as-Code (IaC) approach to deploy and manage over 40 Docker containers, providing a rich suite of self-hosted services.

### Key Service Stacks:
-   **Infrastructure**: Traefik (reverse proxy), Portainer/Dockge (Docker management), AdGuard Home (DNS).
-   **Authentication**: Authelia/LLDAP for Single Sign-On (SSO).
-   **Media**: Jellyfin, the *arr suite (Sonarr, Radarr, etc.), Audiobookshelf, and qBittorrent for a complete media center.
-   **Automation**: Home Assistant, n8n (workflow automation), and local AI with Ollama.
-   **Monitoring**: A full observability stack including Grafana, Prometheus, and Loki.
-   **Photos**: Immich for self-hosted photo management.
-   **WiFi**: A dual-interface WiFi access point with advanced roaming capabilities.

The entire system is designed to be managed with a single Ansible command, making setup and maintenance highly efficient.

## 2. Core Technologies

-   **Automation**: **Ansible** is the core technology used for configuration management and deployment orchestration.
-   **Containerization**: All applications are deployed as **Docker containers**, orchestrated using **Docker Compose**. This ensures isolation, portability, and easy management.

### Ansible Dependencies
The project relies on the following Ansible collections, as defined in `requirements.yml`:
-   `community.general`
-   `community.docker`
-   `ansible.posix`

## 3. Project Structure

The repository is organized following Ansible best practices:

```
frey/
├── inventory/
│   └── hosts.yml         # Defines the target Raspberry Pi and connection info.
├── group_vars/
│   └── all/
│       ├── main.yml      # Global configuration and feature toggles.
│       └── secrets.yml   # Encrypted secrets (passwords, API keys).
├── playbooks/
│   └── site.yml          # The main Ansible playbook that orchestrates all roles.
├── roles/                # Contains individual Ansible roles for each service stack.
│   ├── infrastructure/
│   ├── media/
│   ├── monitoring/
│   └── ... (many others)
├── docs/                 # Detailed user and setup documentation.
└── README.md             # Project summary and quick start guide.
```

## 4. Key Files & Configuration

-   **`playbooks/site.yml`**: This is the master playbook. It defines the sequence of role execution, maps roles to tags, and orchestrates the entire deployment.
-   **`inventory/hosts.yml`**: This file contains the IP address and SSH connection details for the target Raspberry Pi.
-   **`group_vars/all/main.yml`**: The central point for configuration. The most important section is `features`, which uses boolean toggles to enable or disable entire service stacks.
-   **`group_vars/all/secrets.yml`**: All sensitive data (passwords, API keys, etc.) is stored here. This file is encrypted using **Ansible Vault**.

## 5. Building and Running the Project

### Prerequisites
-   Ansible installed on the control machine.
-   SSH access to the target Raspberry Pi.
-   An Ansible Vault password file (e.g., `.vault_pass`).

### Main Execution Commands

-   **Full Deployment**: To deploy or update all enabled services:
    ```bash
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml
    ```
    (Note: The `README.md` suggests using `--vault-password-file .vault_pass`. This may or may not be needed depending on `ansible.cfg`.)

-   **Selective Deployment (Using Tags)**: To deploy a specific part of the stack, use tags. Tags are defined in `playbooks/site.yml` and generally correspond to roles.
    ```bash
    # Deploy only the media stack
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media

    # Deploy only the monitoring stack
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring
    ```

-   **Dry Run**: To preview the changes Ansible will make without actually executing them:
    ```bash
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check
    ```

## 6. Development Conventions

-   **Role-Based Architecture**: The project is highly modular. Each distinct service stack (e.g., `media`, `monitoring`) is encapsulated within its own Ansible role. This keeps concerns separated and makes the codebase easier to maintain.
-   **Feature Toggles**: The primary mechanism for enabling or disabling functionality is through the `features` dictionary in `group_vars/all/main.yml`. This is the preferred way to manage the deployment scope.
-   **Secret Management**: All secrets **must** be stored in `group_vars/all/secrets.yml` and encrypted with Ansible Vault.
    -   To edit secrets: `ansible-vault edit group_vars/all/secrets.yml`
-   **Dynamic Configuration**: The configuration is highly dynamic. For example, firewall rules in `group_vars/all/main.yml` are automatically generated based on the ports of the services that are enabled via feature toggles.
-   **Idempotency**: Playbooks and roles are written to be idempotent. They can be run multiple times, and will only make changes if the desired state does not match the current state.
