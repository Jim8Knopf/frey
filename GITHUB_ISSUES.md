# GitHub Issues Generated from TODO.md

**Assessment Date:** 2025-11-16
**Overall Completion:** 57% of TODO items completed

This document contains GitHub issues that should be created based on the TODO.md assessment. Issues are organized by priority and category.

---

## 🔴 Critical Priority

### Issue #1: Create dedicated database role for PostgreSQL lifecycle management

**Labels:** `priority: critical`, `type: refactoring`, `component: database`

**Description:**
Create a separate `db` role to manage PostgreSQL independently from services, enabling proper database lifecycle management (start/stop/backup/update).

**Current State:**
- PostgreSQL is configured but database management is distributed across roles
- No centralized database schema management
- Backup exists but no structured restore process

**Acceptance Criteria:**
- [ ] Create `roles/db/` with complete role structure
- [ ] Implement tasks for starting/stopping PostgreSQL container
- [ ] Create tasks for creating schemas and users for each service (Jellyfin, Sonarr, Radarr, etc.)
- [ ] Implement backup and restore tasks
- [ ] Create separate playbook `playbooks/db.yml` for DB-specific operations
- [ ] Create playbook `playbooks/db_backup.yml` for automated backups with rotation
- [ ] Document PostgreSQL schema strategy (single instance with separate schemas)

**References:**
- TODO.md lines 14, 27-28, 79-90
- Current PostgreSQL config: `group_vars/all/main.yml` (postgres_version, db_type)

---

### Issue #2: Fix media user/group UID inconsistency

**Labels:** `priority: critical`, `type: bug`, `component: media`

**Description:**
The media services currently use UID/GID 63342 instead of the planned UID/GID 1000. This creates permission inconsistencies and conflicts with the documented shared media user strategy.

**Current State:**
- Default user configured with UID 1000: `users.default.uid: 1000`
- Media role uses UID 63342: `media.user.uid: 63342`
- File management role references `{{ media_user }}` but inconsistently applied

**Acceptance Criteria:**
- [ ] Update media role to use UID/GID 1000
- [ ] Ensure all media services (Jellyfin, Sonarr, Radarr, Prowlarr, etc.) use shared `media` user
- [ ] Update Docker Compose templates to use consistent UID/GID
- [ ] Add task to set permissions for media directories: `sudo chown -R media:media /path/to/media`
- [ ] Add task to set directory mode: `sudo chmod -R 775 /path/to/media`
- [ ] Document migration path for existing installations

**References:**
- TODO.md lines 29-30, 126-149
- Current config: `group_vars/all/main.yml` (media.user.uid, users.default.uid)
- File: `roles/file_management/tasks/main.yml`

---

## 🟡 High Priority

### Issue #3: Complete Traefik global SSO with ForwardAuth middleware

**Labels:** `priority: high`, `type: enhancement`, `component: infrastructure`, `component: security`

**Description:**
While Authentik SSO is implemented for individual services, there's no global Traefik ForwardAuth middleware to enforce authentication across all routes.

**Current State:**
- ✅ Authentik deployed and configured
- ✅ Per-service OIDC/LDAP integration (7 services)
- ❌ No global ForwardAuth middleware in Traefik
- ❌ No unified authentication enforcement

**Acceptance Criteria:**
- [ ] Configure Traefik ForwardAuth middleware in `traefik.yml.j2`
- [ ] Add authentication middleware to global entrypoints
- [ ] Create exemption list for services that should bypass SSO
- [ ] Test admin user access to all protected services
- [ ] Document SSO architecture and user management
- [ ] Add health check for Authentik integration

**Example Configuration:**
```yaml
http:
  middlewares:
    auth:
      forwardAuth:
        address: "http://authentik:9000/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
```

**References:**
- TODO.md lines 50-54, 98-122
- Current file: `roles/infrastructure/templates/traefik.yml.j2`
- Authentik blueprints: `roles/infrastructure/templates/authentik-blueprints/`

---

### Issue #4: Refactor project structure - move Ansible files to subdirectory

**Labels:** `priority: high`, `type: refactoring`, `component: project-structure`

**Description:**
Improve project maintainability and clarity by organizing Ansible-specific files under an `ansible/` subdirectory.

**Current State:**
- All Ansible files at project root: `playbooks/`, `roles/`, `group_vars/`, `inventory/`
- No `ansible/` subdirectory
- Mentioned in CLAUDE.md as planned enhancement

**Acceptance Criteria:**
- [ ] Create `ansible/` subdirectory
- [ ] Move `playbooks/`, `roles/`, `group_vars/`, `inventory/` under `ansible/`
- [ ] Update `ansible.cfg` paths accordingly
- [ ] Update all documentation (README.md, CLAUDE.md)
- [ ] Update any scripts that reference old paths
- [ ] Test deployment from new structure
- [ ] Update repository `.gitignore` if needed

