# Security Baseline

The active baseline is designed to expose services only on the Frey downstream LAN.

## Firewall

UFW defaults:

- Deny inbound.
- Allow outbound.
- Deny routed traffic except the explicit downstream-to-uplink gateway rule.

Allowed on the downstream interface:

- TCP 22 for SSH.
- TCP/UDP 53 for DNS.
- UDP 67 for DHCP.
- TCP 80/443 for Traefik.

The current Ansible SSH source is allowed on the active control interface so deployment does not cut off access.

## Service Exposure

Traefik binds to `10.20.0.1`, not all interfaces. Docker services should not publish ports directly. Use Traefik labels instead.

## SSH Protection

Fail2ban is enabled for `sshd`.

## Remaining Hardening To Consider

- Move SSH to key-only auth if the image still permits passwords.
- Add HTTPS with a local CA once client trust installation is planned.
- Add per-service authentication for sensitive dashboards.
