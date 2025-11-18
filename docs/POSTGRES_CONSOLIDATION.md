# PostgreSQL Database Consolidation Guide

## Overview

This guide documents the consolidation of multiple PostgreSQL instances into a single shared PostgreSQL server with separate databases for each service.

### Before Consolidation
- **3 separate PostgreSQL containers**:
  - `authentik_postgres` (PostgreSQL 16-alpine)
  - `mealie_postgres` (PostgreSQL 15-alpine)
  - `immich_postgres` (PostgreSQL 14 with VectorChord extension)

### After Consolidation
- **1 shared PostgreSQL container**:
  - `shared_postgres` (PostgreSQL 14 with VectorChord extension)
  - Contains 3 separate databases: `authentik`, `mealie`, `immich`
  - Uses Immich's specialized build to support VectorChord for vector search

## Benefits

1. **Resource Savings**: Reduces memory and CPU overhead from running 3 PostgreSQL instances to 1
2. **Simplified Backups**: Single database server to backup instead of 3
3. **Easier Maintenance**: One PostgreSQL version to upgrade and monitor
4. **Network Efficiency**: Reduced network complexity in Docker

## Architecture Changes

### Shared PostgreSQL Configuration
- **Image**: `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`
- **Location**: Infrastructure role (`roles/infrastructure/`)
- **Data Directory**: `/opt/frey/appdata/shared-postgres/data`
- **Networks**:
  - `infrastructure_network` (for Authentik)
  - `photos_network` (for Immich)
  - `cookbook` (for Mealie)

### Database Initialization
The init script (`roles/infrastructure/templates/init-shared-postgres.sh.j2`) creates:
- 3 databases: `authentik`, `mealie`, `immich`
- 3 users with respective passwords from `secrets.yml`
- VectorChord extension configured for Immich database

### Service Configuration Updates

#### Authentik
- **Environment Variable Change**: `AUTHENTIK_POSTGRESQL__HOST` = `shared-postgres`
- **Depends On**: `shared-postgres` (conditional)
- **Old Container**: `authentik-db` (disabled when shared_postgres enabled)

#### Mealie
- **Environment Variable Change**: `POSTGRES_SERVER` = `shared-postgres`
- **Network Addition**: Joins `infrastructure_network`
- **Old Container**: `mealie-postgres` (disabled when shared_postgres enabled)

#### Immich
- **Environment Variable Change**: `DB_HOSTNAME` = `shared-postgres`
- **Network**: Already on `infrastructure_network`
- **Old Container**: `database` (immich_postgres) (disabled when shared_postgres enabled)

## Prerequisites

### Required Secrets
Add the following to `group_vars/all/secrets.yml` (Ansible Vault encrypted):

```yaml
# Shared PostgreSQL admin password
shared_postgres_admin_password: "GENERATE_STRONG_PASSWORD_HERE"

# Existing passwords (must already exist)
authentik_postgres_password: "..."
mealie_db_password: "..."
immich_db_password: "..."
```

Generate a strong password for `shared_postgres_admin_password`:
```bash
openssl rand -base64 32
```

Edit secrets file:
```bash
ansible-vault edit group_vars/all/secrets.yml
```

## Migration Steps

### Option 1: Fresh Deployment (No Existing Data)

If you're deploying fresh or can afford to lose existing database data:

1. **Enable shared PostgreSQL** in `group_vars/all/main.yml`:
   ```yaml
   infrastructure:
     services:
       shared_postgres:
         enabled: true
   ```

2. **Deploy infrastructure stack**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure --ask-vault-pass
   ```

3. **Deploy other stacks**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags cookbook,immich --ask-vault-pass
   ```

4. **Verify all services are running**:
   ```bash
   docker ps | grep -E '(shared_postgres|authentik|mealie|immich)'
   ```

### Option 2: Migration with Data Preservation

If you have existing data in separate databases:

#### Step 1: Backup Existing Databases

