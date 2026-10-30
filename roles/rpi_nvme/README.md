# rpi_nvme

## Tuning (part of `site.yml`)

Conservative Raspberry Pi service-host tuning for an NVMe-backed install:

- Enables `fstrim.timer`.
- Installs NVMe and SMART tooling.
- Lowers swap tendency and VM cache pressure.
- Makes the journal persistent (Raspberry Pi OS pins it to RAM) and bounds its growth.
- Pins the NVMe out of its deepest power states, on the boot cmdline.
- Turns an NVMe that has stopped answering into a reboot rather than a wedge.

This assumes the system is **already** running from NVMe. It does not rewrite
`/etc/fstab` or touch the bootloader.

## The freeze this role exists to stop

The fitted drive is a **KLEVV CRAS C910 4TB**, a DRAM-less Realtek RTS5772DL.
It advertises two non-operational power states:

| state | power | enter | exit |
| --- | --- | --- | --- |
| `ps3` | 0.1500 W | 5 ms | 10 ms |
| `ps4` | 0.0050 W | 17 ms | 60 ms |

The kernel's default `nvme_core.default_ps_max_latency_us` is `100000`, which is
above `ps4`'s 77 ms round trip — so APST was free to park the drive in a
5-milliwatt state with a 60 ms wake-up, and this controller does not reliably
come back from it. When it does not, the drive leaves the PCIe bus:

```
nvme nvme0: controller is down; will reset: CSTS=0xffffffff, PCI_STATUS=0x10
```

`CSTS=0xffffffff` is a register read returning all-ones: nothing is answering.
Six of those inside 25 minutes were recovered by the kernel's own controller
reset. **When the reset also fails, the host does not crash — it wedges.**
Every process that touches the filesystem blocks forever, while systemd runs
from RAM and keeps petting the hardware watchdog, so the 1-minute watchdog
never fires and the Pi never reboots itself. It answers ping, refuses SSH
(`sshd` cannot read `authorized_keys`), and writes nothing to the journal —
because the journal is on the disk that just vanished. Only a power cut ends it.

That is why this looked like a software fault every single time, and why it cost
13 unsafe shutdowns in 19 power cycles.

**Two independent mitigations, deliberately:**

1. `nvme_core.default_ps_max_latency_us=0` forbids the deep states outright, and
   `pcie_aspm.policy=performance` disables L1 link power management, which is the
   other half of the same class of fault. Both are boot cmdline parameters, so
   **they need a reboot** — the role says so when it changes the line.
2. `kernel.hung_task_panic=1` + `kernel.panic=10` convert a wedge that gets past
   mitigation 1 into an automatic reboot in about two and a half minutes. This is
   the part that matters in a van: recovery stops requiring a human.

If a dropout still happens with both in place, in order: drop the link to
`dtparam=pciex1_gen=1` (signal integrity), **reseat the NVMe and its FFC ribbon**
— vibration is a real failure mode in a vehicle and `RxErr`/`BadTLP` on the link
would point there — and then treat the drive itself as suspect, since a
DRAM-less Realtek controller is a marginal choice for a Pi 5.

Check the count before blaming software:

```bash
sudo nvme smart-log /dev/nvme0n1 | grep -E 'unsafe_shutdowns|media_errors|critical_warning'
sudo journalctl -k --no-pager | grep -i 'controller is down'
```

The journal only survives a dropout if the controller reset succeeded, so the
absence of that line proves nothing. Loki keeps what journald lost.

You should not have to run either command to find out, though. SMART is blind
to this failure — wear, spare blocks and media errors all read perfectly clean
while the drive is falling off the bus every few minutes — so the `monitoring`
module counts the dropouts directly and alerts on them:

| Metric | Alert | Says |
| --- | --- | --- |
| `frey_nvme_controller_resets_total` | `FreyNvmeControllerReset` (critical) | the drive left the bus and the kernel reset it. Each one stalls host I/O for seconds, which from a sofa looks like Jellyfin buffering and invites you to blame a busy container instead |
| `frey_nvme_apst_max_latency_us` | `FreyNvmeApstEnabled` (warning) | the cmdline fix above is on disk but has not booted yet, so mitigation 1 is not actually in force |

That second one exists because a cmdline parameter only applies at boot: this
role can report `0 changed` on a Pi whose running kernel still has APST
enabled, which looks identical to a fixed one from the repo side. The metric
reads what the kernel is actually running, so the gap cannot hide.

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