**Migration Path:**
```
Before:
/frey/
├── playbooks/
├── roles/
├── group_vars/
└── inventory/

After:
/frey/
├── ansible/
│   ├── playbooks/
│   ├── roles/
│   ├── group_vars/
│   └── inventory/
└── ansible.cfg (updated)
```

**References:**
- TODO.md line 22
- CLAUDE.md mentions this as "High Priority"
- Current ansible.cfg location: `/home/user/frey/ansible.cfg`

---

### Issue #5: Move variables from group_vars to role defaults

**Labels:** `priority: high`, `type: refactoring`, `component: configuration`

**Description:**
The `group_vars/all/main.yml` file is currently 964 lines, containing variables that should be distributed to role-specific defaults for better modularity and maintainability.

**Current State:**
- `group_vars/all/main.yml`: 964 lines (very large)
- Only 9 of 12 roles have `defaults/main.yml` files
- Variables still centralized instead of role-scoped

**Acceptance Criteria:**
- [ ] Audit `group_vars/all/main.yml` and identify role-specific variables
- [ ] Create/update `defaults/main.yml` for all roles
- [ ] Move role-specific variables from group_vars to role defaults
- [ ] Keep only truly global variables in group_vars
- [ ] Ensure `hash_behaviour = merge` in ansible.cfg still works correctly
- [ ] Test all roles after migration
- [ ] Document variable precedence and scoping strategy

**Roles Missing defaults/main.yml:**
- bluetooth_audio
- file_management
- landing_page

**References:**
- TODO.md line 24
- Current file: `group_vars/all/main.yml` (964 lines)
- Ansible.cfg setting: `hash_behaviour = merge`

---

### Issue #6: Add comprehensive post-deployment health checks

**Labels:** `priority: high`, `type: enhancement`, `component: monitoring`

**Description:**
Implement systematic health checks for all services to prevent silent failures after deployment.

**Current State:**
- Only Immich role has health check tag
- No comprehensive health check playbooks
- `playbooks/site.yml` has TODO comment for health checks

**Acceptance Criteria:**
- [ ] Create `playbooks/health_check.yml` playbook
- [ ] Add health check tasks to all service roles
- [ ] Implement checks for:
  - Docker container status
  - Service HTTP endpoints
  - Database connectivity
  - Traefik routing
  - DNS resolution
  - WiFi AP status
- [ ] Add post-deployment health check execution to site.yml
- [ ] Create summary report of service health
- [ ] Add notification integration (ntfy) for failures
- [ ] Document health check procedures

**Health Check Examples:**
```yaml
- name: Check Jellyfin accessibility
  uri:
    url: "http://jellyfin.frey:8096"
    status_code: 200

- name: Verify Traefik routing
  command: docker exec traefik wget -O- http://localhost:8082/api/http/routers
```

**References:**
- TODO.md line 25
- Current implementation: `roles/immich/tasks/main.yml` (tags: health_check)
- Playbook: `playbooks/site.yml`

---

## 🟢 Medium Priority

### Issue #7: Integrate Cockpit for web-based system management

**Labels:** `priority: medium`, `type: feature`, `component: system`

**Description:**
Add Cockpit to provide a web-based management interface for the Raspberry Pi, making system administration more accessible.

**Current State:**
- Not implemented
- Only mentioned in TODO.md and CLAUDE.md

**Acceptance Criteria:**
- [ ] Create feature toggle: `features.cockpit: true`
- [ ] Create role `roles/cockpit/` or add to system role
- [ ] Configure Cockpit installation and service
- [ ] Integrate with Traefik reverse proxy
- [ ] Add to DNS rewrites: `cockpit.frey`
- [ ] Configure firewall rules (port 9090)
- [ ] Optionally integrate with Authentik SSO
- [ ] Document Cockpit usage and features
- [ ] Add to README.md feature list

**Cockpit Features:**
- System monitoring (CPU, memory, disk)
- Service management (systemd)
- Container management (Podman/Docker)
- Network configuration
- User management
- Terminal access

**References:**
- TODO.md line 38
- CLAUDE.md mentions as "possible enhancement"

---

### Issue #8: Implement system notifications with ntfy

**Labels:** `priority: medium`, `type: feature`, `component: monitoring`

**Description:**
Implement ntfy integration to proactively monitor deployments, backups, and system health with push notifications.

**Current State:**
- Not implemented
- Commented reference in `playbooks/site.yml`

**Acceptance Criteria:**
- [ ] Create feature toggle: `features.ntfy: true`
- [ ] Add ntfy service to infrastructure or monitoring stack
- [ ] Configure ntfy server or use hosted instance
- [ ] Create notification tasks for:
  - Deployment start/completion/failure
  - Backup success/failure
  - Health check failures
  - System updates
  - Certificate renewals
