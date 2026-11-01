# Moving Frey's Root Filesystem to NVMe

The goal: run entirely from the M.2 NVMe drive so the SD card can be removed.

## What `rpi_nvme` Does And Does Not Do

`roles/rpi_nvme` (run as part of `site.yml`) is **tuning only**:
`fstrim.timer`, `nvme-cli`/`smartmontools`, VM tuning, journal size limits.
It assumes the system is already NVMe-backed.

Moving the install is a separate, destructive, one-shot job:
`playbooks/nvme_migrate.yml`. It is deliberately not in `site.yml`, because
imaging a disk is not configuration management.

## Why Clone Rather Than Re-image

This Pi has no console and no Ethernet. Re-imaging the NVMe would need
physical access, so the migration clones the running SD install across and
flips the bootloader's preference.

**Run this before deploying services.** Cloning a live root filesystem is fine
on a fresh install, but once Immich or Postgres are writing, an rsync snapshot
is not consistent and you risk a corrupt database on the clone.

## Safety Model

- The **SD card is never written to.** It remains a complete, bootable fallback.
- Boot order is currently **`0xf461` — SD first, then NVMe**, set in
  `inventory/group_vars/all/system.yml`. Nibbles read right-to-left:
  `1` = SD, `6` = NVMe, `4` = USB, `f` = restart.

  **While the SD card is inserted the Pi always runs from the card**, so the
  NVMe clone sits idle. Recovery from a bad NVMe boot is therefore "leave the
  card in", with nothing to configure under pressure.

  Two ways to actually run from NVMe:

  1. **Remove the SD card.** The bootloader falls through to NVMe. Keep the
     card as your rescue image.
  2. **Switch to `0xf416`** (NVMe, then SD) to prefer NVMe while leaving the
     card in as an automatic fallback:

     ```yaml
     rpi_nvme:
       migrate:
         boot_order: "0xf416"
     ```

     ```bash
     ansible-playbook -i inventory/hosts.yml playbooks/nvme_migrate.yml \
       --tags bootorder --vault-password-file .vault_pass
     ```

  Note that `0xf416` fallback only covers a missing *boot* partition. If the
  kernel loads but cannot mount the NVMe *root*, the Pi stops there rather
  than falling back — which is precisely why SD-first is the safer default
  until NVMe boot has been proven once.
- Re-running is safe: the play stops cleanly if root is already on NVMe.
- It refuses to wipe a target that already holds partitions unless forced.
- It refuses to run at all without an explicit confirmation variable.

## Layout Created

| Partition | Size | Filesystem | Mount |
| --- | --- | --- | --- |
| `nvme0n1p1` | 512 MiB | FAT32 (`bootfs`) | `/boot/firmware` |
| `nvme0n1p2` | remainder | ext4 (`rootfs`) | `/` |

GPT, not MBR: the drive is 3.6 TiB and MBR cannot address beyond 2 TiB. The
Pi 5 bootloader reads GPT.

PARTUUIDs are generated at partition time, discovered during the run, and
written into the clone's `/etc/fstab` and `cmdline.txt`. Nothing is hardcoded,
so a rebuild on different hardware still works.

## Procedure

Dry run first — every destructive step is skipped, guards still execute:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/nvme_migrate.yml \
  -e nvme_migrate_confirm=yes --check --vault-password-file .vault_pass
```

Then for real:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/nvme_migrate.yml \
  -e nvme_migrate_confirm=yes --vault-password-file .vault_pass
```

If the NVMe already holds partitions, add `-e nvme_migrate_force_wipe=yes`.
**All data on the target is lost.**

### The boot order takes two reboots

`rpi-eeprom-config --apply` does not write the EEPROM immediately. It stages
`pieeprom.upd` on the boot partition, and the bootloader flashes it on the next
boot. So:

1. **First reboot** still comes up on the SD card, flashes the new EEPROM, and
   reboots itself automatically.
2. **Second boot** comes up on NVMe.

`sudo rpi-eeprom-config` always reports the *live* EEPROM, so it will keep
showing the old `BOOT_ORDER` until that flash has happened. This is expected,
not a failed run.

Applying only the boot order, without re-running the migration:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/nvme_migrate.yml \
  --tags bootorder --vault-password-file .vault_pass
```

That task also **cancels a stale staged EEPROM image** when the live boot order
already matches what the config asks for, so a previously staged change cannot
silently flash a boot order nobody wants on the next reboot.

Reboot, then verify:

```bash
findmnt -n -o SOURCE /          # expect /dev/nvme0n1p2
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
df -h /
sudo rpi-eeprom-config | grep BOOT_ORDER
```

With SD-first boot order, `findmnt` will keep reporting `mmcblk0p2` — that is
correct and expected. Removing the SD card is what moves you onto NVMe.

Keep the card somewhere safe: it is a bootable snapshot of the pre-migration
system, and with SD-first ordering it is also your one-step recovery.

Once you are genuinely running from NVMe, set `require_nvme_root: true` in
`inventory/group_vars/all/system.yml` so later rebuilds refuse to deploy service
data onto the SD card.

## After Migration

`/opt/frey/docker` (set by `service_proxy`) and `/opt/frey/appdata` land on
NVMe automatically, because the whole root filesystem is now NVMe. That is
what `docs/ARCHITECTURE.md` assumes.

Swap stays on `zram` (compressed RAM) rather than moving to disk, which avoids
pointless NVMe write wear.

## Bootloader EEPROM Firmware

Separate from boot order, and off by default:

```yaml
rpi_nvme:
  migrate:
    update_eeprom_firmware: true
```

Your Pi reports a pending bootloader update. Newer bootloaders improve NVMe
boot handling, so applying it is usually worthwhile — but it is a firmware
flash, so do it as its own step once NVMe boot is confirmed working, not in the
same run as the migration.

## A Cleaner Path For Future Rebuilds

Once you have physical access to the drive, the simpler story is to image the
NVMe directly with Raspberry Pi Imager and run `site.yml` against it. Then no
migration is needed and `rpi_nvme` does what it was designed for: tuning a
system that is already NVMe-backed.
