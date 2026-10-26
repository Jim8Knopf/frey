# security_baseline

Applies the minimum security layer for the modular Frey host:

- UFW default-deny inbound policy.
- DNS, DHCP, HTTP, HTTPS, and SSH allowed on the downstream Frey LAN.
- Routing allowed from downstream LAN to the Wi-Fi uplink.
- Current Ansible SSH path preserved during deployment.
- Fail2ban enabled for SSH.
- Conservative network sysctl hardening.

The reverse proxy still binds only to `10.20.0.1`, so services are not intentionally exposed on the public Wi-Fi uplink.
