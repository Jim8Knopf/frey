# Input Validation System

## Overview

The Frey project now includes a comprehensive input validation system that checks configuration before deployment to prevent misconfigurations and errors.

## What Was Added

### New Validation Role (`roles/validation/`)

A new Ansible role has been created that performs validation checks across all aspects of the Frey configuration:

#### 1. Network Configuration Validation (`tasks/network.yml`)
- **WiFi AP Configuration**:
  - Interface name validation
  - CIDR subnet format validation
  - IP address format validation
  - DHCP range validation
  - SSID length validation (1-32 characters)
  - WPA2 password requirements (8-63 characters)
  - Hardware mode validation (a/b/g/auto)
- **Subnet Overlap Detection**:
  - **CRITICAL**: Prevents WiFi AP and media network subnet conflicts
  - Compares network prefixes to detect overlapping subnets
- **Domain and Timezone**: Basic format validation

#### 2. Port Conflict Detection (`tasks/ports.yml`)
- **Comprehensive Port Collection**: Gathers ports from all enabled services:
  - Infrastructure services (Traefik, Portainer, Dockge)
  - Media services (Jellyfin, *arr stack, qBittorrent, NZBGet)
  - Monitoring services (Grafana, Prometheus, Loki)
  - Automation services (Ollama, Open WebUI, n8n)
  - Landing page
- **Duplicate Detection**: Identifies port conflicts before deployment
- **Firewall Port Validation**: Ensures ports are in valid range (1-65535)

#### 3. Feature Dependency Validation (`tasks/features.yml`)
- **Boolean Type Validation**: Ensures all feature flags are boolean values
- **Dependency Checks**:
  - Landing page requires infrastructure (Traefik)
  - *arr services need at least one download client
  - Grafana requires data sources (Prometheus or Loki)
  - Open WebUI requires Ollama
  - WiFi AP configuration completeness
- **Recommendations**: Warns about best practices (e.g., Prowlarr for multiple *arr services)

#### 4. Storage Path Validation (`tasks/storage.yml`)
- **Absolute Path Validation**: Ensures all paths start with `/`
- **No Relative Paths**: Prevents `./directory` patterns
- **Path Checks**:
  - Base directory
  - Appdata directory
  - Stacks directory
  - Media type directories
  - Monitoring data directories
  - Automation service directories
- **Storage Recommendations**: Warns about space requirements

#### 5. Secrets and Credentials Validation (`tasks/secrets.yml`)
- **Password Strength**:
  - WiFi password WPA2 compliance (8-63 characters)
  - qBittorrent password minimum length (6+ characters)
  - Grafana admin password security (8+ characters)
  - n8n encryption key length (32+ characters)
- **Default Password Detection**:
  - **CRITICAL**: Fails if Grafana admin password is 'admin'
  - Warns about qBittorrent default credentials
- **Common Weak Passwords**: Checks against list of common weak passwords
- **Security Best Practices**: Reminds about proper credential management

#### 6. User/Group ID Validation (`tasks/users.yml`)
- **UID/GID Range Validation**: Ensures IDs are in valid range (1000-65533)
- **Uniqueness Checks**:
  - Detects duplicate UIDs across all stacks
  - Detects duplicate GIDs across all stacks
- **Naming Convention Validation**:
  - Username follows Linux conventions
  - Group name follows Linux conventions
  - Maximum 32 characters
- **Configuration Summary**: Displays all user/group mappings

### Integration with Main Playbook

The validation role has been integrated into `playbooks/site.yml` as the **first role** to execute, ensuring all configuration is validated before any deployment actions occur.

#### Tags
- `validation` - Run all validation checks
- `always` - Validation runs by default with any deployment
- Can be combined with specific tags: `validation,network`, `validation,ports`, etc.

#### Usage Examples

