# Validation Role

## Purpose

The validation role performs comprehensive input validation and configuration checks before deploying the Frey stack. It catches misconfigurations early, preventing deployment failures and providing clear error messages to guide fixes.

## What It Validates

### 1. Core Variables (`validate_variables.yml`)
- **Storage configuration**: Ensures `storage.base_dir`, `appdata_dir`, `stacks`, and `media_dir` are defined
- **Path format**: Validates all storage paths are absolute (start with `/`)
- **Network domain**: Checks `network.domain_name` is defined and valid
- **Feature flags**: Validates all feature flags are boolean values
- **User/group config**: Ensures user/group configuration is complete for enabled stacks

### 2. Network Configuration (`validate_network.yml`)
*Only runs when `features.wifi_access_point` is enabled*

- **WiFi variables**: Validates interface, SSID, password, IP, DHCP range, country code
- **Interface format**: Checks WiFi interface name matches expected pattern (wlan0, wlan1, etc.)
- **SSID length**: Ensures SSID is 1-32 characters
- **Password strength**: Validates WiFi password is 8-63 characters
- **Country code**: Checks format is 2-letter uppercase (US, GB, DE, etc.)
- **IP address format**: Validates IP addresses use correct dotted-quad notation
- **DHCP range**:
  - Ensures DHCP range is in same subnet as WiFi IP
  - Validates start address < end address
  - Checks gateway IP is outside DHCP range
- **DNS rewrites**: Validates DNS rewrite entries have valid names

### 3. Storage Paths (`validate_storage.yml`)
- **Base directory**: Checks if base directory exists, or parent directory is writable
- **Disk space**: Warns if less than 10GB available (configurable via `validation_min_disk_space_gb`)
- **Path hierarchy**: Validates appdata and stacks directories are under base_dir
- **Media configuration**: Checks media directory configuration when media feature is enabled
- **Path safety**: Ensures paths don't contain dangerous characters (;&|`$)

### 4. Port Assignments (`validate_ports.yml`)
- **Port collection**: Gathers all port assignments from enabled services
- **Duplicate detection**: Identifies port conflicts between services
- **Valid range**: Ensures all ports are 1-65535
- **Privileged ports**: Warns about ports <1024 that require special permissions
- **Firewall config**: Validates security.firewall_tcp_ports when security feature is enabled

### 5. Secrets (`validate_secrets.yml`)
- **WiFi password**: Checks password is defined when WiFi AP is enabled
- **Authentik secrets**: Validates secret key and PostgreSQL password
- **Database passwords**: Checks Mealie, Immich, and other service database passwords
- **Grafana credentials**: Validates admin password length (min 8 characters)
- **AdGuard password**: Ensures AdGuard Home password is defined
- **Security warning**: Scans for potential plaintext passwords in main.yml

*Note: All secret validation uses `no_log: true` to prevent exposure in logs*

### 6. Feature Flags and Dependencies (`validate_features.yml`)
- **Feature enablement**: Ensures at least one feature is enabled
- **Feature summary**: Displays which features are enabled
- **Traefik requirement**: Validates Traefik is enabled when infrastructure is enabled
- **Service dependencies**:
  - Warns if media enabled but no media services active
  - Checks download client for *arr services
  - Validates Authentik for LDAP/OAuth services
  - Ensures Prometheus for Grafana dashboards
  - Checks Ollama for Open WebUI
  - Validates required Immich services (server, database, redis)
- **WiFi AP safety**: Prevents configuring the SSH management interface as WiFi AP
- **Docker requirement**: Notes Docker will be installed for enabled services

### 7. Variable Validation in Roles (`create_user.yml`)
*Implements the previously unused `checkVar` parameter*

Each role that uses `create_user.yml` can specify required variables in the `checkVar` list:
```yaml
checkVar: [infrastructure, storage.base_dir, infrastructure.user.name, infrastructure.group.name]
```

The validation ensures all listed variables are defined before creating users/directories.

## Usage

### Automatic Execution

The validation role runs automatically at the beginning of every playbook execution:

```bash
# Full deployment (validation runs first)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Selective deployment (validation still runs)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

### Skip Validation

To skip validation (not recommended):

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags validate
```

