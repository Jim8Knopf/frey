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

### APST was not the whole story — corrected 2026-11-01

The account above was the diagnosis as of 2026-10-29, and it is now known to be
incomplete. The van wedged again on 2026-11-01 **with APST already off and
proven off**:

```
# nvme get-feature /dev/nvme0n1 -f 0x0c -H
  Autonomous Power State Transition Enable (APSTE): Disabled
```

The running kernel's cmdline carried `nvme_core.default_ps_max_latency_us=0`
and `pcie_aspm.policy=performance`, and the drive was genuinely not entering
`ps3`/`ps4`. It still produced **eight `controller is down` events in twelve
minutes**, each recovered by a reset, with:

```
nvme0n1: I/O Cmd(0x2) @ LBA 4789774464, 256 blocks, I/O Error (sct 0x3 / sc 0x71)
```

`sct 0x3 / sc 0x71` is *Path Related Status / Transient Transport Error*. Over
the same window SMART stayed immaculate — 0 media errors, 0 error-log entries,
0 % wear, 40 °C, `throttled=0x0`. So the fault is the **PCIe transport**, not
the NAND, not heat and not power, and "APST, fixed" is no longer a sufficient
explanation. The kernel's `Does your device have a faulty power saving mode
enabled?` line is generic boilerplate printed on every controller reset — it is
not a diagnosis, and it misled this investigation twice.

Note also that the wedged boot trained at **`5.0 GT/s PCIe x1`**, not 2.5: the
`pciex1_gen=1` line was in `config.txt` but the Pi had not rebooted since it was
written, so **Gen 1 had never actually been in effect for a single fault.** A
cmdline or `config.txt` setting that is correct on disk is not a setting the
kernel is running — which is why all of these are exported as metrics.

### Cures, and separately, recovery

These are two different things and the distinction matters. The cures try to
stop the link failing. Recovery only decides what happens *after* it fails, so
it is the fallback, never the answer — a van that reboots itself every few hours
is not a fixed van.

**Cures, in cost order. Change ONE at a time:** this is an intermittent fault,
so altering several variables at once buys a quiet week and no knowledge of
which one bought it.

| # | Change | Cost | State |
| --- | --- | --- | --- |
| 1 | `nvme_core.default_ps_max_latency_us=0` | a fraction of a watt at idle | applied; APSTE confirmed Disabled, **did not prevent the fault** |
| 2 | `pcie_aspm=off` + `pcie_port_pm=off` | idle power only, no throughput | **applied 2026-11-01**, untested against a fault |
| 3 | `dtparam=pciex1_gen=1` | halves link bandwidth (~250 MB/s) | in `config.txt` since 2026-10-31 but **only in effect since the 2026-11-01 reboot**, untested against a fault |
| 4 | `rpi_nvme.hmb.disable` → `nvme.max_host_mem_size_mb=0` | sustained random-write performance | **held in reserve** |
| 5 | Reseat the NVMe and its FFC ribbon | hands on hardware | not done |
| 6 | Replace the drive | money | not done |

Steps 2 and 3 are the kernel's own suggestion and have never faced a fault, so
**the ladder is not exhausted and hardware is not yet indicated.** Step 2 went
in before step 3's downgrade would be judged, because it costs no bandwidth;
if the van proves stable, step 3 is the one to try removing first to get the
bandwidth back.

Step 5 is where this stops being a software problem. `DevSta: CorrErr+
FatalErr+` on the endpoint, a transport-error signature, and a cable that lives
in a moving vehicle all point at signal integrity. Re-check
`/sys/bus/pci/devices/0001:01:00.0/aer_dev_*` before and after reseating.

**Recovery — the fallback, not the fix:**

1. `kernel.hung_task_panic=1` + `kernel.panic=10` convert a wedge into an
   automatic reboot in about two and a half minutes. This is the part that
   matters in a van: recovery stops requiring a human.
2. `tune2fs -e panic` on the root filesystem covers the fault the one above
   cannot see. **`hung_task_panic` only fires when a task BLOCKS**, and on
   2026-11-01 the drive returned errors instead of hanging: nothing blocked,
   nothing panicked, and the Pi sat reachable-by-ping and answering nothing
   until the power was cut. The superblock was on the kernel's oldest default,
   `Continue`, which never panics *and* lets ext4 write through a fault. With
   `panic` the error reaches the panic path and `kernel.panic=10` reboots.
   Set on the superblock rather than in `/etc/fstab` — the root line says
   `defaults`, which carries no `errors=` option, so the superblock is what
   the kernel actually uses, and it applies from the first mount. Like the
   cmdline, **it only takes effect at the next boot**.

Each of the three is measured rather than assumed, because all three can be
correct on disk while the running kernel has none of them: `frey_nvme_apst_max_latency_us`,
`frey_kernel_hung_task_panic` / `frey_kernel_panic_reboot_secs`, and
`frey_root_fs_error_behaviour`, with `FreyNvmeApstEnabled`,
`FreyWedgeRecoveryDisarmed` and `FreyRootFsErrorsNotFatal` to say so.

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
