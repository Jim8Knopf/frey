# network_gateway

Runs the FreyHub access point, DHCP/DNS and NAT, and connects an optional Wi-Fi
uplink. The AP works offline. Settings are in `inventory/group_vars/all/network.yml`;
the AP password and known-network credentials come from the vault.

The built-in `wlan0` defaults to the AP and USB `wlan1` to the uplink; the
interfaces must differ. Open-network autojoin and the USB watchdog operate on
the uplink only. Captive-portal auto-accept is restricted to opted-in SSIDs.
See [GATEWAY](../../docs/GATEWAY.md) for configuration, portal behavior,
recovery, migration and verification.

Tags: `uplink` configures uplink profiles, `portal` the portal helper, `hub`
the AP/DHCP/DNS/NAT, and `network` or `gateway` the full role.

The role identifies the SSH control interface from `SSH_CLIENT` and refuses
to convert it to an AP. AP changes arm a rollback timer until the run commits.
Only override `network_gateway.safety.allow_reconfigure_control_interface`
when a known-good recovery path exists.
