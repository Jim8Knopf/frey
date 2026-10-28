# rpi_nvme

## Tuning (part of `site.yml`)

Conservative Raspberry Pi service-host tuning for an NVMe-backed install:

- Enables `fstrim.timer`.
- Installs NVMe and SMART tooling.
- Lowers swap tendency and VM cache pressure.
- Makes the journal persistent (Raspberry Pi OS pins it to RAM) and bounds its growth.

This assumes the system is **already** running from NVMe. It does not rewrite
`/etc/fstab` or touch the bootloader.

## Migration (`tasks/migrate.yml`, separate playbook)

Moving root from the SD card to NVMe is a destructive, one-shot operation and
lives in its own entry point:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/nvme_migrate.yml \
  -e nvme_migrate_confirm=yes --vault-password-file .vault_pass
```

It partitions the target (GPT: 512 MiB FAT32 + ext4 remainder), clones the
running root and firmware partitions, rewrites the clone's `fstab` and
`cmdline.txt` with the newly generated PARTUUIDs, and sets the bootloader to
`BOOT_ORDER=0xf416` (NVMe, then SD, then USB).

The SD card is never written to and stays a bootable fallback. The play stops
cleanly if root is already on NVMe, and refuses to wipe a target holding
partitions unless `force_wipe` is set.

See [../../docs/NVME_MIGRATION.md](../../docs/NVME_MIGRATION.md).
