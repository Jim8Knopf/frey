# Media Optimization Services

This document describes the media optimization services that have been added to the Frey media stack to enhance library management, transcoding, and automation.

## Overview

The following services have been added to optimize your media library:

1. **Tdarr** - Distributed transcoding automation
2. **Umlautarr** - Foreign character handling for *arr applications
3. **Recyclarr** - TRaSH guides synchronization
4. **Unpackerr** - Automatic archive extraction

### Infrastructure as Code Benefits

This implementation follows **full Infrastructure as Code (IaC)** principles:

**Automated Configuration**:
- ✅ All service configurations deployed via Ansible templates
- ✅ No manual file editing required on the server
- ✅ Configuration versioned in Git alongside your code
- ✅ Idempotent deployments (safe to re-run)
- ✅ Automatic service restarts via Ansible handlers

**Reproducible Deployments**:
- ✅ Complete rebuild from configuration files
- ✅ Disaster recovery through Git repository
- ✅ Easy to test changes (dry-run mode)
- ✅ Audit trail via Git commits

**Configuration as Code**:
- `group_vars/all/main.yml` - Service definitions and settings
- `group_vars/all/secrets.yml` - Encrypted API keys (Ansible Vault)
- `roles/media/templates/` - Configuration file templates
- `roles/media/tasks/main.yml` - Deployment automation

## Services

### Tdarr

**Purpose**: Automated media transcoding and optimization to reduce storage usage and ensure compatibility.

**Features**:
- Convert video files from h264 to h265 (HEVC) - saves 40-50% storage space
- Distributed processing across multiple nodes
- Video health checks and analytics
- GPU/CPU hardware acceleration support
- Plugin-based workflow system

**Access**:
- Web UI: `https://tdarr.frey`
- Port: 8265

**Initial Setup**:
1. Access the web UI at `https://tdarr.frey`
2. Configure your media library paths:
   - `/media/movies` - Movie library
   - `/media/tv` - TV show library
3. Set up transcoding rules using Tdarr plugins:
   - Recommended: "Migz-Transcode using H265" plugin for space savings
   - Configure quality settings based on your needs
4. Set the temporary transcoding directory: `/temp` (already configured)
5. Configure scheduling to avoid peak usage times

**Hardware Acceleration** (Raspberry Pi 5):
To enable hardware acceleration, uncomment the devices section in `group_vars/all/main.yml`:
```yaml
devices:
  - /dev/dri:/dev/dri  # For hardware transcoding
```

**Configuration Notes**:
- Tdarr runs with 2 nodes by default (tdarr server + tdarr-node)
- You can add more nodes by duplicating the tdarr_node configuration
- Transcode cache is stored in `/opt/frey/tdarr/transcode_cache`

### Umlautarr

**Purpose**: Middleware proxy that handles foreign characters and special symbols in media searches for Sonarr, Radarr, Lidarr, and Readarr.

**Features**:
- Fixes issues with umlauts (ä, ö, ü) and other special characters
- Transparent proxy for indexer requests
- Particularly useful for German, French, and other non-English content

**Access**:
- Web UI: `https://umlautarr.frey`
- Port: 3000

**Setup**:
1. Access Prowlarr at `https://prowlarr.frey`
2. For each indexer, update the base URL to point through Umlautarr:
   - Original: `http://indexer-site.com`
   - Updated: `http://umlautarr:3000/indexer-site.com`
3. Alternatively, configure directly in Sonarr/Radarr/Lidarr/Readarr indexer settings

**Example Configuration**:
If you have an indexer like `https://example-indexer.com`, configure it as:
```
http://umlautarr:3000/example-indexer.com
```

### Recyclarr

**Purpose**: Automatically synchronize TRaSH guides to your Sonarr, Radarr, and other *arr applications for optimal quality profiles and release naming.

**Features**:
- Syncs TRaSH guides for quality profiles
- Custom formats for better release selection
- Automatic daily updates via cron
- Consistent configuration across all *arr apps

**Access**: No web UI (command-line/scheduled task only)

**Setup**:
1. Create a configuration file at `/opt/frey/appdata/recyclarr/recyclarr.yml`:

```yaml
sonarr:
  sonarr-main:
    base_url: http://sonarr:8989
    api_key: !env_var SONARR_API_KEY
    quality_definition:
      type: series
    quality_profiles:
      - name: HD-1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
          until_score: 10000
        min_format_score: 0
        quality_sort: top
        qualities:
          - name: Bluray-1080p
          - name: WEB 1080p
          - name: HDTV-1080p

radarr:
  radarr-main:
    base_url: http://radarr:7878
    api_key: !env_var RADARR_API_KEY
    quality_definition:
      type: movie
    quality_profiles:
      - name: HD-1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
          until_score: 10000
        min_format_score: 0
        qualities:
          - name: Bluray-1080p
          - name: WEB 1080p
```

