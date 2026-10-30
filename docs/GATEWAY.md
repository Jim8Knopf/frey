# FreyHub Gateway

FreyHub is the van's private network. It is the **critical always-on service**:
it is how you reach Immich, the media stack and SSH itself, with or without
any internet connection. Sharing public Wi-Fi is the opportunistic extra.

## Radio Assignment

| Purpose | Interface | Hardware | Why |
| --- | --- | --- | --- |
| FreyHub access point | `wlan0` | built-in Broadcom (`brcmfmac`) | Soldered down, best-proven AP driver on a Pi. Clients depend on it, so it gets the reliable radio. |
| Public Wi-Fi uplink | `wlan1` | Realtek RTL8821CU USB (`rtw88_8821cu`) | Expendable and intermittent. A USB reset costs you internet, never FreyHub. External antenna reaches distant hotspots. |

Both are set in `inventory/inventory/group_vars/all/main.yml`. Swapping the two
`interface:` lines swaps the roles — nothing else hardcodes a radio.

**Never run AP and client mode on one radio.** The role asserts the two
interfaces differ.

## Works With No Uplink

This is a hard design requirement, not a side effect:

- `dnsmasq` uses `bind-dynamic`, so it starts even when the AP radio has not
  appeared yet (cold boot, USB enumeration) and picks it up when it does.
- `*.frey` is answered locally, so service names resolve with no internet.
- The NAT unit is deliberately **not** ordered after `network-online.target`.
  Waiting for a target that will never come would delay every boot.
- Uplink profiles use `may-fail=true` and failure to associate is never fatal.
- There is no assert requiring an uplink SSID.

Clients will see a "connected, no internet" prompt when the van has no uplink.
Local services work normally; that notice is client-side behaviour.

## Captive Portals

You sign in **from a device on FreyHub**, not on the Pi. Because every client's
traffic leaves wearing the Pi's uplink address, authenticating the portal from
your phone authorises the Pi, and therefore everything behind it.

Two settings exist specifically to keep this working:

- `dns.stop_dns_rebind: false` — rebind protection discards DNS answers that
  point at private addresses, which is exactly how portals hand back their
  sign-in page. Turning it on breaks portal sign-in.
- `dns.upstream_servers: []` — empty on purpose. The uplink's own resolvers are
  used via `resolv-file`. Hardcoding `1.1.1.1`/`8.8.8.8` here makes portal
  interception a coin flip.

Check state with `nmcli networking connectivity`, which reports `portal`
distinctly from `full` and `none`.

## Adding Known Networks

Networks live in the vault so a rebuild reproduces them. NetworkManager joins
whichever is in range; none in range is a normal state.

```bash
ansible-vault edit inventory/group_vars/all/secrets.yml --vault-password-file .vault_pass
```

```yaml
vault_uplink_networks:
  - ssid: "Campground WiFi"
    password: ""          # empty = open or captive-portal network
    priority: 10
  - ssid: "Home"
    password: "secret"
    priority: 50          # higher wins when both are in range
```

Profiles are declarative: removing a network from this list deletes its
profile from the Pi on the next run.

## Joining Open Networks Nobody Declared

The list above can only ever cover SSIDs you knew about in advance, because
**NetworkManager never auto-connects to a network it has no profile for.** That
is the whole problem for a van: the campground, cafe or tourist car park you
parked next to today is an SSID you have never seen, so the uplink stays down —
and joining it by hand needs the uplink that is down.

`frey-uplink-autojoin.timer` closes that gap. Every couple of minutes, **only
while the uplink is down**, it scans the uplink radio, picks the strongest
genuinely open network and joins it.

```bash
systemctl status frey-uplink-autojoin.timer
journalctl -t frey-uplink-autojoin          # every decision it has made
```

The service only changes the uplink radio. NetworkManager handles declared
profiles; the selector chooses open networks when the uplink is disconnected.
It does not interrupt an existing connection just because a preferred network
appears. Remembered open profiles have NetworkManager autoconnect disabled, so
the selector can enforce its signal threshold, denylist and backoff every time.
Different SSIDs get distinct hashed profile names.

The service leaves connected networks alone even when internet checks fail,
so slow, filtered and captive networks have time to work. Frey's settings also
allow weak open networks and retry failed associations after two minutes. The
strongest eligible network is still tried first. This can leave Frey connected
to a hotspot that has no working internet; denylist it if needed. WEP and OWE
networks are not selected.