### Run Only Validation

To test your configuration without deploying:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags validate --check
```

### Selective Validation

Run specific validation checks:

```bash
# Only network validation
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags validate_network

# Only port validation
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags validate_ports

# Only storage validation
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags validate_storage
```

## Configuration

### Variables

Set these in `group_vars/all/main.yml` or pass as extra vars:

```yaml
# Minimum disk space required (in GB)
validation_min_disk_space_gb: 10

# Skip specific validation checks
skip_network_validation: false
skip_storage_validation: false
skip_port_validation: false
skip_secrets_validation: false
skip_features_validation: false

# Validation verbosity level (0=normal, 1=verbose)
validation_verbosity: 0
```

### Example: Increase Disk Space Requirement

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "validation_min_disk_space_gb=50"
```

## Benefits

### 1. Early Error Detection
Catches misconfigurations before deployment starts, saving time and preventing partial deployments.

### 2. Clear Error Messages
Provides actionable error messages that point to exactly what needs to be fixed:

```
FAILED - RETRYING: Validate WiFi password strength (1 retries left)
fatal: [raspberrypi] => {
    "msg": "WiFi password must be between 8 and 63 characters. Current length: 5"
}
```

### 3. Prevents Dangerous Operations
- Stops you from configuring the SSH interface as WiFi AP (would break connectivity)
- Detects port conflicts before services fail to start
- Validates IP address formats before network configuration changes

### 4. Security Enhancements
- Checks password minimum lengths
- Warns about plaintext secrets in main.yml
- Validates secrets are defined without exposing values

### 5. Improved Reliability
- Ensures dependencies are met before deployment
- Validates disk space is sufficient
- Checks parent directories exist before creating subdirectories

## Common Validation Failures

### Port Conflict
```
FAILED! => {"msg": "Port conflict detected! The following ports are assigned to multiple services: 8080, 9000"}
```

**Fix**: Update `group_vars/all/main.yml` to use unique ports for each service.

### Invalid IP Address
```
FAILED! => {"msg": "Invalid IP address format in WiFi configuration. Check wifi.ip, dhcp_range_start, and dhcp_range_end"}
```

**Fix**: Ensure all IP addresses use dotted-quad format (e.g., `10.20.0.1`).

### Missing Secret
```
FAILED! => {"msg": "Authentik secret_key must be defined and at least 32 characters"}
```

**Fix**: Add the secret to `group_vars/all/secrets.yml` (encrypted with Ansible Vault).

### Insufficient Disk Space
```
WARNING: Only 8GB available. Minimum 10GB recommended for Frey services.
```

**Fix**: Free up disk space or adjust `validation_min_disk_space_gb` if intentional.

### WiFi Interface Conflict
```
FAILED! => {"msg": "CRITICAL: WiFi AP interface (wlan0) matches management interface (wlan0). This will break connectivity!"}
```

**Fix**: Use a different WiFi adapter (wlan1) for the access point, not your primary connection.

## Files

```
roles/validation/
├── README.md                      # This file
├── defaults/main.yml              # Default variables
└── tasks/
    ├── main.yml                   # Orchestrates all validation
    ├── validate_variables.yml     # Core variable validation
    ├── validate_network.yml       # Network configuration validation
    ├── validate_storage.yml       # Storage paths and disk space
    ├── validate_ports.yml         # Port conflict detection
    ├── validate_secrets.yml       # Required secrets validation
    └── validate_features.yml      # Feature flags and dependencies
```

## Integration with Other Roles

The validation role complements the existing validation in `wifi_access_point` role but doesn't replace it. Both work together:

1. **Validation role**: Runs first, validates high-level configuration
2. **Role-specific validation**: Each role can add its own detailed checks
3. **checkVar validation**: Now functional in `create_user.yml` for all roles

## Tags

- `validate`: All validation tasks
- `validate_vars`: Only variable validation
- `validate_network`: Only network validation
- `validate_storage`: Only storage validation
- `validate_ports`: Only port validation
- `validate_secrets`: Only secrets validation
- `validate_features`: Only feature validation
- `always`: Validation runs by default (can be skipped with `--skip-tags validate`)

