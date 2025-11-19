# DJI Mini 4 Pro → Immich Auto-Sync Setup Guide

This guide explains how to set up automatic photo syncing from your DJI Mini 4 Pro to Immich when you connect the drone/controller via USB to your Raspberry Pi.

## What This Does

When you connect your DJI controller or drone to your Raspberry Pi via USB cable:

1. 🔌 **Auto-detection** - System detects USB device
2. 📁 **Auto-mount** - Mounts the storage automatically
3. ☁️ **Upload** - Uploads all photos/videos to Immich
4. ✅ **Verify** - Skips duplicates (already uploaded files)
5. 📱 **Notify** - Sends notification when complete
6. 🔒 **Unmount** - Safely unmounts the device

**Result:** Your DJI photos are automatically backed up to Immich without any manual work!

## Quick Setup (5 Steps)

### 1. Generate Immich API Key

Open Immich in your browser and create an API key:

```
1. Go to: http://immich.frey (or http://10.20.0.1:2283)
2. Click your profile picture (top right) → Account Settings
3. Go to "API Keys" section
4. Click "New API Key"
5. Name it: "DJI Auto-Sync"
6. Copy the generated key (you'll need it next)
```

### 2. Add API Key to Secrets

On your computer (where you run Ansible), edit the secrets file:

```bash
ansible-vault edit group_vars/all/secrets.yml
```

Add this line (paste your actual API key):

```yaml
dji_sync_immich_api_key: "your-actual-api-key-from-step-1"
```

Save and exit.

### 3. Enable DJI Sync

Edit `group_vars/all/main.yml` and change:

```yaml
dji_sync:
  enabled: true  # Change from false to true
```

### 4. Deploy to Raspberry Pi

Run the Ansible playbook:

```bash
# Option A: Deploy only DJI sync (faster)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags dji_sync

# Option B: Deploy everything (if you made other changes)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

Wait for deployment to complete (~2-5 minutes).

### 5. Test It!

1. Connect your DJI RC 2 controller or DJI Mini 4 Pro to the Raspberry Pi via USB
2. Wait 10-30 seconds
3. Check Immich web UI - you should see photos appearing in "DJI Drone Photos" album
4. Disconnect when done!

## How to Use Daily

### Normal Workflow

After a flight:

1. **Connect USB** - Plug DJI controller/drone into Raspberry Pi USB port
2. **Wait** - Give it 30-60 seconds (longer for many photos)
3. **Check** - Open Immich and verify photos uploaded
4. **Disconnect** - Unplug USB cable

That's it! No buttons to press, no apps to open.

### Check Sync Status

**Option 1: Home Assistant** (if enabled)
- Look for MQTT notifications on topic `frey/dji/sync`
- Create an automation to notify you

**Option 2: SSH to Pi**
```bash
# Real-time sync logs
sudo journalctl -u dji-sync@* -f

# Recent activity
sudo journalctl -u dji-sync@* -n 50
```

**Option 3: Check Immich**
- Open Immich web UI
- Go to "DJI Drone Photos" album
- Verify recent photos are there

## Configuration Options

All settings are in `group_vars/all/main.yml` under `dji_sync:`.

### Useful Settings to Customize

**Change album name:**
```yaml
dji_sync:
  sync:
    target_album: "My Drone Photos"  # Default: "DJI Drone Photos"
```

**Delete photos after upload (⚠️ DANGEROUS):**
```yaml
dji_sync:
  sync:
    delete_after_sync: true  # Default: false (recommended!)
```

⚠️ **WARNING:** Only enable `delete_after_sync` if you:
- Have tested the sync process thoroughly
- Trust that your Immich backups are working
- Understand photos will be permanently deleted from the device

**Disable auto-unmount** (if you want to browse files manually):
```yaml
dji_sync:
  mount:
    auto_unmount: false  # Default: true
```

After changing settings, re-deploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags dji_sync
```

## Monitoring & Logs

### View Sync Logs

```bash
# SSH to your Pi
ssh user@frey.local

# Real-time logs
sudo journalctl -u dji-sync@* -f

# View sync history
ls -lh /var/log/dji-sync/

# Read latest sync log
cat /var/log/dji-sync/sync_*.log | tail -50
```