The role default is to disconnect managed networks after 15 minutes of
`limited` or `none` connectivity and back them off for 30 minutes. Set
`unusable_grace_seconds: 0` to disable that behavior, as Frey's inventory does.
Previously paused saved profiles are restored after their backoff or when the
feature is disabled.

A shared uplink address may allow all FreyHub clients to use a portal after one
client signs in, but each hotspot's rules differ.

For a read-only summary of interfaces, connectivity, routes, services and NAT:

```bash
sudo frey-gateway-check
```

Its profiles are named `frey-open-*`, deliberately **not** the
`frey-uplink-*` prefix — the prune step above deletes any `frey-uplink-*`
profile missing from `networks`, which would wipe these on every run.

Tune or disable in `inventory/group_vars/all/main.yml`:

```yaml
network_gateway:
  upstream:
    autojoin_open:
      enabled: true
      ssid_denylist:
        - "Pay Me WiFi"      # associates happily, never routes
```

Full set of knobs in `roles/network_gateway/defaults/main.yml`.

**The trade you are making:** auto-joining unknown open networks means the
van's traffic can leave through an AP you have not vetted, and an "evil twin"
is trivial to stand up. For an opportunistic media-box uplink that is usually
the right call, and it is why `ssid_denylist` exists. If it matters to you, put
a VPN on the uplink and treat the open network as transport only.

## Keeping the USB Radio on the Bus

The uplink is a USB adapter and it is the most droppable part of this machine.
When it falls off the bus **nothing can scan at all** — the AP radio is in
master mode and cannot scan — so the van loses every route to the internet and
the autojoin timer above has no radio to work with. The only recovery used to
be a power cycle, which needs somebody standing next to it.

**Why none of this can hurt FreyHub:** the AP is the built-in Broadcom radio on
SDIO, the uplink is USB. Different buses, different drivers.

```
wlan0 -> /sys/devices/platform/axi/1001100000.mmc/mmc_host/mmc1/...   (brcmfmac)
wlan1 -> /sys/devices/platform/axi/.../xhci-hcd.0/usb1/1-1/1-1:1.0    (rtw88_8821cu)
```

Every action below is scoped to one USB vendor:product or to the uplink netdev
by name, and the script refuses to run at all if the two interfaces are equal.

### Prevention

Two rtw88 module options, in `/etc/modprobe.d/frey-rtw88.conf`:

- `rtw88_usb switch_usb_mode=N` — the driver otherwise re-enumerates the
  adapter into USB 3 mode on **every boot**, which is that
  `usb 1-1: USB disconnect, device number 2` line in `dmesg`. The driver's own
  help text notes USB 3 mode also interferes with 2.4 GHz, and FreyHub is a
  2.4 GHz AP. The adapter negotiates 480 Mbps either way.
- `rtw88_core disable_lps_deep=Y` — deep power save is the usual reason an
  rtw88 USB adapter stops answering while still appearing on the bus.

Plus a udev rule pinning runtime PM off for the adapter, matched on
vendor:product rather than bus path, so it reapplies on every re-enumeration
instead of being whatever Raspberry Pi OS's `60-autosuspend.rules` decided.

Both module options need the driver reloaded, so **they apply on the next
reboot**.

### The USB Current Budget

A Pi 5 caps **total** USB draw at 600 mA until told the supply can take more.
This adapter alone declares `bMaxPower 500mA`, which leaves about 100 mA of
headroom for transmit spikes — and a browning-out adapter drops off the bus.

`usb_max_current_enable=1` raises the cap to 1.6 A and is the real fix, so it
is a knob and **it is off by default**:

```yaml
network_gateway:
  upstream:
    usb_resilience:
      raise_usb_current_limit: true   # only with a supply that can deliver it
```

It is off because it is only safe with a supply that genuinely delivers 1.6 A
(the official 27 W unit). On a marginal supply it lets the Pi pull itself into
a brownout, and this machine has already recorded 12 unclean shutdowns — the
exact failure that corrupts the \*arr and Jellyfin SQLite databases. Needs a
reboot. Check `vcgencmd get_throttled` (want `0x0`) after enabling it.

### Recovery

`frey-uplink-usb-watchdog.timer` checks every 60 s and escalates only as far as
it has to:

| Level | Action |
| --- | --- |
| 1 | Bounce the interface (`ip link down`/`up`) |
| 2 | `usbreset <vendor:product>` — port-level reset of just this adapter |
| 3 | Unbind and rebind the driver, re-running probe |
| 4 | `modprobe -r` / `modprobe` the driver |

```bash
journalctl -t frey-uplink-usb-watchdog     # every decision and recovery
```

What it deliberately does not do:

- **Act on a disconnected radio.** NetworkManager state 30 ("disconnected") is
  the *normal* state when no known network is in range. Treating it as a fault
  would reset the radio every minute while parked somewhere remote. Only a
  missing USB device, a missing netdev, or state 20 ("unavailable" — on the bus
  but not answering) counts as broken.
- **React to a blip.** It needs `failures_before_action` consecutive bad checks
  (default 2) before touching anything.
- **Reset in a loop.** `cooldown_seconds` between attempts and
  `max_actions_per_hour` overall, so a genuinely dead or unplugged adapter is
  left alone instead of being reset forever.

The ladder resets to level 1 as soon as the uplink is healthy again, so the
next real fault starts from the cheapest action.

## The Deadman Rollback

This Pi has **no Ethernet port and no console**. The only ways in are the two
radios, so every change to the AP radio arms a deadman switch first.

1. Before the AP radio is touched, the current config is backed up and
   `frey-net-rollback.timer` is armed.
2. The run applies the AP config and verifies the interface actually took
   `10.20.0.1`.
3. Only then does it write the commit marker and disarm the timer.

If the run dies, your session drops, or the AP never comes up, the timer fires
and restores the previous network — and it fires again after a reboot, so
power-cycling a stranded Pi also recovers it.

Tune or disable in `inventory/inventory/group_vars/all/main.yml`:

```yaml
network_gateway:
  safety:
    rollback:
      enabled: true
      timeout_seconds: 600
```

## Netplan Handover

This image ships netplan with the NetworkManager renderer, and
`/etc/NetworkManager/system-connections/` is empty — every profile is
netplan-generated. Left alone, netplan regenerates competing profiles for the
same radio on every boot and fights the AP for it.

The role backs netplan's config up to `/var/lib/frey/netplan-disabled/` and
removes its claim on the AP radio only. The uplink radio is left alone, so a
phase-1 run can never disturb the session riding it.

## Two-Phase Migration

Needed once, when moving from "SSH arrives on wlan0" to the layout above.
Each phase touches only the radio **not** carrying your session.

### Phase 1 — put the uplink on wlan1 (zero risk)

wlan0 is never opened, so your session cannot drop.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags uplink --vault-password-file .vault_pass
```

Then confirm wlan1 joined and note its address:

```bash
ssh ansible@<current-pi-address> "nmcli -t -f DEVICE,STATE,CONNECTION device status; ip -br addr show wlan1"
```

### Phase 2 — convert wlan0 into FreyHub

**Move your SSH session to wlan1's address first.** The role refuses
otherwise, because it detects which interface your session actually rides.

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags hub -e frey_host=<wlan1-address> --vault-password-file .vault_pass
```

Join `FreyHub` from a phone or laptop and SSH to `10.20.0.1` to confirm.

### Afterwards

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e frey_host=10.20.0.1 --vault-password-file .vault_pass
```

## Verification

On the Pi:

```bash
nmcli device status
nmcli -f GENERAL.STATE,GENERAL.CONNECTION device show wlan0
ip -br addr
systemctl status dnsmasq frey-gateway-nat frey-regdomain
systemctl list-timers frey-net-rollback.timer      # should be inactive once committed
iptables -t nat -S | grep MASQUERADE
nmcli networking connectivity                       # full | portal | none
```

From a device joined to FreyHub:

```bash
ping 10.20.0.1
nslookup immich.frey 10.20.0.1
curl -I http://frey
```

## Regulatory Domain

`frey-regdomain.service` sets the domain before NetworkManager starts, so the
AP cannot land on a channel the domain then forbids. Set to `NZ`.

FreyHub is pinned to a **non-DFS** channel on purpose: DFS channels require a
radar check during which the AP goes silent, which is a common cause of an
access point that mysteriously stops broadcasting.

- `band: bg`, `channel: 6` — 2.4 GHz. Widest client support, carries through a
  van body better. Current default.
- `band: a`, `channel: 36` — 5 GHz, non-DFS in NZ. Roughly treble the
  throughput for media streaming at shorter range. Switch once the AP has
  proven stable.