2. The service runs automatically once per day via cron (`@daily` schedule)

3. Manual sync can be triggered with:
```bash
docker exec recyclarr recyclarr sync
```

### Unpackerr

**Purpose**: Automatically extracts compressed/archived downloads for Sonarr, Radarr, and Lidarr.

**Features**:
- Monitors download folders for .rar, .zip, .7z archives
- Automatically extracts when download completes
- Cleans up archive files after extraction
- Integrates with all *arr applications

**Access**: No web UI (background service)

**Setup**:
Unpackerr is pre-configured to work with your *arr applications. It requires API keys for:
- Sonarr
- Radarr
- Lidarr

**Add API keys to secrets.yml**:
```bash
ansible-vault edit group_vars/all/secrets.yml
```

Add the following keys:
```yaml
# *arr API Keys (get from each service's Settings → General → API Key)
sonarr_api_key: "your-sonarr-api-key-here"
radarr_api_key: "your-radarr-api-key-here"
lidarr_api_key: "your-lidarr-api-key-here"
audiobookshelf_api_token: "your-audiobookshelf-token-here"  # For audiobook-bridge
```

**Monitoring**:
Check Unpackerr logs:
```bash
docker logs unpackerr
```

## Infrastructure as Code (IaC) Approach

This implementation follows a fully automated Infrastructure as Code approach. All configurations are managed via Ansible templates and deployed automatically.

### Automated Configuration Management

**Configuration Files Deployed**:
- **Recyclarr**: `/opt/frey/appdata/recyclarr/recyclarr.yml` (TRaSH guides sync)
- **Unpackerr**: `/opt/frey/appdata/unpackerr/unpackerr.conf` (extraction settings)
- **Tdarr**: `/opt/frey/appdata/tdarr/configs/libraries.json` (initial library setup)

**Ansible Templates**:
- `roles/media/templates/recyclarr.yml.j2` - TRaSH guides configuration
- `roles/media/templates/unpackerr.conf.j2` - Archive extraction configuration
- `roles/media/templates/tdarr-libraries.json.j2` - Tdarr library initialization

**Deployment Tasks** (`roles/media/tasks/main.yml`):
1. Create service directories with proper permissions
2. Deploy configuration files from templates
3. Validate Docker Compose syntax
4. Start services with health checks
5. Trigger handlers for configuration changes

### Deployment

**Full Stack Deployment**:
```bash
# Deploy all media services including optimization tools
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

**Selective Deployment**:
```bash
# Deploy only the media stack
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags docker_compose_media

# Check what would change (dry run)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media --check --diff
```

**Configuration Updates**:
When you update configurations in `group_vars/all/main.yml`, simply re-run the playbook:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

Ansible will:
- Update configuration files from templates
- Restart affected services via handlers
- Maintain service availability during updates

## Post-Deployment Configuration

### 1. Add API Keys to Secrets Vault

The IaC setup requires API keys for *arr services to enable full automation.

**Step-by-step**:

1. **Get API keys** from each service:
   - Access web UI (e.g., `https://sonarr.frey`)
   - Navigate to Settings → General → Security
   - Copy the API Key

2. **Edit encrypted secrets file**:
   ```bash
   ansible-vault edit group_vars/all/secrets.yml --vault-password-file .vault_pass
   ```

3. **Add required keys** (see `docs/secrets.yml.example` for template):
   ```yaml
   # Media Stack API Keys
   sonarr_api_key: "your-sonarr-api-key-32-chars"
   radarr_api_key: "your-radarr-api-key-32-chars"
   lidarr_api_key: "your-lidarr-api-key-32-chars"
   ```

4. **Re-deploy to apply**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
   ```

**Required API Keys for Optimization Services**:
- `sonarr_api_key` - For Recyclarr and Unpackerr
- `radarr_api_key` - For Recyclarr and Unpackerr
- `lidarr_api_key` - For Unpackerr
- `audiobookshelf_api_token` - For audiobook-bridge (optional)

### 2. Configure Tdarr Workflows

1. Access `https://tdarr.frey`
2. Go to Libraries → Add Library
3. Add your media folders:
   - **Movies**: `/media/movies`
   - **TV Shows**: `/media/tv`
4. Configure transcoding settings:
   - Go to Plugins
   - Search for "Migz-Transcode using H265"
   - Configure quality and codec settings
5. Set up a schedule to avoid peak hours

### 3. Configure Umlautarr with Prowlarr

1. Access `https://prowlarr.frey`
2. For each indexer with foreign language content:
   - Edit indexer settings
   - Update the URL to proxy through Umlautarr
   - Test the indexer to ensure it works