- [ ] Add ntfy configuration to group_vars
- [ ] Integrate with Traefik (ntfy.frey)
- [ ] Document notification setup and topics
- [ ] Add example notification handlers

**Integration Points:**
```yaml
- name: Send deployment notification
  uri:
    url: "http://ntfy.frey/frey-deployments"
    method: POST
    body: "Deployment completed successfully"
```

**References:**
- TODO.md line 39
- Comment in: `playbooks/site.yml`

---

### Issue #9: Add Tdarr for media library optimization

**Labels:** `priority: medium`, `type: feature`, `component: media`

**Description:**
Integrate Tdarr to save storage space and standardize media formats through automated transcoding.

**Current State:**
- Not implemented
- Only mentioned in TODO.md

**Acceptance Criteria:**
- [ ] Add Tdarr to media stack configuration
- [ ] Configure service in `media.services.tdarr`
- [ ] Update `docker-compose-media.yml.j2` template
- [ ] Configure volumes:
  - `/opt/frey/appdata/tdarr:/app/configs`
  - `/opt/frey/media:/media`
  - `/opt/frey/downloads/tdarr-temp:/temp`
- [ ] Integrate with media user/group (UID 1000)
- [ ] Configure Traefik labels (tdarr.frey)
- [ ] Add DNS rewrite entry
- [ ] Configure GPU transcoding if available
- [ ] Document Tdarr setup and transcoding profiles
- [ ] Add to README.md

**Tdarr Ports:**
- Web UI: 8265
- Server: 8266

**References:**
- TODO.md line 40
- CLAUDE.md mentions as "possible enhancement"

---

### Issue #10: Add Tube-Archivist for YouTube archival

**Labels:** `priority: medium`, `type: feature`, `component: media`

**Description:**
Integrate Tube-Archivist to enable local backup of important YouTube channels and videos.

**Current State:**
- Not implemented
- Only mentioned in TODO.md

**Acceptance Criteria:**
- [ ] Add Tube-Archivist to media stack configuration
- [ ] Configure service in `media.services.tubearchivist`
- [ ] Update `docker-compose-media.yml.j2` template
- [ ] Configure dependencies:
  - Elasticsearch backend
  - Redis cache
- [ ] Configure volumes:
  - `/opt/frey/appdata/tubearchivist:/cache`
  - `/opt/frey/media/youtube:/youtube`
- [ ] Integrate with media user/group
- [ ] Configure Traefik labels
- [ ] Add DNS rewrite entry
- [ ] Configure backup inclusion for archive metadata
- [ ] Document channel subscription and download management
- [ ] Add to README.md

**Tube-Archivist Components:**
- Main app: Port 8000
- Elasticsearch: Port 9200
- Redis: Port 6379

**References:**
- TODO.md line 41
- CLAUDE.md mentions as "possible enhancement"

---

### Issue #11: Document and test backup/restore strategy

**Labels:** `priority: medium`, `type: documentation`, `type: testing`, `component: backup`

**Description:**
While backup infrastructure exists, comprehensive restore testing and documentation is needed to ensure backups are functional and usable.

**Current State:**
- ✅ Backup role exists: `roles/backup/`
- ✅ Backup script template: `backup.sh.j2`
- ✅ Cron job scheduled
- ❌ Restore procedures not documented
- ❌ No restore testing validation

**Acceptance Criteria:**
- [ ] Document backup strategy and schedule
- [ ] Create restore playbook: `playbooks/restore.yml`
- [ ] Document restore procedures for each service type:
  - Docker volumes
  - PostgreSQL databases
  - Configuration files
  - Media libraries
- [ ] Create test restore procedure
- [ ] Validate backup integrity checks
- [ ] Document disaster recovery scenarios
- [ ] Add backup verification to health checks
- [ ] Document off-site backup strategy
- [ ] Add restore testing to regular maintenance

**Documentation Needed:**
- Backup locations and retention
- Service-specific restore procedures
- Point-in-time recovery
- Disaster recovery runbook

**References:**
- TODO.md line 42
- Current backup role: `roles/backup/tasks/main.yml`
- Backup script: `roles/backup/templates/backup.sh.j2`

---

## 🔵 Low Priority

### Issue #12: Simplify network architecture

**Labels:** `priority: low`, `type: refactoring`, `component: network`

**Description:**
The current network architecture uses multiple isolated Docker networks which may be more complex than necessary. Evaluate and potentially simplify the network design.

**Current State:**
- Multiple Docker networks:
  - `proxy` - Traefik reverse proxy (infrastructure)
  - `localdns` - DNS resolution
  - `media_network` - Media services (10.20.7.0/24)
  - `infrastructure_network` - Infrastructure (10.20.3.0/24)
  - WiFi AP network - (10.20.0.0/24)