```bash
# Run only validation (no deployment)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags validation

# Run specific validation category
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "validation,network"

# Skip validation (NOT RECOMMENDED)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags validation

# Normal deployment (includes validation automatically)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

## Critical Issues Prevented

### 1. Network Subnet Overlap ⚠️ CRITICAL
**Before**: WiFi AP subnet (10.20.0.0/24) and media network subnet (10.20.0.0/24) could overlap, causing routing conflicts.

**Now**: Validation detects overlap and fails with clear error message explaining the issue.

### 2. Port Conflicts ⚠️ HIGH
**Before**: Multiple services could be configured with the same port, causing deployment failures.

**Now**: All ports are collected and checked for duplicates before deployment.

### 3. Missing Dependencies ⚠️ HIGH
**Before**: Landing page could be enabled without Traefik, causing routing failures.

**Now**: Dependency checks ensure required services are enabled.

### 4. UID/GID Conflicts ⚠️ MEDIUM
**Before**: Duplicate user/group IDs could cause file permission issues.

**Now**: Uniqueness validation prevents UID/GID conflicts.

### 5. Weak Credentials ⚠️ SECURITY
**Before**: Default or weak passwords could be used in production.

**Now**: Password strength validation and default password detection.

### 6. Invalid Paths ⚠️ MEDIUM
**Before**: Relative paths like `./config` could cause container mount failures.

**Now**: Path validation ensures all paths are absolute.

## Configuration Options

Default variables in `roles/validation/defaults/main.yml`:

```yaml
# Common weak passwords to check against
validation_common_weak_passwords:
  - "password"
  - "12345678"
  - "password123"
  # ... more weak passwords

# Validation settings
validation_strict_mode: false  # Set to true to fail on warnings
validation_skip_secrets: false  # Set to true to skip secrets validation (not recommended)
```

## Validation Output Examples

### Success
```
TASK [validation : Display validation start message]
ok: [frey] =>
  msg: Starting Frey configuration validation...

TASK [validation : Validate WiFi AP subnet is in valid CIDR format]
ok: [frey] =>
  msg: ✓ WiFi AP subnet format is valid: 10.20.0.0/24

TASK [validation : Assert no port conflicts exist]
ok: [frey] =>
  msg: ✓ No port conflicts detected among 15 configured services

TASK [validation : Display validation success message]
ok: [frey] =>
  msg: ✓ All configuration validations passed successfully!
```

### Failure (Port Conflict)
```
TASK [validation : Assert no port conflicts exist]
fatal: [frey]: FAILED! =>
  msg: |
    PORT CONFLICT DETECTED!
    The following services are configured to use the same port(s):
    Port 8080:
      - open-webui
      - qbittorrent
    Please reconfigure the services to use unique ports.
```

### Failure (Subnet Overlap)
```
TASK [validation : Warn if WiFi and media subnets overlap]
fatal: [frey]: FAILED! =>
  msg: |
    CRITICAL: Network subnet overlap detected!
    WiFi AP subnet: 10.20.0.0/24
    Media network subnet: 10.20.0.0/24
    These subnets must not overlap to prevent routing conflicts.
```

## Benefits

1. **Early Error Detection**: Catches configuration errors before any deployment actions
2. **Clear Error Messages**: Provides actionable feedback on how to fix issues
3. **Prevents Downtime**: Stops problematic deployments before they cause service outages
4. **Security Improvements**: Enforces password strength and credential best practices
5. **Documentation**: Self-documenting through validation checks
6. **Confidence**: Gives operators confidence that configuration is correct

## Future Enhancements

Potential additions to the validation system:

1. **Docker Image Availability**: Verify images exist before pulling
2. **IANA Timezone Validation**: Check timezone against official IANA database
3. **DNS Resolution Tests**: Verify domain configuration
4. **Resource Limits**: Validate memory/CPU constraints
5. **Post-Deployment Health Checks**: Verify services started correctly
6. **Configuration Schema Validation**: JSON Schema validation for complex configs

## Files Added

```
roles/validation/
├── tasks/
│   ├── main.yml          # Main entry point, includes all validation tasks
│   ├── network.yml       # Network configuration validation
│   ├── ports.yml         # Port conflict detection
│   ├── features.yml      # Feature dependency validation
│   ├── storage.yml       # Storage path validation
│   ├── secrets.yml       # Credentials and secrets validation
│   └── users.yml         # User/group ID validation
├── defaults/
│   └── main.yml          # Default variables (weak passwords list, settings)
└── README.md             # Comprehensive documentation

playbooks/site.yml         # Modified to include validation role
docs/INPUT_VALIDATION.md   # This document
```

## Maintenance

When adding new features to Frey:

1. Add corresponding validation checks to appropriate task file
2. Test with both valid and invalid configurations
3. Update validation README with new validation descriptions
4. Include clear error messages in assertions
5. Document any new configuration requirements

## References

- Main Documentation: `roles/validation/README.md`
- Ansible Assert Module: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/assert_module.html
- CLAUDE.md: Project overview and development workflow
- TODO.md: Planned enhancements including validation expansion
