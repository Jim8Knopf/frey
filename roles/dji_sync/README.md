# DJI Drone Auto-Sync to Immich

Automatically syncs photos and videos from DJI drones to your Immich photo library when connected via USB.

## Features

- **USB Auto-Detection**: Automatically detects when DJI controller/drone is connected
- **Auto-Mount**: Mounts the USB storage device automatically
- **Smart Upload**: Uses Immich CLI to upload photos/videos
- **Duplicate Detection**: Skips already uploaded files using hash comparison
- **Album Organization**: Automatically creates and uploads to "DJI Drone Photos" album
- **Notifications**: MQTT notifications for Home Assistant integration
- **Safe Unmount**: Automatically unmounts device after successful sync
- **Comprehensive Logging**: Detailed logs for troubleshooting

## Supported Devices

- DJI Mini 4 Pro (controller or drone via USB)
- DJI RC 2 / RC-N2 controllers
- Any DJI drone with USB mass storage mode

## Requirements

1. **Immich installed and running** on your Frey server
2. **Immich API key** (generated in web UI)
3. **USB connection** between Raspberry Pi and DJI controller/drone

## Setup Instructions

### Step 1: Generate Immich API Key

1. Open Immich web UI: `http://immich.frey` (or `http://10.20.0.1:2283`)
2. Click on your profile (top right)
3. Go to **Account Settings** → **API Keys**
4. Click **New API Key**
5. Give it a name (e.g., "DJI Auto-Sync")
6. Copy the generated API key

### Step 2: Add API Key to Secrets

Edit your secrets file:

```bash
ansible-vault edit group_vars/all/secrets.yml
```

Add this line (replace with your actual API key):

```yaml
dji_sync_immich_api_key: "your-api-key-here-from-immich-web-ui"
```

### Step 3: Enable DJI Sync

Edit `group_vars/all/main.yml`:

```yaml
dji_sync:
  enabled: true  # Change from false to true
```

### Step 4: Deploy

Run the Ansible playbook:

```bash
# Deploy only DJI sync
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags dji_sync

# Or deploy everything
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

## Usage

### Automatic Sync

1. Connect your DJI controller or drone to the Raspberry Pi via USB
2. Wait 10-30 seconds for the sync to complete
3. Check logs or Home Assistant for sync status notification
4. Safely disconnect the device when sync is complete

### Manual Sync (Testing)

You can manually trigger a sync for testing:

```bash
# Find your device (usually /dev/sdb1 or /dev/sdc1)
lsblk

# Manually run sync script
sudo bash /usr/local/bin/dji-sync.sh /dev/sdb1
```

## Configuration

All configuration is in `group_vars/all/main.yml` under the `dji_sync` section:

### Sync Folders

By default, syncs these folders from the DJI device:

- `DCIM` - Standard photo/video folder
- `PANORAMA` - Panoramic photos

### File Types

Uploads these file types:

- Photos: `.JPG`, `.JPEG`, `.DNG` (RAW)
- Videos: `.MP4`, `.MOV`

### Behavior Settings

```yaml
dji_sync:
  sync:
    skip_duplicates: true        # Skip already uploaded files
    delete_after_sync: false     # ⚠️ Delete from drone after upload
    target_album: "DJI Drone Photos"  # Album name in Immich
  mount:
    auto_unmount: true           # Automatically unmount after sync
    unmount_delay: 30            # Wait 30 seconds before unmounting
```

## Monitoring

### View Live Logs

```bash
# Real-time logs
sudo journalctl -u dji-sync@* -f

# Recent sync activity
sudo journalctl -u dji-sync@* -n 100
```

### Sync History

```bash
# List all sync log files
ls -lh /var/log/dji-sync/

