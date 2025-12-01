# WiFi Captive Portal Automation - Ansible Deployment Guide

## Overview

This Ansible-based automation enables your Raspberry Pi to **automatically authenticate with public WiFi networks** that have login pages (captive portals). Once deployed via Ansible, the daemon runs continuously in the background, detecting and bypassing captive portals without user intervention.

## Features

✅ **Automatic Portal Detection** - Detects when connected to a captive portal  
✅ **Auto-Submit Forms** - Automatically fills and submits login forms  
✅ **Multiple Bypass Methods** - Tries various techniques to bypass portals  
✅ **Internet Verification** - Confirms successful authentication  
✅ **Background Daemon** - Runs as systemd service, survives reboots  
✅ **Logging** - Full logs for debugging and monitoring  
✅ **Resource Efficient** - Uses minimal CPU and memory  

## Prerequisites

### What You Need

1. **Frey Project Directory** - Your ansible project at `/home/jim/Projects/frey0`
2. **SSH Access** - SSH configured to your Raspberry Pi as shown:
   ```bash
   ssh -i ~/.ssh/id_rsa_ansible ansible@frey
   ```
3. **Ansible Inventory** - Your Pi configured in `inventory/hosts.yml`
4. **WiFi Configured** - WiFi roaming enabled in your config

### Expected Configuration

The automation is controlled by WiFi roaming settings in `group_vars/all/main.yml`:

```yaml
network:
  wifi:
    roaming:
      enabled: true              # Enable WiFi roaming
      daemon_enabled: true       # Enable roaming daemon
      client_interface: "wlan0"  # Interface for connecting to public WiFi
      known_networks: []         # List of known WiFi networks (optional)
```

When `network.wifi.roaming.enabled` is `true`, Ansible will automatically deploy and enable the captive portal daemon.

## Deployment

### Method 1: Deploy All WiFi Services (Recommended)

Run the full playbook to deploy the complete WiFi infrastructure including captive portal automation:

```bash
cd /home/jim/Projects/frey0

# Full deployment with encryption
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "ansible_ssh_private_key_file=~/.ssh/id_rsa_ansible" \
  --vault-password-file .vault_pass

# Or dry-run first to see what will happen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "ansible_ssh_private_key_file=~/.ssh/id_rsa_ansible" \
  --vault-password-file .vault_pass \
  --check --diff
```

### Method 2: Deploy Only WiFi Services

Deploy only the WiFi access point role including captive portal:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "ansible_ssh_private_key_file=~/.ssh/id_rsa_ansible" \
  --vault-password-file .vault_pass \
  --tags wifi_access_point
```

### Method 3: Deploy Only Captive Portal Daemon

Deploy just the captive portal daemon (requires WiFi roaming already configured):

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "ansible_ssh_private_key_file=~/.ssh/id_rsa_ansible" \
  --vault-password-file .vault_pass \
  --tags captive_portal
```

## What Gets Installed

When Ansible deploys the WiFi access point role with roaming enabled, it installs:

1. **Scripts** (in `/usr/local/bin/`)
   - `frey-wifi-captive-portal-auto` - Single-shot portal bypass script
   - `frey-wifi-captive-portal-daemon` - Daemon wrapper that monitors WiFi

2. **Systemd Service** (in `/etc/systemd/system/`)
   - `frey-wifi-captive-portal-daemon.service` - Automatically starts on boot

3. **Log Files** (in `/var/log/`)
   - `frey-wifi-captive-portal-daemon.log` - Daemon activity logs

## Using After Deployment

### Verify Installation

After Ansible completes deployment, verify everything is running:

```bash
# Check daemon status
sudo systemctl status frey-wifi-captive-portal-daemon

# View live logs
sudo journalctl -u frey-wifi-captive-portal-daemon -f

# Check if daemon is enabled for auto-start
sudo systemctl is-enabled frey-wifi-captive-portal-daemon
# Output: enabled
```

### Test Manually

To test the captive portal bypass without waiting for the daemon:

```bash
# Run the auto-bypass script directly (verbose output)
sudo /usr/local/bin/frey-wifi-captive-portal-auto --verbose

# Check exit code
echo $?
# 0 = Portal bypassed successfully
# 1 = No portal detected
# 2 = Portal detected but manual intervention needed
```

### View Captured Portal Pages

The script saves captured portal pages for debugging:

```bash
# View last captured portal page
sudo cat /var/log/frey-captive-portal-latest.html | less

# View headers
sudo cat /var/log/frey-captive-portal-headers.txt
```

### Manage the Daemon