**Considerations:**
- Network isolation provides security benefits
- Complexity acknowledged in TODO.md
- Current design is intentional but could be streamlined

**Acceptance Criteria:**
- [ ] Document current network architecture and rationale
- [ ] Identify opportunities for consolidation
- [ ] Evaluate security implications of simplification
- [ ] Design simplified network architecture
- [ ] Create migration plan
- [ ] Test network changes in staging
- [ ] Update documentation
- [ ] Implement network simplification
- [ ] Verify service connectivity post-migration

**References:**
- TODO.md line 65
- CLAUDE.md: "Network Architecture Complexity" section
- Network configs: `group_vars/all/main.yml`

---

### Issue #13: Add comprehensive input validation

**Labels:** `priority: low`, `type: enhancement`, `component: validation`

**Description:**
Extend input validation beyond critical roles (WiFi, Bluetooth) to prevent misconfigurations and errors across all roles.

**Current State:**
- ✅ Validation in: `bluetooth_audio`, `wifi_access_point`
- ✅ 5+ test/verify playbooks
- ❌ Not comprehensive across all roles

**Acceptance Criteria:**
- [ ] Audit all roles for required variables
- [ ] Add `ansible.builtin.assert` tasks for:
  - Required variables exist
  - Variables are correct type
  - Values are in acceptable ranges
  - File paths exist
  - Port numbers are valid
- [ ] Create shared validation tasks
- [ ] Add pre-deployment validation playbook
- [ ] Validate:
  - UID/GID ranges
  - Network configurations
  - Port conflicts
  - Directory permissions
  - Service dependencies
- [ ] Document validation patterns
- [ ] Add validation to CI/CD if applicable

**Validation Examples:**
```yaml
- name: Validate media UID
  assert:
    that:
      - media.user.uid is defined
      - media.user.uid >= 1000
      - media.user.uid < 65534
```

**References:**
- TODO.md line 63
- Current validation: `roles/bluetooth_audio/tasks/main.yml`
- WiFi validation: `roles/wifi_access_point/`

---

## 💡 Long-Term / Future Enhancements

### Issue #14: Add Umlautarr for enhanced media library management

**Labels:** `priority: low`, `type: feature`, `component: media`, `status: future`

**Description:**
Consider adding Umlautarr to improve media library management capabilities.

**Note:** This is a long-term idea from the "Maybe/Someday" section. Create this issue for tracking but prioritize other work first.

**References:**
- TODO.md line 73

---

### Issue #15: Implement automated testing framework

**Labels:** `priority: low`, `type: enhancement`, `component: testing`, `status: future`

**Description:**
Add automated testing to ensure reliability and catch issues early in the development process.

**Potential Scope:**
- Ansible playbook syntax validation
- Docker Compose file validation
- Integration tests for service deployment
- End-to-end tests for service accessibility
- Network configuration tests
- Backup/restore validation tests

**References:**
- TODO.md line 74

---

### Issue #16: Add service monitoring and alerting

**Labels:** `priority: low`, `type: feature`, `component: monitoring`, `status: future`

**Description:**
While Prometheus and Grafana are deployed, add comprehensive service monitoring to proactively detect and resolve issues.

**Potential Scope:**
- Service health metrics
- Container resource usage
- Disk space monitoring
- Network bandwidth monitoring
- Certificate expiration alerts
- Backup success/failure alerts
- Integration with ntfy for notifications

**Note:** Some functionality may overlap with Issue #8 (ntfy) and should be coordinated.

**References:**
- TODO.md line 75

---

## 📊 Summary

**Total Issues:** 16

**By Priority:**
- 🔴 Critical: 2 issues
- 🟡 High: 4 issues
- 🟢 Medium: 5 issues
- 🔵 Low: 2 issues
- 💡 Future: 3 issues

**By Category:**
- Security/Database: 2 issues
- Refactoring: 3 issues
- Features: 6 issues
- Documentation/Testing: 2 issues
- Monitoring: 2 issues
- Future/Long-term: 3 issues

**Quick Wins (Easy Impact):**
1. Issue #2: Fix media UID inconsistency (configuration change)
2. Issue #13: Add input validation (incremental improvement)
3. Issue #11: Document backup/restore (documentation)

**High Impact:**
1. Issue #1: Database role (infrastructure improvement)
2. Issue #3: Global SSO with ForwardAuth (security enhancement)
3. Issue #6: Comprehensive health checks (reliability)

---

## 📝 Notes

- All issues reference specific files and line numbers from the codebase
- Issues include acceptance criteria and implementation guidance
- Cross-references between related issues are noted
- Assessment based on codebase analysis performed 2025-11-16
- Some issues may have dependencies on others (noted in descriptions)
