# WiFi Captive Portal Automation - Quick Start Guide

## Overview

This automation enables your Raspberry Pi to automatically authenticate with public WiFi networks (like libraries, cafes, hotels) that have login pages (captive portals). Once authenticated, you'll have real internet access through your Pi.

## Components

1. **`frey-wifi-captive-portal-auto.sh`** - Single-shot portal detection and bypass script
2. **`frey-wifi-captive-portal-daemon.sh`** - Background daemon that monitors and retries portal authentication
3. **`frey-wifi-captive-portal-daemon.service`** - Systemd service for automatic startup

## Installation

### Manual Installation (Quick Test)

```bash
# Copy scripts to system
sudo cp /home/jim/Projects/frey0/roles/wifi_access_point/files/frey-wifi-captive-portal-auto.sh /usr/local/bin/
sudo cp /home/jim/Projects/frey0/roles/wifi_access_point/files/frey-wifi-captive-portal-daemon.sh /usr/local/bin/

# Make executable
sudo chmod +x /usr/local/bin/frey-wifi-captive-portal-auto.sh
sudo chmod +x /usr/local/bin/frey-wifi-captive-portal-daemon.sh

# Copy systemd service
sudo cp /home/jim/Projects/frey0/roles/wifi_access_point/templates/frey-wifi-captive-portal-daemon.service.j2 /etc/systemd/system/frey-wifi-captive-portal-daemon.service

# Fix service file (remove .j2 template syntax if present, rename properly)
sudo systemctl daemon-reload
```

### Using Ansible (Recommended)

Update your Ansible playbook to include the `wifi_access_point` role, which will:
- Install both scripts
- Configure the systemd service
- Set proper permissions
- Enable automatic startup

```yaml
# In your playbooks/site.yml or similar
- hosts: all
  roles:
    - wifi_access_point
  tags:
    - wifi
```

Then deploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags wifi
```

## Running the Daemon

### Start the daemon (one-time)

```bash
sudo systemctl start frey-wifi-captive-portal-daemon
```

### Enable automatic startup

```bash
sudo systemctl enable frey-wifi-captive-portal-daemon
```

### View logs in real-time

```bash
# Live logs
sudo journalctl -u frey-wifi-captive-portal-daemon -f

# Or from log file
tail -f /var/log/frey-wifi-captive-portal-daemon.log
```

### Check daemon status

```bash
sudo systemctl status frey-wifi-captive-portal-daemon
```

### Stop the daemon

```bash
sudo systemctl stop frey-wifi-captive-portal-daemon
```

## Testing the Automation

### Connect to a public WiFi with a captive portal

```bash
# Find available networks
sudo iwlist wlan0 scan | grep ESSID

# Connect to the network (using wpa_supplicant or your WiFi manager)
# Once connected but without portal auth, you won't have internet yet
```

### Run portal bypass manually (for debugging)

```bash
# Verbose output to see what's happening
/usr/local/bin/frey-wifi-captive-portal-auto --interface wlan0 --verbose

# Check exit code
echo $?
# 0 = Portal bypassed successfully
# 1 = No portal detected or bypass failed
# 2 = Portal detected but manual intervention needed
```

### View captured portal pages

```bash
# Last captured portal page
cat /var/log/frey-captive-portal-latest.html

# Last captured headers
cat /var/log/frey-captive-portal-headers.txt

# Fallback locations if /var/log not writable
cat /tmp/frey-captive-portal-latest.html
cat /tmp/frey-captive-portal-headers.txt
```

## How It Works

### Detection Phase
The daemon continuously monitors your WiFi connection by:
1. Checking if you're connected to a WiFi network
2. Testing internet access via Firefox's portal detection endpoint
3. If no internet, checks for a captive portal redirect

### Bypass Methods (in order of attempt)
1. **Simple Visit** - Just accessing the portal page may authenticate you
2. **Auto-Submit Forms** - Finds and submits login forms with default values
3. **Button Click** - Clicks "Accept" or "Agree" buttons automatically
4. **API Endpoints** - Tries common portal API endpoints
5. **Query Parameters** - Appends common acceptance parameters to URLs
6. **Auto-Form** - Extracts hidden form fields and submits them

### Success Verification
After each bypass attempt, the script verifies internet access using:
- Firefox portal detection endpoint: `http://detectportal.firefox.com/success.txt`
- If you get a `success` response, you have full internet access

## Configuration

### Via Systemd Service

Edit `/etc/systemd/system/frey-wifi-captive-portal-daemon.service`:

```ini
# Change check interval (in seconds)
# Shorter = more aggressive monitoring, higher CPU usage
# Default: 30 seconds
ExecStart=/usr/local/bin/frey-wifi-captive-portal-daemon --interface wlan0 --check-interval 30

# Change interface if needed (e.g., for different WiFi adapter)
ExecStart=/usr/local/bin/frey-wifi-captive-portal-daemon --interface wlan1 --check-interval 30
```

After editing:
```bash
sudo systemctl daemon-reload
sudo systemctl restart frey-wifi-captive-portal-daemon
```

### Via Environment Variables

```bash
# Set these before starting the daemon
INTERFACE=wlan0 CHECK_INTERVAL=30 /usr/local/bin/frey-wifi-captive-portal-daemon
```

### Daemon Configuration Constants

Inside `frey-wifi-captive-portal-daemon.sh`, adjust:

```bash
MAX_PORTAL_ATTEMPTS=3      # How many times to retry portal bypass
PORTAL_COOLDOWN=60         # Seconds between retry attempts
CHECK_INTERVAL=30          # How often to check for portal (seconds)
```

## Troubleshooting

### Daemon not starting

```bash
# Check service status and error
sudo systemctl status frey-wifi-captive-portal-daemon

# Check journalctl for detailed errors
sudo journalctl -u frey-wifi-captive-portal-daemon -n 50
```

### Script not found in daemon logs

Make sure both scripts are installed:
```bash
ls -la /usr/local/bin/frey-wifi-captive-portal-*.sh
```

If missing, copy them:
```bash
sudo cp roles/wifi_access_point/files/frey-wifi-captive-portal-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/frey-wifi-captive-portal-*.sh
```

### Portal detection working but bypass failing

1. Check the captured portal page:
   ```bash
   cat /var/log/frey-captive-portal-latest.html | head -50
   ```

2. Run with verbose output:
   ```bash
   /usr/local/bin/frey-wifi-captive-portal-auto --interface wlan0 --verbose
   ```

3. Check portal headers for hints:
   ```bash
   cat /var/log/frey-captive-portal-headers.txt
   ```

### Still no internet after "successful" bypass

Some portals require:
- JavaScript execution (not possible with curl)
- User account login (not automated)
- Complex multi-step authentication
- Device registration

For these cases, you may need manual authentication through a browser. Check the captured portal page to understand requirements.

## Advanced Usage

### Run multiple WiFi interfaces

```bash
# Terminal 1: Monitor wlan0
/usr/local/bin/frey-wifi-captive-portal-daemon --interface wlan0

# Terminal 2: Monitor wlan1
/usr/local/bin/frey-wifi-captive-portal-daemon --interface wlan1
```

### Integrate with WiFi connection scripts

Add to your WiFi connection automation:
```bash
# After connecting to WiFi
/usr/local/bin/frey-wifi-captive-portal-auto --interface wlan0 --verbose

# Or let the daemon handle it
sudo systemctl status frey-wifi-captive-portal-daemon
```

### Custom portal detection

Modify `detect_portal()` function to add site-specific detection logic if needed.

## Logs Location

- **Daemon logs**: `/var/log/frey-wifi-captive-portal-daemon.log`
- **System journal**: `journalctl -u frey-wifi-captive-portal-daemon`
- **Captured portals**: `/var/log/frey-captive-portal-latest.html`
- **Portal headers**: `/var/log/frey-captive-portal-headers.txt`
- **Fallback location** (if /var/log not writable): `/tmp/frey-captive-portal-*`

## Support & Debugging

If the automation fails for a specific WiFi network:

1. **Capture the portal page**:
   ```bash
   /usr/local/bin/frey-wifi-captive-portal-auto --interface wlan0 --verbose
   cat /var/log/frey-captive-portal-latest.html
   ```

2. **Check if portal uses JavaScript**:
   - Look for `<script>` tags in the captured HTML
   - If present, automated bypass may not work

3. **Check required fields**:
   - Look for form inputs that might need authentication
   - Note form action URL

4. **Share logs** (redact sensitive info):
   - Portal page HTML
   - Portal headers
   - Daemon logs

## Exit Codes

**`frey-wifi-captive-portal-auto` exit codes:**

- `0` - Portal bypassed successfully, internet access confirmed
- `1` - No portal detected OR bypass failed after all attempts
- `2` - Portal detected but automatic bypass failed (manual intervention needed)

**Daemon**: Runs continuously, use `systemctl status` to check health.

## Next Steps

1. ✅ Install the scripts (above)
2. ✅ Enable the systemd service
3. ✅ Connect to a public WiFi with a captive portal
4. ✅ Check logs: `sudo journalctl -u frey-wifi-captive-portal-daemon -f`
5. ✅ Verify internet access works

Once working, your Pi will automatically handle captive portals in the future!