```bash
# Stop daemon (if it's interfering)
sudo systemctl stop frey-wifi-captive-portal-daemon

# Start daemon
sudo systemctl start frey-wifi-captive-portal-daemon

# Restart daemon
sudo systemctl restart frey-wifi-captive-portal-daemon

# View last 50 log lines
sudo journalctl -u frey-wifi-captive-portal-daemon -n 50

# Disable auto-start (won't run on reboot)
sudo systemctl disable frey-wifi-captive-portal-daemon

# Re-enable auto-start
sudo systemctl enable frey-wifi-captive-portal-daemon
```

## Configuration

### Via Ansible (Recommended)

To customize the behavior, modify `/home/jim/Projects/frey0/group_vars/all/main.yml` **before** running Ansible:

```yaml
network:
  wifi:
    roaming:
      enabled: true
      daemon_enabled: true
      client_interface: "wlan0"  # Change if different interface
      known_networks:
        - ssid: "MyLibrary"
          password: "password123"
        - ssid: "CoffeeShop"
          password: "coffee2024"
```

Then re-deploy:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags wifi_access_point \
  --vault-password-file .vault_pass
```

### Via Systemd Service (Advanced)

After deployment, you can edit the systemd service to change parameters:

```bash
sudo systemctl edit frey-wifi-captive-portal-daemon
```

This opens an editor to override service settings. For example, to change the interface:

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/frey-wifi-captive-portal-daemon --interface wlan1 --check-interval 30
```

Then reload systemd:

```bash
sudo systemctl daemon-reload
sudo systemctl restart frey-wifi-captive-portal-daemon
```

### Via Environment Variables

You can set environment variables before starting the daemon:

```bash
INTERFACE=wlan1 CHECK_INTERVAL=30 sudo systemctl restart frey-wifi-captive-portal-daemon
```

## How It Works

### Detection Phase
1. Daemon continuously monitors your WiFi connection
2. Checks if you're connected to a network
3. Tests internet access via Firefox's portal detection endpoint
4. If no internet, checks for a captive portal redirect

### Bypass Methods (attempted in order)
1. **Simple Visit** - Just accessing the portal page authenticates you
2. **Form Auto-Submit** - Finds and submits login forms with default values
3. **Button Click** - Clicks "Accept" or "Agree" buttons
4. **API Endpoints** - Tries common portal API endpoints
5. **Query Parameters** - Appends common acceptance parameters
6. **Form Extraction** - Parses and submits complex forms

### Success Verification
After each attempt, the script verifies internet by:
- Testing Firefox's portal detection endpoint
- If you get a `success` response → you have internet! ✅
- Otherwise → retries with next method

### Retry Logic
- Maximum 3 attempts per portal
- 60 second cooldown between attempts
- 30 second check interval between WiFi connection checks
- All configurable via daemon parameters

## Troubleshooting

### Daemon Not Running

```bash
# Check systemd status
sudo systemctl status frey-wifi-captive-portal-daemon

# View systemd logs for errors
sudo journalctl -u frey-wifi-captive-portal-daemon --no-pager | tail -20

# Check if script exists
ls -la /usr/local/bin/frey-wifi-captive-portal-daemon
ls -la /usr/local/bin/frey-wifi-captive-portal-auto
```

### Scripts Not Found

If deployment didn't create the scripts:

```bash
# Check what exists
ls -la /usr/local/bin/frey-wifi-*

# Manually copy if missing
sudo cp /home/jim/Projects/frey0/roles/wifi_access_point/files/frey-wifi-captive-portal-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/frey-wifi-captive-portal-*
```

### Re-run Ansible Deployment

To fix deployment issues, re-run the appropriate Ansible command:

```bash
# Re-deploy WiFi services
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags wifi_access_point,captive_portal \
  --vault-password-file .vault_pass \
  --check  # First do --check to see what would change
```

### Portal Bypass Not Working

For a specific WiFi network:

1. **Capture the portal page** for analysis:
   ```bash
   sudo /usr/local/bin/frey-wifi-captive-portal-auto --verbose
   cat /var/log/frey-captive-portal-latest.html | head -100
   ```

2. **Check if portal requires JavaScript** - If there are `<script>` tags, automated bypass may not work

3. **Check required form fields**:
   ```bash
   grep -i "input\|form" /var/log/frey-captive-portal-latest.html
   ```

4. **Share logs** (redact sensitive info) in the frey project for help

### View Recent Activity

```bash
# Last 30 lines of daemon logs
sudo journalctl -u frey-wifi-captive-portal-daemon -n 30

# Watch logs in real-time
sudo journalctl -u frey-wifi-captive-portal-daemon -f

# Logs from specific time period
sudo journalctl -u frey-wifi-captive-portal-daemon --since "2 hours ago"
```

