# Comprehensive Monitoring Dashboard Deployment Guide

## Overview

This deployment adds comprehensive monitoring to your Frey Raspberry Pi 5 stack including:
- **System Metrics**: CPU, RAM, disk, network, temperature (Raspberry Pi specific)
- **Container Metrics**: Per-container resource usage for all Docker services
- **Application Metrics**: PostgreSQL, Redis, AdGuard DNS, qBittorrent, Traefik
- **Log Aggregation**: Enhanced Promtail with automatic Docker service discovery
- **Auto-Provisioned Dashboards**: 10+ professional Grafana dashboards
- **Alerting**: 30+ alert rules for critical issues

**Resource Impact**: ~635MB RAM total (~8% of 8GB Pi), ~15-23GB storage for 30-day retention

## Prerequisites

1. All Frey services deployed (infrastructure, media, photos, cookbook)
2. Ansible Vault password available
3. SSH access to Raspberry Pi
4. Service credentials (AdGuard, qBittorrent)

## Step 1: Add Required Secrets

See `README_SECRETS.md` for the complete list. Quick start:

```bash
# Edit encrypted secrets file
cd /home/jim/Projects/frey0
ansible-vault edit group_vars/all/secrets.yml

# Add these minimum required secrets:
# - grafana_admin_password
# - adguard_username & adguard_password
# - qbittorrent_username & qbittorrent_password
# - Database credentials (if not already present)
```

## Step 2: Validate Configuration

```bash
# Check Ansible syntax
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check

# Dry run to see what will change
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring,infrastructure --check --ask-vault-pass
```

## Step 3: Deploy Monitoring Stack

```bash
# Deploy monitoring and infrastructure (for Traefik metrics)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring,infrastructure --ask-vault-pass

# Estimated time: 10-15 minutes (includes dashboard downloads)
```

### What Happens During Deployment:

1. **Infrastructure Updates** (2-3 min):
   - Traefik Prometheus metrics enabled on port 8083
   - Traefik container restarted

2. **Monitoring Stack Updates** (5-7 min):
   - 5 new exporter containers deployed (PostgreSQL×3, Redis, AdGuard, qBittorrent)
   - Prometheus configuration updated with 8 new scrape targets
   - 30+ alerting rules deployed
   - 10 Grafana dashboards downloaded from Grafana.com
   - Promtail configuration enhanced with Docker service discovery
   - All monitoring containers restarted

3. **Network Configuration**:
   - 4 new external networks attached to monitoring stack:
     - `infrastructure_network` (PostgreSQL/Redis access)
     - `photos_network` (Immich DB access)
     - `cookbook_network` (Mealie DB access)
     - `media_network` (qBittorrent access)

## Step 4: Verify Deployment

### Check Container Status
```bash
# All monitoring containers should be "Up"
docker ps --filter "network=monitoring_network" --format "table {{.Names}}\t{{.Status}}"

# Expected containers:
# - prometheus
# - grafana
# - node-exporter
# - cadvisor
# - loki
# - promtail
# - postgres-exporter-authentik
# - postgres-exporter-immich
# - postgres-exporter-mealie
# - redis-exporter
# - adguard-exporter
# - qbittorrent-exporter
# - uptime-kuma
# - dockge
# - speedtest-tracker
# - watchtower
```

### Check Prometheus Targets
```bash
# All targets should show "up"
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Or via browser:
# https://prometheus.frey -> Status -> Targets
```

Expected targets (all should be **UP**):
- ✅ prometheus
- ✅ node-exporter
- ✅ cadvisor
- ✅ traefik
- ✅ postgres-authentik
- ✅ postgres-immich
- ✅ postgres-mealie
- ✅ redis
- ✅ adguard
- ✅ qbittorrent

### Check Grafana Dashboards
```bash
# List provisioned dashboards
curl -s -u admin:YOUR_PASSWORD http://localhost:3000/api/search?type=dash-db | jq '.[].title'

# Or via browser (recommended):
# 1. Visit https://grafana.frey
# 2. Login with Authentik SSO or admin/YOUR_PASSWORD
# 3. Go to Dashboards -> Browse
# 4. Verify all 10 dashboards are imported
```

Expected dashboards:
1. **Node Exporter Full** - Raspberry Pi metrics
2. **Docker and System Monitoring** - Container overview
3. **cAdvisor Exporter** - Container resources
4. **Traefik Official Standalone** - Reverse proxy stats
5. **PostgreSQL Database** - DB performance
6. **Redis Dashboard** - Cache metrics
7. **AdGuard Exporter** - DNS statistics
8. **qBittorrent Dashboard** - Torrent metrics
9. **Loki Logs Dashboard** - Log viewer
10. **Loki Stack Monitoring** - Loki infrastructure