### 4. Verify Recyclarr Configuration

Recyclarr is automatically configured via IaC templates! The configuration at `/opt/frey/appdata/recyclarr/recyclarr.yml` is deployed from `roles/media/templates/recyclarr.yml.j2`.

**Configuration includes**:
- TRaSH guides quality definitions for Sonarr and Radarr
- Custom formats for optimal release selection
- HD-1080p and UHD-4K quality profiles
- Automatic daily sync via cron

**Manual sync** (if needed):
```bash
docker exec recyclarr recyclarr sync
```

**View logs**:
```bash
docker logs recyclarr
```

**Customize** (optional):
If you need custom quality profiles, edit the template:
```bash
nano roles/media/templates/recyclarr.yml.j2
```
Then re-deploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

## Monitoring and Maintenance

### Check Service Status

```bash
# View all media services
docker compose -f /opt/frey/stacks/media/docker-compose.yml ps

# View logs for specific service
docker logs tdarr
docker logs umlautarr
docker logs recyclarr
docker logs unpackerr
```

### Tdarr Transcoding Progress

Monitor transcoding jobs:
1. Access `https://tdarr.frey`
2. Go to the "Processing" tab
3. View active, queued, and completed jobs

### Storage Savings

Check how much space Tdarr has saved:
1. Access `https://tdarr.frey`
2. Go to "Statistics" tab
3. View "Total Space Saved" metric

## Troubleshooting

### Tdarr Not Finding Media

**Issue**: Tdarr can't see media files

**Solution**:
1. Check volume mounts are correct in the docker-compose file
2. Verify permissions: `ls -la /opt/frey/media/`
3. Ensure media files are in the correct directories

### Umlautarr Not Working

**Issue**: Search results still have character issues

**Solution**:
1. Verify indexer URLs in Prowlarr point to Umlautarr
2. Check Umlautarr logs: `docker logs umlautarr`
3. Ensure the proxy URL format is correct: `http://umlautarr:3000/original-indexer-url`

### Recyclarr Sync Failing

**Issue**: Recyclarr fails to sync TRaSH guides

**Solution**:
1. Check API keys are correct in `recyclarr.yml`
2. Verify Sonarr/Radarr are accessible from the recyclarr container
3. Check logs: `docker logs recyclarr`
4. Manually test sync: `docker exec recyclarr recyclarr sync --debug`

### Unpackerr Not Extracting Archives

**Issue**: Downloaded archives aren't being extracted

**Solution**:
1. Verify API keys are set in secrets.yml and environment variables
2. Check Unpackerr logs: `docker logs unpackerr`
3. Ensure downloads folder is correctly mounted
4. Verify *arr apps are triggering download complete events

## Advanced Configuration

### Add More Tdarr Nodes

To add additional Tdarr nodes for distributed processing, duplicate the `tdarr_node` configuration in `group_vars/all/main.yml`:

```yaml
tdarr_node_3:
  enabled: true
  version: "latest"
  image: "ghcr.io/haveagitgat/tdarr_node"
  port: 0
  volumes:
    - "{{ storage.appdata_dir }}/tdarr/configs:/app/configs"
    - "{{ storage.appdata_dir }}/tdarr/logs:/app/logs"
    - "{{ media.dir }}:/media"
    - "{{ storage.base_dir }}/tdarr/transcode_cache:/temp"
  environment:
    - "serverIP=tdarr"
    - "serverPort={{ media.services.tdarr.server_port }}"
    - "nodeName=TdarrNode3"
    - "inContainer=true"
```

### Custom Recyclarr Schedules

Modify the sync schedule in `group_vars/all/main.yml`:

```yaml
recyclarr:
  environment:
    - "CRON_SCHEDULE=0 */6 * * *"  # Every 6 hours instead of daily
```

## Resources

- **Tdarr Documentation**: https://docs.tdarr.io/
- **Tdarr GitHub**: https://github.com/HaveAGitGat/Tdarr
- **Recyclarr Documentation**: https://recyclarr.dev/
- **TRaSH Guides**: https://trash-guides.info/
- **Unpackerr GitHub**: https://github.com/Unpackerr/unpackerr
- **Servarr Wiki**: https://wiki.servarr.com/

## Summary

These media optimization services work together to:

1. **Tdarr** - Reduces storage usage by transcoding to efficient codecs
2. **Umlautarr** - Ensures foreign language content is found correctly
3. **Recyclarr** - Maintains optimal quality profiles and naming conventions
4. **Unpackerr** - Streamlines downloads by auto-extracting archives

Combined, they create a highly automated and optimized media management system that saves space, improves quality, and reduces manual intervention.
