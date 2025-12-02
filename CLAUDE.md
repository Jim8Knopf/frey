# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Frey is a comprehensive Ansible project for automating the setup of a Raspberry Pi 5 as a central hub for various self-hosted services. The project deploys a complete Docker-based stack including media management (Jellyfin, Sonarr, Radarr), monitoring (Grafana, Prometheus), automation (n8n, Ollama), and infrastructure services (Traefik, Portainer) with an optional WiFi access point configuration.

## Core Commands

### Deployment
```bash
# Full deployment (all enabled features)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Selective deployment with specific tags
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "docker,infrastructure,media,networking"

# Deploy specific role
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags wifi_access_point

# Check mode (dry run)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check
```

### Testing and Validation
```bash
# Validate Docker Compose syntax
docker compose -f /opt/frey/stacks/media/docker-compose.yml config --quiet

# Test WiFi access point configuration
ansible-playbook -i inventory/hosts.yml roles/wifi_access_point/tests/verify.yml

# Check dnsmasq configuration
sudo dnsmasq --test -C /etc/dnsmasq.d/01-wifi-ap.conf
```

### Ansible Vault (Secrets Management)
```bash
# Edit encrypted secrets
ansible-vault edit group_vars/all/secrets.yml

# Run playbook with vault password
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass
```

## Architecture

### Directory Structure
```
frey/
├── inventory/
│   └── hosts.yml              # Target host configuration
├── group_vars/
│   └── all/
│       ├── main.yml          # Main configuration variables
│       └── secrets.yml       # Encrypted secrets (Ansible Vault)
├── playbooks/
│   └── site.yml              # Main playbook orchestrating all roles
├── roles/                    # Ansible roles (modular components)
│   ├── infrastructure/       # Traefik, Portainer, Dockge
│   ├── media/               # Jellyfin, Sonarr, Radarr, etc.
│   ├── monitoring/          # Prometheus, Grafana, Loki
│   ├── automation/          # Ollama, Open WebUI, n8n
│   ├── wifi_access_point/   # WiFi AP, dnsmasq, hostapd
│   ├── security/            # UFW, Fail2Ban
│   └── docker_minimal/      # Base Docker setup
└── scripts/                 # Maintenance utilities
```

### Role Organization Pattern
Each role follows this structure:
- `tasks/main.yml` - Main task execution
- `templates/` - Jinja2 templates (primarily docker-compose.yml.j2 and config files)
- `handlers/main.yml` - Service restart/reload handlers
- `defaults/main.yml` - Default variables
- `tests/` - Role-specific verification playbooks

### Configuration System

**Feature Toggles** in `group_vars/all/main.yml`:
- Enable/disable entire service stacks via `features.*` boolean flags
- Example: `features.media: true` enables the entire media stack

**Secrets Management**:
- All sensitive data stored in `group_vars/all/secrets.yml` (encrypted with Ansible Vault)
- Reference secrets in playbooks/roles using vault variable names
- Vault password stored in `.vault_pass` (gitignored)

**Service Configuration Pattern**:
Each service group (media, infrastructure, monitoring, automation) uses this structure:
```yaml
<stack_name>:
  user:
    name: <stack>_manager
    uid: <unique_id>
    groups: <stack_group>
  group:
    name: <stack>
    gid: <unique_id>
  dir: /opt/frey/<stack>
  services:
    <service_name>:
      enabled: true
      version: "latest"
      port: <port_number>
```

### Docker Network Architecture

**Network Separation**:
- `proxy` - Traefik reverse proxy network (infrastructure services)
- `localdns` - DNS resolution network
- `media_network` - Isolated media services network (10.20.0.0/24)
- WiFi AP network: 10.20.0.0/24 on wlan1 interface

**Service Discovery**:
- Traefik acts as reverse proxy on port 80/443
- AdGuard Home provides DNS resolution for `.frey` domain
- Services accessible via `http://<service>.frey` (e.g., `http://jellyfin.frey`)
- DNS rewrites configured in `network.dns_rewrites` list