## Logs

### Daemon Log File

Location: `/var/log/frey-wifi-captive-portal-daemon.log`

Contains:
- Connection status (connected/disconnected)
- Portal detection attempts
- Bypass method attempts and results
- Internet connectivity verification
- Timestamps for debugging

View:
```bash
sudo tail -f /var/log/frey-wifi-captive-portal-daemon.log
```

### Systemd Journal

Contains structured logs with timestamps:

```bash
sudo journalctl -u frey-wifi-captive-portal-daemon -f
```

### Captured Portal Pages

- Latest portal page: `/var/log/frey-captive-portal-latest.html`
- Portal headers: `/var/log/frey-captive-portal-headers.txt`
- Fallback locations: `/tmp/frey-captive-portal-*`

## Uninstallation

To remove the captive portal daemon:

```bash
# Stop and disable the service
sudo systemctl stop frey-wifi-captive-portal-daemon
sudo systemctl disable frey-wifi-captive-portal-daemon

# Remove files
sudo rm /usr/local/bin/frey-wifi-captive-portal-*
sudo rm /etc/systemd/system/frey-wifi-captive-portal-daemon.service

# Reload systemd
sudo systemctl daemon-reload

# Clean up logs
sudo rm /var/log/frey-captive-portal-*
```

Or re-run Ansible with roaming disabled:

```bash
# In group_vars/all/main.yml, set:
# network.wifi.roaming.enabled: false

ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags wifi_access_point \
  --vault-password-file .vault_pass
```

## Integration with Frey Project

This automation is integrated into the **frey WiFi Access Point role** (`roles/wifi_access_point/`).

### Files Deployed

```
roles/wifi_access_point/
├── files/
│   ├── frey-wifi-captive-portal-auto.sh       # Auto-bypass script (deployed)
│   └── frey-wifi-captive-portal-daemon.sh     # Daemon wrapper (deployed)
├── templates/
│   └── frey-wifi-captive-portal-daemon.service.j2  # Systemd service template
└── tasks/
    └── main.yml  # Includes captive portal deployment tasks
```

### Deployment Conditions

The captive portal daemon is deployed when:
1. ✅ Ansible playbook is run on the Pi
2. ✅ `network.wifi.roaming.enabled: true` in config
3. ✅ The WiFi access point role is executed (`--tags wifi_access_point` or full playbook)

### Git Hooks

This project uses git hooks to encrypt secrets before commit. Captive portal configuration (including WiFi passwords) is kept in the encrypted `group_vars/all/secrets.yml` file.

## Support & Debugging

### Enable Verbose Logging

Run the auto-script directly with verbose mode:

```bash
sudo /usr/local/bin/frey-wifi-captive-portal-auto --verbose
```

### Capture Portal HTML

The script automatically captures the portal page. View it:

```bash
sudo cat /var/log/frey-captive-portal-latest.html | less
```

### Check Daemon Configuration

View the deployed systemd service:

```bash
sudo systemctl cat frey-wifi-captive-portal-daemon
```

### Manual Service Edit

To modify the service configuration:

```bash
sudo systemctl edit frey-wifi-captive-portal-daemon
# This creates an override file at:
# /etc/systemd/system/frey-wifi-captive-portal-daemon.service.d/override.conf
```

## Next Steps

1. ✅ Ensure WiFi roaming is enabled in your configuration
2. ✅ Run Ansible playbook to deploy
3. ✅ Verify daemon is running with `systemctl status`
4. ✅ Connect to a public WiFi with a login page
5. ✅ Check logs: `sudo journalctl -u frey-wifi-captive-portal-daemon -f`
6. ✅ Test internet access once daemon detects and bypasses portal

## Related Commands

```bash
# View all WiFi-related systemd services
systemctl list-units --all | grep frey-wifi

# Check WiFi connection status
iw dev wlan0 link

# Restart WiFi interface
sudo systemctl restart wpa_supplicant@wlan0

# View WiFi logs
sudo journalctl -u wpa_supplicant@wlan0 -f

# Check IP address
ip addr show wlan0
```

## Files in This Project

- **Ansible Playbook**: `playbooks/site.yml`
- **WiFi Role**: `roles/wifi_access_point/`
- **Scripts**: `roles/wifi_access_point/files/frey-wifi-captive-portal-*.sh`
- **Service Template**: `roles/wifi_access_point/templates/frey-wifi-captive-portal-daemon.service.j2`
- **Configuration**: `group_vars/all/main.yml` and `group_vars/all/secrets.yml`
- **Inventory**: `inventory/hosts.yml`
