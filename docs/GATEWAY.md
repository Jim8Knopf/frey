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
ansible-vault edit inventory/inventory/group_vars/all/secrets.yml --vault-password-file .vault_pass
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