### WiFi Access Point Architecture (Dual-Interface)

**Critical Understanding**:
- **wlan0** (or eth0): Client interface - connects to primary network for internet
- **wlan1**: AP interface - broadcasts WiFi network for clients
- NAT/MASQUERADE routes AP client traffic (10.20.0.0/24) through client interface
- dnsmasq provides DHCP (10.20.0.50-150) and local `.frey` DNS resolution

**Service Startup Order** (critical):
1. hostapd - activates wireless radio on wlan1
2. dnsmasq - binds to now-active interface for DHCP/DNS

**Safety**: The role includes pre-task checks to prevent reconfiguring the active SSH interface. Use `force_apply: true` to override if needed.

### Compose File Generation

**Dynamic Templating Pattern**:
All Docker stacks use Jinja2 templates (`docker-compose-<stack>.yml.j2`) that:
1. Iterate over `<stack>.services` dictionary
2. Check `enabled: true` flag for each service
3. Generate service definitions with environment variables, volumes, and labels
4. Services reference user/group IDs from `<stack>.user.*` and `<stack>.group.*`

**Volume Mounting Convention**:
- Config/data: `{{ storage.appdata_dir }}/<service>:/config` or `/data`
- Media libraries: `{{ storage.base_dir }}/media/<type>:/media/<type>`
- Downloads: `{{ media.downloads }}:/downloads`
- Stacks: `{{ storage.stacks }}/<stack>/docker-compose.yml`

## Development Workflow

### Adding a New Service

1. **Update feature toggle** in `group_vars/all/main.yml`:
   ```yaml
   features:
     new_service: true
   ```

2. **Add service configuration** under appropriate stack in `group_vars/all/main.yml`:
   ```yaml
   media:  # or infrastructure/monitoring/automation
     services:
       new_service:
         enabled: true
         version: "latest"
         port: 8080
   ```

3. **Update docker-compose template** (`roles/<stack>/templates/docker-compose-<stack>.yml.j2`):
   - Add service block within `{% if <stack>.services.new_service.enabled %}`
   - Configure volumes, environment, networks, and Traefik labels

4. **Update DNS rewrites** if web-accessible:
   ```yaml
   network:
     dns_rewrites:
       - name: new_service
   ```

5. **Update firewall ports** in `security.firewall_tcp_ports` list if external access needed

### Modifying WiFi Access Point

**Before making changes**:
- Verify you're not modifying the interface used for SSH/management
- Role will check `ansible_default_ipv4.interface` vs `network.wifi.interface`
- Use a separate WiFi adapter (wlan1) for AP mode, not your primary connection

**Configuration changes**:
- Update `network.wifi.*` variables in `group_vars/all/main.yml`
- Hostapd changes use `hostapd_cli reconfigure` (non-disruptive)
- Dnsmasq changes use `systemctl reload` (graceful)

**Debugging**:
```bash
# Check interface status
ip addr show wlan1

# View hostapd logs
sudo journalctl -u hostapd -n 50

# Check connected clients
sudo hostapd_cli -i wlan1 all_sta

# View DHCP leases
cat /var/lib/misc/dnsmasq.leases
```

### Variable Scope Best Practices

- **Role defaults** (`roles/<role>/defaults/main.yml`): Default values for role-specific variables
- **Group vars** (`group_vars/all/main.yml`): Override defaults, project-wide configuration
- **Secrets** (`group_vars/all/secrets.yml`): All sensitive data (passwords, API keys)
- **Inventory vars** (`inventory/hosts.yml`): Host-specific overrides

### Ansible Configuration

**Important settings** in `ansible.cfg`:
- `hash_behaviour = merge` - Deep merges dictionaries (important for service configs)
- `stdout_callback = yaml` - Human-readable output
- `host_key_checking = False` - Convenient for fresh Pi setups
- `forks = 5` - Parallel task execution

### Common Patterns