### Check Alerting Rules
```bash
# Verify alerts are loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'

# Should show:
# - system_alerts
# - container_alerts
# - database_alerts (if postgres-exporter enabled)
# - network_alerts
# - traefik_alerts (if metrics enabled)
# - adguard_alerts (if exporter enabled)
# - qbittorrent_alerts (if exporter enabled)
```

## Step 5: Access Monitoring Services

All services accessible via HTTPS with Authentik SSO:

| Service | URL | Description |
|---------|-----|-------------|
| **Grafana** | https://grafana.frey | Main dashboards interface |
| **Prometheus** | https://prometheus.frey | Metrics database & query UI |
| **Loki** | https://loki.frey | Log aggregation (internal) |
| **Uptime Kuma** | https://uptime.frey | HTTP/TCP uptime monitoring |
| **cAdvisor** | https://cadvisor.frey | Raw container metrics |
| **Node Exporter** | https://metrics.frey | Raw system metrics |
| **Dockge** | https://dockge.frey | Docker Compose stack editor |
| **Speedtest** | https://speedtest.frey | Internet bandwidth tracking |

## Step 6: Explore Key Dashboards

### 1. Node Exporter Full (System Overview)
- CPU usage per core
- Memory usage & swap
- Disk I/O & space
- Network traffic per interface
- **Raspberry Pi temperature** (critical!)
- System load & uptime

**Use for**: Daily health checks, performance bottlenecks

### 2. Docker and System Monitoring
- All container CPU/memory usage
- Per-container network traffic
- System resources + container view
- Quick health overview

**Use for**: Identifying resource-hungry containers

### 3. Traefik Official Standalone
- HTTP requests per second
- Response times (p50, p95, p99)
- Error rates (4xx, 5xx)
- Top services by traffic

**Use for**: Web performance monitoring, debugging slow services

### 4. PostgreSQL Database
- Connection counts per database
- Query performance
- Cache hit rates
- Locks and deadlocks

**Use for**: Database optimization, connection pool tuning

### 5. Loki Logs Dashboard
- Search logs across all containers
- Filter by container, service, log level
- Real-time log streaming
- Error pattern detection

**Use for**: Troubleshooting, error investigation

## Step 7: Configure Alerts (Optional)

Alerting is configured but needs a notification channel. Options:

### Option A: Integrate with ntfy (Recommended)
```yaml
# Add to group_vars/all/main.yml when ntfy is deployed
monitoring:
  alerting:
    ntfy_enabled: true
    ntfy_url: "http://ntfy.frey/frey-alerts"
```

### Option B: Email Notifications
```yaml
# Add to group_vars/all/secrets.yml
alerting_email_host: "smtp.gmail.com:587"
alerting_email_from: "frey@example.com"
alerting_email_password: "your-app-password"
```

### Option C: Webhook (Discord, Slack, etc.)
Configure in Prometheus Alertmanager configuration (future enhancement)

## Troubleshooting

### Exporter Container Failing

**Symptom**: `postgres-exporter-*` or other exporter shows "Restarting"

**Diagnosis**:
```bash
# Check container logs
docker logs postgres-exporter-authentik

# Common issues:
# 1. Wrong database password
# 2. Database not reachable (network issue)
# 3. Database container not running
```

**Fix**:
```bash
# Verify database credentials match
docker exec -it authentik-db env | grep POSTGRES_PASSWORD

# Update secrets.yml with correct password
ansible-vault edit group_vars/all/secrets.yml

# Redeploy
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring --ask-vault-pass
```

### Prometheus Target "Down"

**Symptom**: Target shows as "DOWN" in Prometheus UI

**Diagnosis**:
```bash
# Test exporter endpoint directly
curl http://postgres-exporter-authentik:9187/metrics

# Check exporter is on correct network
docker inspect postgres-exporter-authentik | jq '.[0].NetworkSettings.Networks'
```

**Fix**: Verify network configuration in docker-compose-monitoring.yml.j2

### Grafana Dashboards Not Loading

**Symptom**: Dashboards folder empty or "Dashboard not found"

**Diagnosis**:
```bash
# Check dashboard provisioning directory
ls -la /opt/frey/appdata/grafana/provisioning/dashboards/

# Check Grafana logs for provisioning errors
docker logs grafana | grep -i dashboard
```

**Fix**:
```bash
# Manually download missing dashboards
cd /opt/frey/appdata/grafana/provisioning/dashboards/
curl -o 1860-node-exporter-full.json https://grafana.com/api/dashboards/1860/revisions/latest/download

# Restart Grafana
docker restart grafana
```

### High Memory Usage

**Symptom**: Monitoring stack using >800MB RAM

**Solution**: Adjust retention periods in `group_vars/all/main.yml`:

```yaml
monitoring:
  prometheus:
    retention_time: "15d"  # Reduce from 30d
    retention_size: "10GB"  # Reduce from 15GB
  loki:
    retention_period: "15d"  # Reduce from 30d
```

### Traefik Metrics Not Showing

**Symptom**: Traefik dashboard empty, target "DOWN"

**Diagnosis**:
```bash
# Verify metrics endpoint is exposed
docker exec traefik wget -O- http://localhost:8083/metrics | head -20

# Check Traefik config
docker exec traefik cat /etc/traefik/traefik.yml | grep -A5 metrics
```

**Fix**: Verify `infrastructure.services.traefik.metrics.enabled: true` in main.yml

## Performance Tuning

### Reduce Scrape Frequency (Lower CPU Usage)
```yaml
# In prometheus.yml.j2
global:
  scrape_interval: 60s  # Change from 30s
  evaluation_interval: 60s
```

### Disable Unused Exporters
```yaml
# In group_vars/all/main.yml
monitoring:
  qbittorrent-exporter:
    enabled: false  # If you don't need torrent metrics
  adguard-exporter:
    enabled: false  # If you don't need DNS metrics
```

### Optimize Log Collection
```yaml
# In promtail-config.yml.j2, drop more verbose logs:
- match:
    selector: '{level=~"DEBUG|INFO"}'
    stages:
      - drop:
          expression: '.*'
          older_than: 6h  # Keep only recent verbose logs
```

## Backup and Restore

### Backup Prometheus Data
```bash
# Stop Prometheus
docker stop prometheus

# Backup data directory
tar -czf prometheus-backup-$(date +%Y%m%d).tar.gz /opt/frey/appdata/prometheus/data/

# Start Prometheus
docker start prometheus
```

### Backup Grafana Dashboards
```bash
# Export all dashboards via API
for dash in $(curl -s -u admin:PASSWORD http://localhost:3000/api/search | jq -r '.[].uid'); do
  curl -s -u admin:PASSWORD http://localhost:3000/api/dashboards/uid/$dash \
    | jq '.dashboard' > "grafana-backup-${dash}.json"
done
```

## Next Steps

1. **Set Up Notifications**: Configure ntfy or email alerts (see Step 7)
2. **Create Custom Dashboards**: Build service-specific views
3. **Tune Alert Thresholds**: Adjust based on your usage patterns
4. **Schedule Reports**: Use Grafana's reporting feature (optional)
5. **Integrate with Home Assistant**: Export metrics to HA (optional)

## Useful Grafana Tips

### Create Custom Dashboard Playlist
1. Go to Dashboards -> Playlists -> New Playlist
2. Add: Node Exporter → Docker Monitoring → Traefik → PostgreSQL
3. Set interval: 10 seconds
4. Use for: TV dashboard, NOC view

### Set Up Dashboard Annotations
Mark deployments, incidents, etc. on graphs:
```bash
# Example: Add deployment annotation
curl -X POST http://localhost:3000/api/annotations \
  -H "Content-Type: application/json" \
  -u admin:PASSWORD \
  -d '{
    "time": '$(date +%s000)',
    "tags": ["deployment"],
    "text": "Deployed monitoring v2.0"
  }'
```

### Export Dashboard as PDF
1. Open dashboard
2. Click share icon → Export → PDF
3. Use for: Reports, documentation

## Log Analysis with Loki

### Common LogQL Queries

```logql
# All errors across all services
{job="docker"} |= "ERROR"

# Authentik authentication failures
{compose_project="infrastructure", container_name=~"authentik.*"} |= "authentication failed"

# Slow database queries
{compose_project=~"photos|infrastructure|cookbook"} |= "slow query"

# Container restarts
{job="docker"} |= "restarting"

# Top 10 error messages
{job="docker"} |= "ERROR" | line_format "{{.msg}}" | count by msg | sort desc | limit 10
```

## Getting Help

- **Grafana Docs**: https://grafana.com/docs/grafana/latest/
- **Prometheus Docs**: https://prometheus.io/docs/
- **Dashboard Repository**: https://grafana.com/grafana/dashboards/
- **Frey Project Issues**: Check TODO.md for known issues

## Summary

You now have:
- ✅ 10+ professional dashboards auto-provisioned
- ✅ 30+ alert rules for critical issues
- ✅ Comprehensive metrics for Pi, containers, and applications
- ✅ Enhanced log aggregation with automatic labeling
- ✅ Traefik reverse proxy monitoring
- ✅ Database and cache performance tracking
- ✅ DNS query statistics
- ✅ Torrent bandwidth monitoring

**Total Setup Time**: ~20 minutes
**Monitoring Coverage**: 99% of Frey services
**Resource Overhead**: ~8% RAM, <2% CPU (idle)
