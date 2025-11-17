# Validation Role

This role performs comprehensive input validation of the Frey configuration to prevent misconfigurations and deployment errors.

## Purpose

The validation role checks configuration before deployment to catch common errors early:

- **Network Configuration**: Validates subnet overlaps, CIDR notation, DHCP ranges, IP addresses
- **Port Conflicts**: Detects duplicate port assignments across services
- **Feature Dependencies**: Ensures required services are enabled (e.g., landing page requires infrastructure)
- **Storage Paths**: Validates all paths are absolute and properly formatted
- **Secrets & Credentials**: Checks password strength and credential requirements
- **User/Group IDs**: Validates UID/GID uniqueness and proper ranges

## Usage

The validation role is automatically included at the beginning of the main playbook:

```yaml
- hosts: all
  roles:
    - validation  # Runs first to catch configuration errors
    - docker_minimal
    - infrastructure
    # ... other roles
```

### Run Validation Only

To run just the validation without deploying:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags validation
```

### Run Specific Validation

Run only network validation:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "validation,network"
```

Available validation tags:
- `validation` - All validations
- `network` - Network configuration
- `ports` - Port conflicts
- `features` - Feature dependencies
- `storage` - Storage paths
- `secrets` - Credentials and secrets
- `users` - User/group IDs

### Skip Validation

**Not recommended**, but you can skip validation:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags validation
```

## Validation Checks

### Network Validation (`tasks/network.yml`)

- WiFi interface name specified
- Subnet CIDR format validity
- IP address format validation
- DHCP range validity
- SSID length (1-32 characters)
- WPA2 password requirements (8-63 characters)
- Hardware mode validity (a/b/g/auto)
- **Subnet overlap detection** (critical: prevents WiFi AP and media network conflicts)
- Domain name format
- Timezone configuration

### Port Conflict Detection (`tasks/ports.yml`)

Collects all enabled service ports and checks for duplicates across:
- Infrastructure services (Traefik, Portainer, Dockge)
- Media services (Jellyfin, *arr stack, download clients)
- Monitoring services (Grafana, Prometheus, Loki)
- Automation services (Ollama, Open WebUI, n8n)
- Landing page
- Firewall port range validation (1-65535)

### Feature Dependencies (`tasks/features.yml`)

- Boolean type validation for all feature flags
- Landing page requires infrastructure (Traefik)
- *arr services need download clients (qBittorrent or NZBGet)
- Prowlarr recommended for multiple *arr services
- Grafana requires data sources (Prometheus or Loki)
- Open WebUI requires Ollama
- WiFi AP configuration completeness
- Service enabled flags are boolean

### Storage Path Validation (`tasks/storage.yml`)

- Base directory is absolute path
- Appdata directory is absolute path
- Stacks directory is absolute path
- Media directories are absolute paths
- Monitoring data directories validation
- Automation service directories validation
- No relative paths (./directory patterns)
- Path nesting depth warnings
- Storage space recommendations

### Secrets Validation (`tasks/secrets.yml`)

- Vault configuration check
- WiFi password WPA2 compliance
- qBittorrent credentials validation
- Grafana admin password security
- **Critical check**: Prevents default 'admin' password
- n8n encryption key length (32+ characters)
- Common weak password detection
- Security best practices reminders

### User/Group Validation (`tasks/users.yml`)

- UID range validation (1000-65533)
- GID range validation (1000-65533)
- **UID uniqueness** across all stacks
- **GID uniqueness** across all stacks
- Username Linux naming conventions
- Group name Linux naming conventions
- Configuration summary output

## Configuration Variables

### Default Variables (`defaults/main.yml`)

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

## Critical Issues Prevented

### 1. Network Subnet Overlap (CRITICAL)

**Problem**: WiFi AP subnet (10.20.0.0/24) overlapping with media network (10.20.0.0/24) causes routing conflicts.

**Detection**: Network validation compares subnet prefixes and fails if overlap detected.

**Fix**: Change one subnet to different range (e.g., 10.30.0.0/24).

### 2. Port Conflicts (HIGH)

**Problem**: Multiple services configured with same port cause deployment failures.

**Detection**: Collects all ports from enabled services and checks for duplicates.

**Fix**: Reconfigure conflicting services to use unique ports.

### 3. Missing Dependencies (HIGH)

**Problem**: Landing page enabled without Traefik causes routing failures.

**Detection**: Checks feature dependencies before deployment.

**Fix**: Enable required infrastructure stack.

### 4. UID/GID Conflicts (MEDIUM)

**Problem**: Duplicate UIDs cause file permission issues between services.

**Detection**: Validates uniqueness across all user/group definitions.

**Fix**: Assign unique IDs to each stack user/group.

### 5. Weak Credentials (SECURITY)

**Problem**: Default or weak passwords compromise security.

**Detection**: Password strength validation and default password detection.

**Fix**: Set strong, unique passwords in secrets.yml.

## Best Practices

1. **Always run validation** before deploying changes
2. **Never skip validation** in production environments
3. **Review warnings** even if they don't fail the playbook
4. **Use Ansible Vault** for all secrets (validated by secrets.yml tasks)
5. **Test with `--check` mode** after fixing validation errors

## Example Output

### Successful Validation

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

### Failed Validation (Port Conflict)

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

### Failed Validation (Subnet Overlap)

```
TASK [validation : Warn if WiFi and media subnets overlap]
fatal: [frey]: FAILED! =>
  msg: |
    CRITICAL: Network subnet overlap detected!
    WiFi AP subnet: 10.20.0.0/24
    Media network subnet: 10.20.0.0/24
    These subnets must not overlap to prevent routing conflicts.
```

## Extending Validation

To add new validation checks:

1. Create or modify task file in `tasks/`
2. Add validation assertions using `ansible.builtin.assert`
3. Provide clear `fail_msg` explaining the issue and how to fix it
4. Provide descriptive `success_msg` confirming validation passed
5. Include in `tasks/main.yml` with appropriate tags

Example:

```yaml
- name: Validate custom setting
  ansible.builtin.assert:
    that:
      - custom_setting is defined
      - custom_setting | int > 0
    fail_msg: "custom_setting must be positive integer"
    success_msg: "✓ custom_setting is valid: {{ custom_setting }}"
```

## Troubleshooting

### Validation fails but configuration looks correct

1. Check variable scoping (role defaults vs group_vars)
2. Verify variable types (string vs integer vs boolean)
3. Review conditional logic (when clauses)

### Validation passes but deployment still fails

1. Validation may not cover all edge cases
2. Runtime issues (network, Docker, permissions) aren't caught
3. Consider adding new validation checks for the issue

### Too many false positives

1. Review strict mode setting
2. Adjust validation thresholds if needed
3. Document exceptions in configuration

## Contributing

When adding new features to Frey:

1. Add corresponding validation checks
2. Test with both valid and invalid configurations
3. Update this README with new validation descriptions
4. Include clear error messages in assertions