# View latest sync log
cat /var/log/dji-sync/sync_*.log | tail -100
```

### Home Assistant Integration

If you have Home Assistant enabled, sync events are published to MQTT:

**Topic:** `frey/dji/sync/status`

**Message format:**
```json
{
  "type": "info|success|error",
  "message": "DJI device connected, starting sync...",
  "timestamp": "2025-11-19T10:30:00+00:00"
}
```

## Troubleshooting

### Sync not triggering

1. **Check USB connection:**
   ```bash
   lsusb
   dmesg | tail -20
   ```

2. **Check udev rules:**
   ```bash
   udevadm control --reload-rules
   udevadm trigger
   ```

3. **Manually trigger for testing:**
   ```bash
   # Find device
   lsblk

   # Test sync
   sudo systemctl start dji-sync@sdb1.service

   # Check logs
   journalctl -u dji-sync@sdb1 -f
   ```

### Upload failures

1. **Verify Immich CLI is installed:**
   ```bash
   immich --version
   ```

2. **Test Immich connection:**
   ```bash
   immich server-info
   ```

3. **Check API key:**
   ```bash
   cat /root/.config/immich/auth.json
   ```

### Device won't unmount

If the device doesn't auto-unmount:

```bash
# Check what's using it
lsof | grep /media/dji-sync

# Force unmount
sudo umount /media/dji-sync/<device>
```

## Advanced Configuration

### Change Target Album

Edit `group_vars/all/main.yml`:

```yaml
dji_sync:
  sync:
    target_album: "My Custom Album Name"
```

### Add More File Types

```yaml
dji_sync:
  sync:
    include_extensions:
      - "*.JPG"
      - "*.DNG"
      - "*.MP4"
      - "*.AVI"  # Add custom types
```

### Disable Auto-Unmount

Useful if you want to browse photos before disconnecting:

```yaml
dji_sync:
  mount:
    auto_unmount: false
```

Then manually unmount:

```bash
sudo umount /media/dji-sync/<device>
```

## Safety Notes

### Delete After Sync

⚠️ **CAUTION:** The `delete_after_sync` option will DELETE photos from your drone/controller after uploading to Immich.

**Only enable this if:**
- You have verified Immich backups are working
- You trust the upload process
- You understand the photos will be permanently deleted from the device

**Recommended:** Keep `delete_after_sync: false` and manually delete photos after verifying uploads.

### Backup Strategy

Even with auto-sync, consider:
1. **Regular Immich database backups** (see backup role)
2. **External photo backups** (copy `/opt/frey/photos/library` to external drive)
3. **Keep originals on SD card** until verified in Immich

## File Locations

- **Sync script:** `/usr/local/bin/dji-sync.sh`
- **Systemd service:** `/etc/systemd/system/dji-sync@.service`
- **udev rules:** `/etc/udev/rules.d/99-dji-sync.rules`
- **Logs directory:** `/var/log/dji-sync/`
- **Mount point:** `/media/dji-sync/<device>/`
- **Immich auth:** `/root/.config/immich/auth.json`

## Performance

- **Sync speed:** ~10-20 MB/s (USB 3.0)
- **Typical sync time:**
  - 100 photos (~500MB): 30-60 seconds
  - 500 photos (~2.5GB): 2-5 minutes
  - 1000 photos (~5GB): 5-10 minutes

Video uploads will take longer depending on file size.

## Comparison with Alternatives

| Method | Pros | Cons |
|--------|------|------|
| **USB Auto-Sync** (this) | Fully automatic, fast, no phone needed | Requires physical connection |
| **Immich Mobile App** | Works anywhere, no computer needed | Must transfer to phone first |
| **Immich CLI Manual** | Full control, scriptable | Manual process |
| **External Library** | No upload time, direct filesystem | Requires network transfer (rsync) |

## Support

For issues or questions:
- Check logs: `journalctl -u dji-sync@* -n 100`
- Manual test: `sudo bash /usr/local/bin/dji-sync.sh /dev/sdb1`
- Review configuration in `group_vars/all/main.yml`
