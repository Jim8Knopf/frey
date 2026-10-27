# security_baseline

Applies the minimum security layer for the modular Frey host:

- UFW default-deny inbound policy.
- DNS, DHCP, HTTP, HTTPS, and SSH allowed on the downstream Frey LAN.
- Routing allowed from downstream LAN to the Wi-Fi uplink.
- SSH on the uplink opened only to explicitly known sources.
- Fail2ban enabled for SSH.
- Conservative network sysctl hardening.
- SSH lockout prevention (below).

The reverse proxy still binds only to `10.20.0.1`, so services are not intentionally exposed on the public Wi-Fi uplink.

## Required Variables

Everything has a default in `defaults/main.yml`. The one worth setting
deliberately is:

```yaml
security_baseline:
  firewall:
    # CIDRs allowed to reach SSH on the UPLINK radio. Empty means SSH is
    # reachable on FreyHub only, which is the safe default.
    ssh_control_sources: ["192.168.1.0/24"]
```

## SSH Lockout Prevention

### What happened

On 2026-10-27 the Pi stopped accepting SSH. The port stayed open and the
TCP handshake completed, but sshd closed every connection *before sending
its banner*. From outside that is indistinguishable from a healthy daemon
— `nmap` reports the port as `tcpwrapped`, and `ss -ltn` sees a normal
listener. Because the close happens before any username is transmitted,
every account was locked out at once; keys, passwords and PAM were all
irrelevant. The box has no Ethernet port and no console, so recovery meant
physically pulling the NVMe and booting the SD card to mount it offline.

The root cause could not be proven after the fact: journald was volatile,
so the logs died with the reboot that recovered the machine. The mechanism,
however, is not in doubt. sshd's stock limits were:

| Setting                | Stock value  | Effect |
| ---------------------- | ------------ | ------ |
| `MaxStartups`          | `10:30:100`  | every new connection dropped once 100 unauthenticated ones are in flight |
| `LoginGraceTime`       | `120`        | each unauthenticated connection holds a slot for two minutes |
| `PerSourceMaxStartups` | unset        | a single host can fill all 100 slots alone |

Anything opening SSH connections without completing authentication at more
than ~50/minute therefore locks the owner out, and fail2ban cannot help:
MaxStartups throttling writes no authentication-failure line, so the jail
never sees an offender to ban.

What made the Pi reachable by such a flood was a bug in this role. The
control-source detection fell back to `any` whenever `SSH_CLIENT` was
missing from the gathered facts — the normal case under `become` with
pipelining — which produced a live rule of:

```
-A ufw-user-input -i wlan1 -p tcp --dport 22 -j ACCEPT
```

No source restriction, on the *uplink* radio: SSH open to every stranger
on whatever campground or public Wi-Fi the van parked beside.

### What prevents it now

1. **No wildcard SSH rule can be generated.** An undetectable control path
   writes no uplink rule at all and warns; an assertion fails the run
   rather than emitting `any`. Opening SSH to an uplink network is only
   possible by naming CIDRs in `ssh_control_sources`.
2. **The legacy wildcard rule is retracted** on the next run, since UFW
   rules are additive and fixing the generator does not withdraw what it
   already wrote.
3. **sshd is hardened against pre-auth floods** — `PerSourceMaxStartups`
   caps any single source, `LoginGraceTime` recycles abandoned slots four
   times faster, and `MaxStartups` gets more headroom.
4. **sshd survives memory pressure and crashes** — `OOMScoreAdjust=-1000`
   and `Restart=always`.
5. **A watchdog restarts sshd if it stops answering.** It insists on
   seeing the banner, because the failure keeps the port open and any
   TCP-connect check would call it healthy. Two probes ten seconds apart
   are required before it acts.
6. **The journal is persistent**, so a repeat leaves evidence instead of
   dying with the recovery reboot.

### Validation

```bash
# The limits that matter
ansible frey -i inventory/hosts.yml -b -m shell \
  -a "sshd -T | grep -iE 'maxstartups|logingracetime|persourcemax'"

# SSH must appear on the downstream radio ONLY
ansible frey -i inventory/hosts.yml -b -m shell -a "ufw status verbose"

# Watchdog is armed
ansible frey -i inventory/hosts.yml -b -m shell \
  -a "systemctl list-timers frey-ssh-watchdog.timer"

# Watchdog history, if it ever fired
ansible frey -i inventory/hosts.yml -b -m shell \
  -a "journalctl -t frey-ssh-watchdog --no-pager | tail -20"
```

### Recovering from a lockout anyway

The AP is the address that never changes: join FreyHub and the Pi is
`10.20.0.1`. If sshd itself is wedged, power-cycle — the watchdog starts
probing three minutes after boot. If that still fails, insert the SD card
(boot order `0xf461` prefers it), boot from it, and mount the NVMe root to
read `/var/log/journal` — which now survives reboots.
