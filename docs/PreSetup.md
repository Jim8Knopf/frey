```bash
sudo adduser ansible 
sudo adduser ansible sudo
echo 'ansible ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/010_ansible-nopasswd
```

after the docker is installed

```bash
sudo adduser ansible docker
```

from your hoast: 
```bash
ssh-copy-id -i ~/.ssh/id_rsa_ansible frey
```
frey should be eighter desined in your ssh config or replace it with `ansible@<IP>`

# Raspberry Pi NVMe-Only Boot Setup

## Initial Setup
```bash
# Wipe NVMe and create GPT partitions
sudo wipefs -a /dev/nvme0n1
sudo parted /dev/nvme0n1 mklabel gpt
sudo parted /dev/nvme0n1 mkpart primary fat32 1MiB 513MiB
sudo parted /dev/nvme0n1 set 1 esp on
sudo parted /dev/nvme0n1 mkpart primary ext4 513MiB 100%

# Format partitions
sudo mkfs.vfat -F 32 /dev/nvme0n1p1
sudo mkfs.ext4 /dev/nvme0n1p2
```

## Copy System to NVMe
```bash
# Mount partitions
sudo mount /dev/nvme0n1p2 /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/nvme0n1p1 /mnt/boot

# Copy system files
sudo cp -a /bin /etc /home /lib* /opt /root /sbin /usr /var /mnt/ 2>/dev/null || true
sudo mkdir -p /mnt/dev /mnt/proc /mnt/sys /mnt/tmp /mnt/run /mnt/media
sudo cp -r /boot/firmware/* /mnt/boot/

# Add NVMe support
echo "dtparam=pciex1" | sudo tee -a /mnt/boot/config.txt
```

## Configure Boot
```bash
# Get partition UUIDs
sudo blkid /dev/nvme0n1p1
sudo blkid /dev/nvme0n1p2

# Update fstab (replace with actual PARTUUIDs)
sudo cp /etc/fstab /etc/fstab.backup
sudo sed -i 's|PARTUUID=OLD_SD_BOOT|PARTUUID=NEW_NVME_BOOT|' /etc/fstab
sudo sed -i 's|PARTUUID=OLD_SD_ROOT|PARTUUID=NEW_NVME_ROOT|' /etc/fstab

# Update cmdline.txt on NVMe boot
sudo sed -i 's|root=OLD_ROOT|root=PARTUUID=NEW_NVME_ROOT|' /mnt/boot/cmdline.txt

# Reload and test
sudo systemctl daemon-reload
sudo mount -a
```

## Configure Bootloader
```bash
# Update bootloader
sudo rpi-eeprom-update -a

# Set boot order to NVMe first
sudo -E rpi-eeprom-config --edit
```
**Change:**
```
BOOT_ORDER=0xf416
PCIEE_PROBE=1
```

## Final Steps
```bash
# Reboot to test
sudo reboot

# Verify boot from NVMe
mount | grep " / "
lsblk

# Remove SD card when confirmed working
sudo shutdown now
```

## Verification Commands
```bash
# Check boot source
mount | grep -E "( / | /boot )"

# Check partitions
lsblk

# Check bootloader config
vcgencmd bootloader_config

# Check partition UUIDs
sudo blkid
```

## Key Settings
- **Boot Order**: `0xf416` (NVMe → SD → USB)
- **PCIe Probe**: `PCIEE_PROBE=1`
- **Root**: NVMe partition 2
- **Boot**: NVMe partition 1

This setup allows complete boot from NVMe without SD card dependency.