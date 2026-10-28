# SSH access, and why the admin laptop is whitelisted

The Pi has no Ethernet port and no console. SSH over FreyHub is the **only**
way to reach it. A security mechanism that blocks SSH therefore does not
degrade this system, it bricks it until someone drives home — so SSH rate
limiting on this host is configured to protect the daemon's availability,
never to lock the owner out.

Two mechanisms have each done the latter.

## The two lockouts

Both present the identical, maddening symptom: **TCP connects, then closes
with no SSH banner.** `ssh` reports
`kex_exchange_identification: Connection reset by peer`, `nmap` calls the
port `tcpwrapped`, and ping, DNS, Jellyfin and every other service keep
working perfectly. Because the close happens before a username is ever sent,
every account is locked out at once, and no authentication failure is logged
— so `fail2ban` never sees an offender and cannot explain it either.

### 1. MaxStartups saturation (observed 2026-10-27)

Stock `MaxStartups 10:30:100` with `LoginGraceTime 120` means 100 abandoned
pre-auth connections hold port 22 shut for two minutes, and with
`PerSourceMaxStartups` unset **one** host can fill all 100 slots. Anything
opening connections faster than roughly 50/minute without completing
authentication locks the van out of its own Pi.

### 2. PerSourcePenalties (OpenSSH 9.8+, enabled by default)

This host runs OpenSSH 10.0p2 (Debian 13). `PerSourcePenalties` is on out of
the box:

```
persourcepenalties crash:90 authfail:5 noauth:1 grace-exceeded:10 \
  refuseconnection:10 max:600 min:15
```

Every short-lived connection that does not authenticate adds a penalty, up to
`max:600` — ten minutes. It is scoped to the **source address**, which is why
only the admin laptop goes dark while the rest of the network is fine. The
trap: **every further attempt, including a bare TCP port probe, renews the
penalty.** Poking at it to see if it has cleared is what turns a ten-minute
lockout into an hour of confusion.

A burst of `ansible-playbook` runs, or a handful of `ssh` one-liners, looks
exactly like the abuse this is designed to stop.

## The whitelist

`frey.trusted_devices` in `inventory/group_vars/all/main.yml` is the single
list of machines that must never be throttled, penalised or banned:

```yaml
frey:
  trusted_devices:
    - name: thinkpad
      mac: "b4:b5:b6:a7:57:c9"
      address: 10.20.0.10
      comment: "Admin laptop - the machine Ansible is driven from"
```

`security_baseline.trusted` widens that to whole networks — by default all of
FreyHub (`10.20.0.0/24`) — and `security_baseline.trusted.addresses` takes
one-off addresses that are not pinned devices.

Four layers honour the resulting list. Every one of them is a layer that
could otherwise lock you out:

| Layer | Setting | File |
|---|---|---|
| `sshd` penalties | `PerSourcePenaltyExemptList` | `/etc/ssh/sshd_config.d/10-frey-ssh-access.conf` |
| `sshd` auth budget | `Match Address` → `MaxAuthTries 20` | same |
| `fail2ban` | `ignoreip` | `/etc/fail2ban/jail.d/frey-sshd.local` |
| `ufw` | `allow proto tcp from <src> to any port 22` | runtime rules |

### Why exempting all of FreyHub is safe here

UFW opens port 22 on the **downstream interface only** and the uplink is
default-deny, so the only addresses that can reach `sshd` at all are the ones
on this list. On this host the penalty mechanism has no attacker to stop —
only an owner to lock out. Narrow `security_baseline.trusted.networks` to the
pinned addresses if port 22 is ever exposed upstream.

### The one limit that cannot be whitelisted

`PerSourceMaxStartups` is **not** a `Match`-block keyword — the listener
evaluates it before any `Match` can apply — so trusted devices cannot be
exempted from it. It is instead set to `60`, high enough that no real admin
use reaches it (`ansible.cfg` runs `forks = 2`, and pubkey auth vacates a
slot in milliseconds) while staying below the `MaxStartups` ceiling of `200`,
so one host still cannot saturate the daemon on its own.

## Fixed addresses

A whitelist of addresses is only meaningful if the addresses keep pointing at
the same machines, so `network_gateway` pins each trusted device by MAC in
dnsmasq:

```
dhcp-host=b4:b5:b6:a7:57:c9,10.20.0.10,thinkpad
```

These sit **outside** the DHCP pool (`10.20.0.50`–`10.20.0.150`) so a
reserved address can never also be handed to a passing phone. `expand-hosts`
is on, so `thinkpad.frey` resolves from anywhere on FreyHub as a bonus.

## Deploying a change

```bash
# The whitelist, the sshd policy, fail2ban and the firewall:
ansible-playbook playbooks/site.yml --tags security \
  --vault-password-file .vault_pass

# The DHCP reservations (restarts dnsmasq, so DHCP/DNS blip briefly):
ansible-playbook playbooks/site.yml --tags network \
  --vault-password-file .vault_pass
```

The sshd task cannot strand you. It renders the drop-in, validates the **full**
configuration with `sshd -t`, and on any error restores the previous file and
fails *without* notifying the reload handler — so the running daemon keeps the
config it already had and the live session is untouched. The reload itself is
a `HUP`, not a restart: the unit's `ExecReload` runs `sshd -t` first and
refuses a bad config, and `KillMode=process` means existing sessions survive.

Validate template changes offline first, without touching the Pi:

```bash
ansible-playbook playbooks/site.yml --tags security --check --diff \
  --vault-password-file .vault_pass
```

To trust another machine: get its MAC (`ip link show <iface>`), add an entry
to `frey.trusted_devices` with a free address below `.50`, and re-run with
`--tags network,security`.

## If you are locked out anyway

1. **Stop touching port 22.** Every attempt, a bare probe included, renews
   the penalty. This is the whole game.
2. Wait. The ceiling is `max:600`, so ten minutes from your *last* attempt.
3. Then connect once. If it works, deploy `--tags security` — the reload
   re-execs `sshd` and discards the entire in-memory penalty table, which
   clears any lockout in progress as a side effect.
4. If `fail2ban` banned you instead (a firewall `REJECT`, so it fails fast
   rather than hanging with no banner), that cannot be waited out from the
   laptop: `sudo fail2ban-client set sshd unbanip <ip>` from the Pi.

## Verifying it works

```bash
# What sshd actually believes, globally:
sudo sshd -T | grep -iE 'persourcepenaltyexemptlist|persourcemaxstartups|maxstartups'

# That the Match block applies to a trusted address and nobody else
# (expect 20, then 6):
sudo sshd -T -C addr=10.20.0.10,user=ansible,host=frey,laddr=10.20.0.1,lport=22 | grep maxauthtries
sudo sshd -T -C addr=203.0.113.9,user=ansible,host=frey,laddr=10.20.0.1,lport=22 | grep maxauthtries

sudo fail2ban-client get sshd ignoreip
sudo ufw status | grep 'trusted SSH'
```

Confirmed working on 2026-10-28: 40 consecutive no-auth connections from the
laptop — the exact pattern that caused the lockout — produced zero penalty
events in `journalctl -u ssh`, zero `fail2ban` bans, and `sshd` kept
answering with its banner immediately throughout.