## Debugging

### Increase Verbosity

See detailed validation output:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v
```

For even more detail:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -vv
```

### Check Which Variables Are Set

```bash
ansible -i inventory/hosts.yml all -m debug -a "var=storage"
ansible -i inventory/hosts.yml all -m debug -a "var=network.wifi"
```

## Future Enhancements

Potential additions to validation:

- [ ] Docker image name validation (check if images exist)
- [ ] Certificate validity checks
- [ ] URL reachability tests
- [ ] Dependency graph validation (ensure service dependencies are met)
- [ ] Ansible version compatibility checks
- [ ] Python version validation
- [ ] Memory requirements check
- [ ] Network connectivity pre-tests

## Adding New Stacks

The validation role is designed to be **extensible and dynamic**. When you add a new stack to your Frey deployment, you only need to add one entry to make it automatically validated.

### Steps to Add a New Stack

1. **Add stack to validation list** in `roles/validation/defaults/main.yml`:

```yaml
validation_stacks:
  # ... existing stacks ...
  - name: my_new_stack           # Must match variable name in main.yml
    feature_flag: my_new_stack   # Feature flag in features.* dict
    has_services: true           # Does it have a .services dict?
    has_user_group: true         # Does it have .user and .group config?
```

2. **That's it!** The validation role will automatically:
   - ✓ Validate user/group configuration (if `has_user_group: true`)
   - ✓ Collect and check ports for conflicts (if `has_services: true`)
   - ✓ Count enabled services and warn if none active
   - ✓ Include it in dependency checks

### Example: Adding a "backup" Stack

If you add a new backup stack to your configuration:

```yaml
# In group_vars/all/main.yml
features:
  backup: true

backup:
  user:
    name: backup_manager
    uid: 50000
  group:
    name: backup
    gid: 50000
  services:
    duplicati:
      enabled: true
      port: 8200
    restic:
      enabled: true
      port: 8201
```

Just add this to `validation_stacks`:

```yaml
- name: backup
  feature_flag: backup
  has_services: true
  has_user_group: true
```

Now the validation will automatically:
- Check that `backup.user.name`, `backup.user.uid`, `backup.group.name`, `backup.group.gid` are defined
- Collect ports 8200 and 8201 for conflict detection
- Warn if backup is enabled but no services are active
- Validate the feature flag is boolean

### Stack Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `name` | Variable name of the stack (e.g., `media`, `infrastructure`) | Required |
| `feature_flag` | Feature flag name in `features.*` dict | Required |
| `has_services` | Whether stack has a `.services` dictionary | `false` |
| `has_user_group` | Whether stack has `.user` and `.group` config | `false` |

**Notes:**
- Set `has_user_group: false` for stacks with custom user naming (like Immich which uses `photos_manager`)
- Set `has_services: false` for system-level stacks without service dictionaries

## Contributing

To add new validation checks:

1. Create a new task file in `roles/validation/tasks/` (e.g., `validate_docker.yml`)
2. Add validation using `ansible.builtin.assert` with clear error messages
3. Include the task file in `roles/validation/tasks/main.yml`
4. Add corresponding tags for selective execution
5. Update this README with the new validation details

### Best Practices for Dynamic Validation

When adding validation, prefer **dynamic loops** over hardcoded checks:

**❌ Bad (hardcoded, not extensible):**
```yaml
- name: Check infrastructure ports
  set_fact:
    ports: "{{ infrastructure.services | ... }}"
- name: Check media ports
  set_fact:
    ports: "{{ media.services | ... }}"
```

**✅ Good (dynamic, extensible):**
```yaml
- name: Check all stack ports
  include_tasks: collect_ports.yml
  loop: "{{ validation_stacks }}"
```

This way, new stacks are automatically validated without modifying validation code.

## Related Documentation

- Main playbook: `playbooks/site.yml`
- Configuration: `group_vars/all/main.yml`
- Secrets: `group_vars/all/secrets.yml`
- WiFi AP validation: `roles/wifi_access_point/tasks/main.yml`
- Project documentation: `CLAUDE.md`
