#!/bin/bash

# Script to create GitHub issues from TODO.md assessment
# Requires: GITHUB_TOKEN environment variable

set -e

REPO_OWNER="Jim8Knopf"
REPO_NAME="frey"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues"

# Check for GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    echo "Create a token at: https://github.com/settings/tokens"
    echo "Required scopes: repo"
    exit 1
fi

# Function to create an issue
create_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"

    echo "Creating issue: $title"

    # Convert comma-separated labels to JSON array
    IFS=',' read -ra LABEL_ARRAY <<< "$labels"
    LABEL_JSON="["
    for i in "${!LABEL_ARRAY[@]}"; do
        if [ $i -gt 0 ]; then
            LABEL_JSON+=","
        fi
        LABEL_JSON+="\"${LABEL_ARRAY[$i]}\""
    done
    LABEL_JSON+="]"

    # Create the issue
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"title\": \"$title\",
            \"body\": \"$body\",
            \"labels\": $LABEL_JSON
        }")

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "201" ]; then
        issue_number=$(echo "$response" | head -n-1 | jq -r '.number')
        echo "✓ Created issue #$issue_number"
    else
        echo "✗ Failed to create issue (HTTP $http_code)"
        echo "$response" | head -n-1 | jq -r '.message // .'
    fi

    # Rate limiting - be nice to GitHub API
    sleep 1
}

echo "Creating GitHub issues for Frey project..."
echo "Repository: ${REPO_OWNER}/${REPO_NAME}"
echo ""

# Issue #1: Create dedicated database role
create_issue \
    "Create dedicated database role for PostgreSQL lifecycle management" \
    "**Priority:** Critical

