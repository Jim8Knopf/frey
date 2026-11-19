# Security baseline

The role configures UFW, SSH and fail2ban. UFW denies inbound and routed
traffic by default, allows outbound traffic and permits downstream-to-uplink
routing. On the downstream interface it allows SSH (TCP 22), DNS (TCP/UDP 53),
DHCP (UDP 67), and Traefik (TCP 80/443). It preserves the current Ansible SSH
path. Traefik binds to `10.20.0.1`; services should use proxy labels instead of
publishing ports directly.

## SSH access

The Pi has no Ethernet or console. `frey.trusted_devices` in
`inventory/group_vars/all/main.yml` and `security_baseline.trusted` supply
exemptions for sshd penalties and authentication limits, fail2ban and UFW.
`tasks/trusted_sources.yml` resolves these sources and can be included separately.
The role validates the complete sshd configuration and restores the previous
file on error before any reload. See [SSH access](../../docs/SSH_ACCESS.md) for
lockout recovery, deployment and verification.

## Service access

`frey_pki` issues Traefik's certificate; clients must trust
`ca/frey-root-ca.crt`. Protected services redirect HTTP to HTTPS because
Authelia uses secure cookies. Unprotected services can still use HTTP for
clients that cannot install the CA. See [PKI](../frey_pki/README.md) and
[identity](../../docs/IDENTITY.md) for certificates and access policy.

The *arr `/api`, `/feed` and `/ping` paths bypass the login redirect but require
an API key. `media_acquisition.auth.required` must remain `Enabled`: otherwise
Servarr can waive the key for private addresses, including requests via Traefik.