**User/Group Creation Pattern**:
All roles use shared task: `include_tasks: "templates/create_user.yml"` with vars:
- `stack`: Stack name (media, infrastructure, etc.)
- `folders`: List of subdirectories to create
- `checkVar`: List of required variables to verify
- `prepull_images` (optional): List of Docker images to pre-pull asynchronously; jobs are polled after kickoff and use `force_source: false` to skip images already present.

Example usage when including the shared task:

```yaml
- name: Setup <stack> user and pre-pull images
  include_tasks: "templates/create_user.yml"
  vars:
    stack: "<stack>"
    folders: [subdir_one, subdir_two]
    prepull_images: ["my/image:tag", "ghcr.io/example/app:latest"]
```

**Service Stack Deployment Pattern**:
1. Create dedicated user/group for stack
2. Pre-pull Docker images (with retry logic)
3. Template docker-compose.yml from variables
4. Validate compose file syntax
5. Deploy with `docker_compose_v2` module
6. Rescue block captures logs on failure

**Traefik Labels Pattern**:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<service>.rule=Host(`<service>.{{ network.domain_name }}`)"
  - "traefik.http.routers.<service>.entrypoints=web"
  - "traefik.http.services.<service>.loadbalancer.server.port=<port>"
```

## Known Issues and Gotchas

### Deprecation Warnings
- `community.general.yaml` callback is deprecated - use `result_format=yaml` in `ansible.builtin.default` instead (ansible-core 2.13+)
- Can silence with `deprecation_warnings=False` in ansible.cfg

### Security Considerations
- **Secrets**: Currently some secrets may be hardcoded in `group_vars/all/main.yml` - these should be moved to `secrets.yml`
- **Vault password**: Stored in `.vault_pass` file - ensure this is gitignored
- UFW firewall rules are dynamically generated from enabled features

### Docker APT Repository Conflict
The playbook includes pre-tasks to remove conflicting Docker APT sources that reference `download.docker.com` before updating the package cache.

### Network Architecture Complexity
The TODO.md notes that the network architecture "could be simplified" - the current setup uses multiple Docker networks and NAT configuration which may be more complex than necessary for some use cases.

## File Paths and Defaults

**Base directory**: `/opt/frey` (configurable via `storage.base_dir`)
- Appdata: `/opt/frey/appdata/<service>` - service configurations
- Stacks: `/opt/frey/stacks/<stack>` - docker-compose.yml files
- Media: `/opt/frey/media/{movies,tv,music,audiobooks,podcasts}`
- Downloads: `/opt/frey/downloads`

**System locations**:
- Hostapd config: `/etc/hostapd/hostapd.conf`
- Dnsmasq config: `/etc/dnsmasq.d/01-wifi-ap.conf`
- Dhcpcd config: `/etc/dhcpcd.conf`
- Traefik config: `/opt/frey/appdata/traefik/traefik.yml`

## Testing and Verification

**Post-deployment verification**:
```bash
# Check Docker containers
docker ps -a

# View compose project status
docker compose -f /opt/frey/stacks/media/docker-compose.yml ps

# Test service accessibility
curl -I http://jellyfin.frey:8096

# Check Traefik routing
curl http://traefik.frey:8082/api/http/routers
```

**DNS verification**:
```bash
# From WiFi AP client
nslookup jellyfin.frey 10.20.0.1

# Test wildcard domains
dig +short *.frey @10.20.0.1
```

## Project Roadmap (from TODO.md)

**High Priority**:
- Complete Ansible Vault encryption for all secrets
- Complete Traefik integration with internal HTTPS (self-signed certs)
- Refactor project structure (move ansible files to `ansible/` subdirectory)

**Next Level**:
- Refine variable scoping (move defaults to role-level)
- Implement system notifications (ntfy integration)
- Add post-deployment health checks

**Possible Enhancements**:
- Media optimization with Tdarr
- YouTube archival with Tube-Archivist
- Implement and test backup/restore strategy
- Add Cockpit for system management
- the ap needs internet passthrough and als need to work without external internet and it shouldnt disupt the conetet wifi becaus i might be connected over it to adjust stuf