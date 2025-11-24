# Required Secrets for Comprehensive Monitoring Setup

This document lists the secrets that need to be added to `group_vars/all/secrets.yml` (encrypted with Ansible Vault) for the comprehensive monitoring solution to work.

## How to Add Secrets

```bash
# Edit the encrypted secrets file
ansible-vault edit group_vars/all/secrets.yml
```

## Required Secrets

Add the following variables to your `secrets.yml` file:

```yaml
# ==============================================================================
# MONITORING STACK SECRETS
# ==============================================================================

# Grafana Admin Password
# Used for: Local Grafana admin account (also uses Authentik SSO)
grafana_admin_password: "your-secure-password-here"

# AdGuard Home Credentials
# Used for: AdGuard exporter to collect DNS statistics
adguard_username: "admin"
adguard_password: "your-adguard-password"

# qBittorrent Credentials
# Used for: qBittorrent exporter to collect torrent metrics
qbittorrent_username: "admin"
qbittorrent_password: "your-qbittorrent-password"

# ==============================================================================
# DATABASE CREDENTIALS (if not already present)
# ==============================================================================

# Authentik PostgreSQL (likely already exists)
authentik_db_user: "authentik"
authentik_db_name: "authentik"
authentik_postgres_password: "your-authentik-db-password"

# Immich PostgreSQL (uses hardcoded user/db names)
# User: immich (hardcoded in .env)
# Database: immich (hardcoded in .env)
# Only password needs to be in secrets:
immich_db_password: "your-immich-db-password"

# Mealie PostgreSQL
cookbook:
  db_user: "mealie"
  db_name: "mealie"
  db_password: "your-mealie-db-password"

# Grafana OIDC Client Secret (if using Authentik SSO - likely already exists)
grafana_oidc_client_secret: "your-grafana-oidc-secret"
```

## How to Find Existing Passwords

If you don't remember your service passwords, you can find them in the running containers:

### AdGuard Home Password
```bash
# Reset via AdGuard UI or check docker-compose environment
docker exec -it adguardhome cat /opt/adguardhome/conf/AdGuardHome.yaml | grep password
```

### qBittorrent Password
```bash
# Default username is usually 'admin', check Web UI settings
# Or regenerate: Settings -> Web UI -> Authentication
```

### Database Passwords
```bash
# Check existing environment variables in running containers
docker exec -it authentik_postgres env | grep POSTGRES_PASSWORD
docker exec -it immich-postgres env | grep POSTGRES_PASSWORD
docker exec -it mealie-db env | grep POSTGRES_PASSWORD
```

## Verification After Adding Secrets

After adding the secrets and deploying, verify the exporters are working:

```bash
# Check all exporters are running
docker ps | grep exporter

# Check Prometheus scrape targets
curl -s http://prometheus.frey:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Should show all jobs as "up":
# - prometheus
# - node-exporter
# - cadvisor
# - traefik (if enabled)
# - postgres-authentik
# - postgres-immich
# - postgres-mealie
# - redis
# - adguard
# - qbittorrent
```

## Security Notes

- **Never commit unencrypted secrets** to version control
- Use strong, unique passwords for each service
- The `secrets.yml` file is encrypted with Ansible Vault - keep the vault password safe
- Database credentials should match what's already configured in running services