```bash
# Backup Authentik database
docker exec authentik_postgres pg_dump -U authentik authentik > /tmp/authentik_backup.sql

# Backup Mealie database
docker exec mealie_postgres pg_dump -U mealie mealie > /tmp/mealie_backup.sql

# Backup Immich database
docker exec immich_postgres pg_dump -U immich immich > /tmp/immich_backup.sql
```

#### Step 2: Stop Services

```bash
# Stop all services that use databases
docker compose -f /opt/frey/stacks/infrastructure/docker-compose.yml down
docker compose -f /opt/frey/stacks/cookbook/docker-compose.yml down
docker compose -f /opt/frey/stacks/immich/docker-compose.yml down
```

#### Step 3: Enable Shared PostgreSQL

Edit `group_vars/all/main.yml`:
```yaml
infrastructure:
  services:
    shared_postgres:
      enabled: true
```

#### Step 4: Deploy Infrastructure with Shared PostgreSQL

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure --ask-vault-pass
```

#### Step 5: Restore Databases

```bash
# Wait for shared PostgreSQL to be healthy
docker exec shared_postgres pg_isready -U postgres

# Restore Authentik
cat /tmp/authentik_backup.sql | docker exec -i shared_postgres psql -U authentik -d authentik

# Restore Mealie
cat /tmp/mealie_backup.sql | docker exec -i shared_postgres psql -U mealie -d mealie

# Restore Immich
cat /tmp/immich_backup.sql | docker exec -i shared_postgres psql -U immich -d immich
```

#### Step 6: Deploy Remaining Services

```bash
# Deploy cookbook (Mealie)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags cookbook --ask-vault-pass

# Deploy Immich
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags immich --ask-vault-pass
```

#### Step 7: Verify Services

```bash
# Check all containers are running
docker ps

# Check Authentik can connect to database
docker logs authentik_server | grep -i database

# Check Mealie can connect to database
docker logs mealie | grep -i postgres

# Check Immich can connect to database
docker logs immich_server | grep -i database
```

#### Step 8: Clean Up Old Database Volumes (Optional)

After verifying everything works:

```bash
# Remove old database volumes (WARNING: This deletes data!)
docker volume rm $(docker volume ls -q | grep -E '(authentik-db|mealie-db|immich-db)')

# Or manually remove old data directories
rm -rf /opt/frey/appdata/authentik/database
rm -rf /opt/frey/appdata/mealie/db
rm -rf /opt/frey/appdata/immich-db
```

## Rollback Instructions

If you need to rollback to separate databases:

1. **Disable shared PostgreSQL** in `group_vars/all/main.yml`:
   ```yaml
   infrastructure:
     services:
       shared_postgres:
         enabled: false
   ```

2. **Redeploy all stacks**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass
   ```

The old database containers will be recreated and services will use them instead.

## Verification

### Check Shared PostgreSQL is Running

```bash
docker ps | grep shared_postgres
docker logs shared_postgres
```

### Verify Databases Were Created

```bash
docker exec shared_postgres psql -U postgres -c "\l"
```

Expected output should show:
- `authentik` database owned by `authentik` user
- `mealie` database owned by `mealie` user
- `immich` database owned by `immich` user

### Test Database Connections

```bash
# Test Authentik database
docker exec shared_postgres psql -U authentik -d authentik -c "SELECT version();"

# Test Mealie database
docker exec shared_postgres psql -U mealie -d mealie -c "SELECT version();"

# Test Immich database
docker exec shared_postgres psql -U immich -d immich -c "SELECT version();"
```

### Verify VectorChord Extension for Immich

```bash
docker exec shared_postgres psql -U immich -d immich -c "SELECT * FROM pg_extension WHERE extname LIKE '%vector%';"
```

### Check Service Health

```bash
# Authentik
curl -I http://auth.frey

# Mealie
curl -I http://cookbook.frey

# Immich
curl -I http://immich.frey
```

## Troubleshooting

### Shared PostgreSQL Won't Start

Check logs:
```bash
docker logs shared_postgres
```

