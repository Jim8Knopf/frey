# network_gateway

Runs **FreyHub**, the van's private access point, and opportunistically shares
a public Wi-Fi uplink through to it.

FreyHub is the critical always-on service. This role is written so the AP
serves clients fully with no uplink of any kind present.

## Radios

| Variable | Default | Role |
| --- | --- | --- |
| `network_gateway.downstream.interface` | `wlan0` | FreyHub AP — the reliable built-in radio |
| `network_gateway.upstream.interface` | `wlan1` | Public Wi-Fi uplink — the expendable USB radio |

Swapping those two values swaps the roles. The role asserts they differ; AP and
client mode on one radio is not supported.

## Required Variables

| Variable | Notes |
| --- | --- |
| `network_gateway.downstream.ap.ssid` | Defaults to `FreyHub` |
| `network_gateway.downstream.ap.password` | From vault; empty means an open AP. 8 char minimum |
| `network_gateway.downstream.ap.country` | Regulatory domain, applied before NetworkManager starts |
| `network_gateway.upstream.networks` | List of `{ssid, password, priority}`; may be empty |

No uplink SSID is required. Having no network to join is a normal state.

## Opportunistic Open Wi-Fi

`networks` can only cover SSIDs known in advance, because NetworkManager never
auto-connects to a profile that does not exist. `frey-uplink-autojoin.timer`
scans the uplink radio while it is down and joins the strongest genuinely open
network, which is what makes an undeclared campground or cafe work.

Declared networks always win (`autoconnect-priority: 1` for autojoined ones),
the AP radio is never touched, and a captive portal counts as success. Profiles
are named `frey-open-*` so the `frey-uplink-*` prune cannot delete them.

Disable with `network_gateway.upstream.autojoin_open.enabled: false`; see
`docs/GATEWAY.md` for the full rationale and the security trade-off.

## Tags

- `uplink` — uplink profiles only. Never touches the AP radio.
- `hub` — the AP, DHCP/DNS and NAT.
- `network`, `gateway` — everything.

## Safety

The role determines which interface carries the live SSH session from
`SSH_CLIENT`, not from the default route, and refuses to convert that radio
into an access point. Changes to the AP radio arm `frey-net-rollback.timer`,
which restores the previous network unless the run reaches its commit step.

Override only with a known-good way back in:

```yaml
network_gateway:
  safety:
    allow_reconfigure_control_interface: true
```

## Validation

```bash
nmcli device status
systemctl status dnsmasq frey-gateway-nat frey-regdomain
systemctl list-timers frey-net-rollback.timer
iptables -t nat -S | grep MASQUERADE
nmcli networking connectivity
```

See [../../docs/GATEWAY.md](../../docs/GATEWAY.md) for the migration procedure.