### Home Assistant Automation (Optional)

If you have Home Assistant enabled, create an automation:

```yaml
automation:
  - alias: "DJI Sync Notification"
    trigger:
      - platform: mqtt
        topic: "frey/dji/sync/status"
    action:
      - service: notify.mobile_app
        data:
          message: "{{ trigger.payload_json.message }}"
          title: "DJI Photo Sync"
```

## Troubleshooting

### Photos not uploading

**Check device detection:**
```bash
# SSH to Pi
lsusb  # Should show DJI device
dmesg | tail -20  # Check for USB events
```

**Manually trigger sync:**
```bash
# Find device (usually sdb1 or sdc1)
lsblk

# Trigger sync manually
sudo systemctl start dji-sync@sdb1.service

# Watch logs
journalctl -u dji-sync@sdb1 -f
```

### "Authentication failed" errors

Your API key might be wrong or expired.

**Fix:**
1. Generate new API key in Immich web UI
2. Update `group_vars/all/secrets.yml`
3. Re-deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags dji_sync`

### Sync is very slow

Normal speeds:
- 100 photos (~500MB): 30-60 seconds
- 500 photos (~2.5GB): 2-5 minutes

If slower:
- Use USB 3.0 ports (blue ports)
- Check Pi CPU usage: `htop`
- Verify good USB cable (try different cable)

### Device won't disconnect

```bash
# SSH to Pi
sudo umount /media/dji-sync/*
```

## What Gets Synced?

### Default Folders
- `DCIM/` - Standard DJI photos and videos
- `PANORAMA/` - Panoramic photos

### File Types
- **Photos:** `.JPG`, `.JPEG`, `.DNG` (RAW)
- **Videos:** `.MP4`, `.MOV`

### Duplicate Handling
Files are checked by hash - if already uploaded to Immich, they're skipped automatically.

## Alternative Sync Methods

If USB auto-sync doesn't fit your workflow, consider:

### 1. Immich Mobile App
- Transfer photos to phone via DJI Fly app
- Immich mobile app auto-uploads from phone
- **Pros:** Works anywhere
- **Cons:** Requires phone, uses phone storage

### 2. Manual Immich CLI
```bash
# SSH to Pi
immich upload /path/to/dji/photos --recursive --album "DJI Drone Photos"
```

### 3. Manual Web Upload
- Go to http://immich.frey
- Click Upload button
- Drag and drop photos

## Safety & Backup Tips

1. **Don't delete from SD card immediately** - Wait until verified in Immich
2. **Enable Immich backups** - See backup role documentation
3. **Test first** - Try with a few photos before trusting with whole flights
4. **Keep `delete_after_sync: false`** - Manual deletion is safer

## Performance & Storage

**Sync Speed:**
- USB 3.0: ~10-20 MB/s
- USB 2.0: ~3-5 MB/s

**Storage Requirements:**
DJI Mini 4 Pro photos:
- JPEG: ~5-8 MB each
- DNG (RAW): ~25-30 MB each
- 4K Video: ~100-150 MB per minute

Plan Immich storage accordingly (see `immich.services.immich.upload_location` in `main.yml`).

## Need Help?

**Check logs first:**
```bash
sudo journalctl -u dji-sync@* -n 100
```

**Manual test:**
```bash
sudo bash /usr/local/bin/dji-sync.sh /dev/sdb1
```

**Verify Immich CLI:**
```bash
immich --version
immich server-info
```

For more details, see `roles/dji_sync/README.md`.

---

## Summary

**What you did:**
1. ✅ Generated Immich API key
2. ✅ Added to secrets.yml
3. ✅ Enabled in main.yml
4. ✅ Deployed with Ansible

**What happens now:**
- Connect DJI device via USB → Photos automatically upload to Immich
- No manual steps needed
- Check Immich web UI to verify

**Next steps:**
- Test with a few photos first
- Set up Home Assistant notifications (optional)
- Configure automatic Immich backups (recommended)

Enjoy automatic drone photo backups! 🚁📸