## Description
Create a separate \`db\` role to manage PostgreSQL independently from services, enabling proper database lifecycle management (start/stop/backup/update).

## Current State
- PostgreSQL is configured but database management is distributed across roles
- No centralized database schema management
- Backup exists but no structured restore process

## Acceptance Criteria
- [ ] Create \`roles/db/\` with complete role structure
- [ ] Implement tasks for starting/stopping PostgreSQL container
- [ ] Create tasks for creating schemas and users for each service (Jellyfin, Sonarr, Radarr, etc.)
- [ ] Implement backup and restore tasks
- [ ] Create separate playbook \`playbooks/db.yml\` for DB-specific operations
- [ ] Create playbook \`playbooks/db_backup.yml\` for automated backups with rotation
- [ ] Document PostgreSQL schema strategy (single instance with separate schemas)

## References
- TODO.md lines 14, 27-28, 79-90
- Current PostgreSQL config: \`group_vars/all/main.yml\` (postgres_version, db_type)" \
    "priority: critical,type: refactoring,component: database"

# Issue #2: Fix media UID inconsistency
create_issue \
    "Fix media user/group UID inconsistency" \
    "**Priority:** Critical

## Description
The media services currently use UID/GID 63342 instead of the planned UID/GID 1000. This creates permission inconsistencies and conflicts with the documented shared media user strategy.

## Current State
- Default user configured with UID 1000: \`users.default.uid: 1000\`
- Media role uses UID 63342: \`media.user.uid: 63342\`
- File management role references \`{{ media_user }}\` but inconsistently applied

## Acceptance Criteria
- [ ] Update media role to use UID/GID 1000
- [ ] Ensure all media services (Jellyfin, Sonarr, Radarr, Prowlarr, etc.) use shared \`media\` user
- [ ] Update Docker Compose templates to use consistent UID/GID
- [ ] Add task to set permissions for media directories: \`sudo chown -R media:media /path/to/media\`
- [ ] Add task to set directory mode: \`sudo chmod -R 775 /path/to/media\`
- [ ] Document migration path for existing installations

## References
- TODO.md lines 29-30, 126-149
- Current config: \`group_vars/all/main.yml\` (media.user.uid, users.default.uid)
- File: \`roles/file_management/tasks/main.yml\`" \
    "priority: critical,type: bug,component: media"

# Issue #3: Complete Traefik global SSO
create_issue \
    "Complete Traefik global SSO with ForwardAuth middleware" \
    "**Priority:** High

## Description
While Authentik SSO is implemented for individual services, there's no global Traefik ForwardAuth middleware to enforce authentication across all routes.

## Current State
- ✅ Authentik deployed and configured
- ✅ Per-service OIDC/LDAP integration (7 services)
- ❌ No global ForwardAuth middleware in Traefik
- ❌ No unified authentication enforcement

## Acceptance Criteria
- [ ] Configure Traefik ForwardAuth middleware in \`traefik.yml.j2\`
- [ ] Add authentication middleware to global entrypoints
- [ ] Create exemption list for services that should bypass SSO
- [ ] Test admin user access to all protected services
- [ ] Document SSO architecture and user management
- [ ] Add health check for Authentik integration

## Example Configuration
\`\`\`yaml
http:
  middlewares:
    auth:
      forwardAuth:
        address: \"http://authentik:9000/outpost.goauthentik.io/auth/traefik\"
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
\`\`\`

## References
- TODO.md lines 50-54, 98-122
- Current file: \`roles/infrastructure/templates/traefik.yml.j2\`
- Authentik blueprints: \`roles/infrastructure/templates/authentik-blueprints/\`" \
    "priority: high,type: enhancement,component: infrastructure,component: security"

# Issue #4: Refactor project structure
create_issue \
    "Refactor project structure - move Ansible files to subdirectory" \
    "**Priority:** High

## Description
Improve project maintainability and clarity by organizing Ansible-specific files under an \`ansible/\` subdirectory.

## Current State
- All Ansible files at project root: \`playbooks/\`, \`roles/\`, \`group_vars/\`, \`inventory/\`
- No \`ansible/\` subdirectory
- Mentioned in CLAUDE.md as planned enhancement

## Acceptance Criteria
- [ ] Create \`ansible/\` subdirectory
- [ ] Move \`playbooks/\`, \`roles/\`, \`group_vars/\`, \`inventory/\` under \`ansible/\`
- [ ] Update \`ansible.cfg\` paths accordingly
- [ ] Update all documentation (README.md, CLAUDE.md)
- [ ] Update any scripts that reference old paths
- [ ] Test deployment from new structure
- [ ] Update repository \`.gitignore\` if needed

## References
- TODO.md line 22
- CLAUDE.md mentions this as \"High Priority\"" \
    "priority: high,type: refactoring,component: project-structure"

# Issue #5: Move variables to role defaults
create_issue \
    "Move variables from group_vars to role defaults" \
    "**Priority:** High

## Description
The \`group_vars/all/main.yml\` file is currently 964 lines, containing variables that should be distributed to role-specific defaults for better modularity and maintainability.

## Current State
- \`group_vars/all/main.yml\`: 964 lines (very large)
- Only 9 of 12 roles have \`defaults/main.yml\` files
- Variables still centralized instead of role-scoped

## Acceptance Criteria
- [ ] Audit \`group_vars/all/main.yml\` and identify role-specific variables
- [ ] Create/update \`defaults/main.yml\` for all roles
- [ ] Move role-specific variables from group_vars to role defaults
- [ ] Keep only truly global variables in group_vars
- [ ] Ensure \`hash_behaviour = merge\` in ansible.cfg still works correctly
- [ ] Test all roles after migration
- [ ] Document variable precedence and scoping strategy

## Roles Missing defaults/main.yml
- bluetooth_audio
- file_management
- landing_page

## References
- TODO.md line 24
- Current file: \`group_vars/all/main.yml\` (964 lines)" \
    "priority: high,type: refactoring,component: configuration"

# Issue #6: Add health checks
create_issue \
    "Add comprehensive post-deployment health checks" \
    "**Priority:** High

## Description
Implement systematic health checks for all services to prevent silent failures after deployment.

## Current State
- Only Immich role has health check tag
- No comprehensive health check playbooks
- \`playbooks/site.yml\` has TODO comment for health checks

## Acceptance Criteria
- [ ] Create \`playbooks/health_check.yml\` playbook
- [ ] Add health check tasks to all service roles
- [ ] Implement checks for Docker containers, HTTP endpoints, database, Traefik routing, DNS, WiFi AP
- [ ] Add post-deployment health check execution to site.yml
- [ ] Create summary report of service health
- [ ] Add notification integration (ntfy) for failures
- [ ] Document health check procedures

## References
- TODO.md line 25
- Current implementation: \`roles/immich/tasks/main.yml\` (tags: health_check)" \
    "priority: high,type: enhancement,component: monitoring"

# Issue #7: Integrate Cockpit
create_issue \
    "Integrate Cockpit for web-based system management" \
    "**Priority:** Medium

## Description
Add Cockpit to provide a web-based management interface for the Raspberry Pi, making system administration more accessible.

## Acceptance Criteria
- [ ] Create feature toggle: \`features.cockpit: true\`
- [ ] Create role \`roles/cockpit/\` or add to system role
- [ ] Configure Cockpit installation and service
- [ ] Integrate with Traefik reverse proxy
- [ ] Add to DNS rewrites: \`cockpit.frey\`
- [ ] Configure firewall rules (port 9090)
- [ ] Optionally integrate with Authentik SSO
- [ ] Document Cockpit usage and features
- [ ] Add to README.md feature list

## Cockpit Features
- System monitoring (CPU, memory, disk)
- Service management (systemd)
- Container management
- Network configuration
- User management
- Terminal access

## References
- TODO.md line 38" \
    "priority: medium,type: feature,component: system"

# Issue #8: Implement ntfy notifications
create_issue \
    "Implement system notifications with ntfy" \
    "**Priority:** Medium

## Description
Implement ntfy integration to proactively monitor deployments, backups, and system health with push notifications.

## Acceptance Criteria
- [ ] Create feature toggle: \`features.ntfy: true\`
- [ ] Add ntfy service to infrastructure or monitoring stack
- [ ] Configure ntfy server or use hosted instance
- [ ] Create notification tasks for deployments, backups, health checks, system updates, certificate renewals
- [ ] Add ntfy configuration to group_vars
- [ ] Integrate with Traefik (ntfy.frey)
- [ ] Document notification setup and topics
- [ ] Add example notification handlers

## References
- TODO.md line 39
- Comment in: \`playbooks/site.yml\`" \
    "priority: medium,type: feature,component: monitoring"

# Issue #9: Add Tdarr
create_issue \
    "Add Tdarr for media library optimization" \
    "**Priority:** Medium

## Description
Integrate Tdarr to save storage space and standardize media formats through automated transcoding.

## Acceptance Criteria
- [ ] Add Tdarr to media stack configuration
- [ ] Configure service in \`media.services.tdarr\`
- [ ] Update \`docker-compose-media.yml.j2\` template
- [ ] Configure volumes for configs, media, and temp files
- [ ] Integrate with media user/group (UID 1000)
- [ ] Configure Traefik labels (tdarr.frey)
- [ ] Add DNS rewrite entry
- [ ] Configure GPU transcoding if available
- [ ] Document Tdarr setup and transcoding profiles
- [ ] Add to README.md

## Tdarr Ports
- Web UI: 8265
- Server: 8266

## References
- TODO.md line 40" \
    "priority: medium,type: feature,component: media"

# Issue #10: Add Tube-Archivist
create_issue \
    "Add Tube-Archivist for YouTube archival" \
    "**Priority:** Medium

## Description
Integrate Tube-Archivist to enable local backup of important YouTube channels and videos.

## Acceptance Criteria
- [ ] Add Tube-Archivist to media stack configuration
- [ ] Configure service in \`media.services.tubearchivist\`
- [ ] Update \`docker-compose-media.yml.j2\` template
- [ ] Configure dependencies: Elasticsearch backend, Redis cache
- [ ] Configure volumes for cache and YouTube media
- [ ] Integrate with media user/group
- [ ] Configure Traefik labels
- [ ] Add DNS rewrite entry
- [ ] Configure backup inclusion for archive metadata
- [ ] Document channel subscription and download management
- [ ] Add to README.md

## References
- TODO.md line 41" \
    "priority: medium,type: feature,component: media"

# Issue #11: Document backup/restore
create_issue \
    "Document and test backup/restore strategy" \
    "**Priority:** Medium

## Description
While backup infrastructure exists, comprehensive restore testing and documentation is needed to ensure backups are functional and usable.

## Current State
- ✅ Backup role exists
- ✅ Backup script template
- ✅ Cron job scheduled
- ❌ Restore procedures not documented
- ❌ No restore testing validation

## Acceptance Criteria
- [ ] Document backup strategy and schedule
- [ ] Create restore playbook: \`playbooks/restore.yml\`
- [ ] Document restore procedures for Docker volumes, PostgreSQL databases, config files, media libraries
- [ ] Create test restore procedure
- [ ] Validate backup integrity checks
- [ ] Document disaster recovery scenarios
- [ ] Add backup verification to health checks
- [ ] Document off-site backup strategy
- [ ] Add restore testing to regular maintenance

## References
- TODO.md line 42
- Current backup role: \`roles/backup/\`" \
    "priority: medium,type: documentation,type: testing,component: backup"

# Issue #12: Simplify network architecture
create_issue \
    "Simplify network architecture" \
    "**Priority:** Low

## Description
The current network architecture uses multiple isolated Docker networks which may be more complex than necessary. Evaluate and potentially simplify the network design.

## Current State
Multiple Docker networks: proxy, localdns, media_network (10.20.7.0/24), infrastructure_network (10.20.3.0/24), WiFi AP (10.20.0.0/24)

## Considerations
- Network isolation provides security benefits
- Complexity acknowledged in TODO.md
- Current design is intentional but could be streamlined

## Acceptance Criteria
- [ ] Document current network architecture and rationale
- [ ] Identify opportunities for consolidation
- [ ] Evaluate security implications of simplification
- [ ] Design simplified network architecture
- [ ] Create migration plan
- [ ] Test network changes in staging
- [ ] Update documentation
- [ ] Implement network simplification
- [ ] Verify service connectivity post-migration

## References
- TODO.md line 65" \
    "priority: low,type: refactoring,component: network"

# Issue #13: Add input validation
create_issue \
    "Add comprehensive input validation" \
    "**Priority:** Low

## Description
Extend input validation beyond critical roles (WiFi, Bluetooth) to prevent misconfigurations and errors across all roles.

## Current State
- ✅ Validation in: bluetooth_audio, wifi_access_point
- ✅ 5+ test/verify playbooks
- ❌ Not comprehensive across all roles

## Acceptance Criteria
- [ ] Audit all roles for required variables
- [ ] Add \`ansible.builtin.assert\` tasks for variable validation
- [ ] Create shared validation tasks
- [ ] Add pre-deployment validation playbook
- [ ] Validate UID/GID ranges, network configs, port conflicts, directory permissions, service dependencies
- [ ] Document validation patterns
- [ ] Add validation to CI/CD if applicable

## References
- TODO.md line 63" \
    "priority: low,type: enhancement,component: validation"

# Issue #14: Add Umlautarr
create_issue \
    "Add Umlautarr for enhanced media library management" \
    "**Priority:** Future

## Description
Consider adding Umlautarr to improve media library management capabilities.

**Note:** This is a long-term idea from the \"Maybe/Someday\" section. Create this issue for tracking but prioritize other work first.

## References
- TODO.md line 73" \
    "priority: low,type: feature,component: media,status: future"

# Issue #15: Automated testing
create_issue \
    "Implement automated testing framework" \
    "**Priority:** Future

## Description
Add automated testing to ensure reliability and catch issues early in the development process.

## Potential Scope
- Ansible playbook syntax validation
- Docker Compose file validation
- Integration tests for service deployment
- End-to-end tests for service accessibility
- Network configuration tests
- Backup/restore validation tests

## References
- TODO.md line 74" \
    "priority: low,type: enhancement,component: testing,status: future"

# Issue #16: Service monitoring
create_issue \
    "Add service monitoring and alerting" \
    "**Priority:** Future

## Description
While Prometheus and Grafana are deployed, add comprehensive service monitoring to proactively detect and resolve issues.

## Potential Scope
- Service health metrics
- Container resource usage
- Disk space monitoring
- Network bandwidth monitoring
- Certificate expiration alerts
- Backup success/failure alerts
- Integration with ntfy for notifications

**Note:** Some functionality may overlap with Issue #8 (ntfy) and should be coordinated.

## References
- TODO.md line 75" \
    "priority: low,type: feature,component: monitoring,status: future"

echo ""
echo "✓ All issues created successfully!"
echo ""
echo "View issues at: https://github.com/${REPO_OWNER}/${REPO_NAME}/issues"