Common issues:
- Data directory permissions (should be owned by UID 999)
- Init script syntax errors
- Missing passwords in secrets.yml

### Service Can't Connect to Database

1. Verify the service is on the correct network:
   ```bash
   docker network inspect infrastructure_network
   docker network inspect photos_network
   docker network inspect cookbook_network
   ```

2. Check service environment variables:
   ```bash
   docker exec <service_container> env | grep -i postgres
   ```

3. Verify database credentials match secrets.yml

### Immich Vector Search Not Working

Verify VectorChord extension is loaded:
```bash
docker exec shared_postgres psql -U immich -d immich -c "SHOW search_path;"
```

Should include `vectors` in the search path.

Check shared libraries:
```bash
docker exec shared_postgres psql -U immich -d immich -c "SHOW shared_preload_libraries;"
```

Should show `vchord.so`.

### Database Migration Failed

If restoration fails, you can recreate databases manually:

```bash
# Connect as postgres admin
docker exec -it shared_postgres psql -U postgres

# Drop and recreate database
DROP DATABASE IF EXISTS <database_name>;
CREATE DATABASE <database_name> OWNER <user_name>;

# Exit and try restore again
\q
```

## Performance Monitoring

Monitor shared PostgreSQL performance:

```bash
# Check running queries
docker exec shared_postgres psql -U postgres -c "SELECT pid, usename, datname, state, query FROM pg_stat_activity WHERE state != 'idle';"

# Check database sizes
docker exec shared_postgres psql -U postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"

# Check connection counts
docker exec shared_postgres psql -U postgres -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"
```

## Backup Strategy

### Automated Backups

Consider implementing automated backups:

```bash
#!/bin/bash
# /opt/frey/scripts/backup-shared-postgres.sh

BACKUP_DIR="/opt/frey/backups/postgres"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup all databases
docker exec shared_postgres pg_dumpall -U postgres > "$BACKUP_DIR/all_databases_$DATE.sql"

# Backup individual databases
docker exec shared_postgres pg_dump -U authentik authentik > "$BACKUP_DIR/authentik_$DATE.sql"
docker exec shared_postgres pg_dump -U mealie mealie > "$BACKUP_DIR/mealie_$DATE.sql"
docker exec shared_postgres pg_dump -U immich immich > "$BACKUP_DIR/immich_$DATE.sql"

# Compress backups
gzip "$BACKUP_DIR"/*_$DATE.sql

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
```

Schedule with cron:
```bash
0 2 * * * /opt/frey/scripts/backup-shared-postgres.sh
```

## Files Modified

This consolidation touched the following files:

### Infrastructure Role
- `roles/infrastructure/templates/docker-compose-infrastructure.yml.j2`
- `roles/infrastructure/templates/init-shared-postgres.sh.j2` (new)
- `roles/infrastructure/tasks/main.yml`

### Cookbook Role
- `roles/cookbook/templates/docker-compose-cookbook.yml.j2`
- `roles/cookbook/templates/.env.j2`

### Immich Role
- `roles/immich/templates/docker-compose-immich.yml.j2`
- `roles/immich/templates/.env.j2`

### Configuration
- `group_vars/all/main.yml` (added shared_postgres config, immich db credentials)
- `group_vars/all/secrets.yml` (needs `shared_postgres_admin_password`)

## Future Enhancements

1. **Automated Migration Playbook**: Create an Ansible playbook that handles the entire migration automatically
2. **Health Monitoring**: Add PostgreSQL exporter for Prometheus/Grafana monitoring
3. **Connection Pooling**: Consider adding PgBouncer for connection pooling if needed
4. **Read Replicas**: For high availability, consider PostgreSQL replication
5. **Jellystat Integration**: If enabled, add Jellystat database to shared instance

## References

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [Immich PostgreSQL Requirements](https://immich.app/docs/install/requirements)
- [VectorChord Extension](https://github.com/tensorchord/VectorChord)
- [Docker PostgreSQL Best Practices](https://docs.docker.com/samples/postgres/)
