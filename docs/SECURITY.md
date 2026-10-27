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

## HTTPS

`frey_pki` runs a private CA on the Pi and issues the certificate Traefik
serves for every `*.frey` and `*.hub.frey` name. The root is valid ten years;
the leaf is 365 days and renews itself once inside a 30-day window. Devices
need the root installed once — `ca/frey-root-ca.crt`.

Not forced globally. Services behind the login page are HTTPS-only and their
HTTP routers redirect, because Authelia's session cookie is `Secure` and would
never come back over plain HTTP. Services with no auth in front of them —
Jellyfin, Audiobookshelf, Seerr — still answer HTTP, because a television
cannot install a private root certificate and gives you no way to click
through. Flip `service_proxy.traefik.redirect_http_to_https` once every device
that matters trusts the CA.

See [frey_pki/README.md](../roles/frey_pki/README.md).

## Service Authentication

`identity` runs LLDAP and Authelia. Fourteen hostnames that previously had
either their own weak login or none at all now sit behind single sign-on:

- **Forward auth** — Traefik asks Authelia before the request reaches the
  service. Twelve hostnames, including every *arr, qBittorrent, Jellystat and
  Maintainerr. Maintainerr had no authentication whatsoever and can delete
  media.
- **OIDC** — Jellyfin and Audiobookshelf log in against Authelia themselves.

Who may reach what is one `groups` list per service in
`inventory/group_vars/all/identity.yml`. Authelia's own brute-force regulation
is separate from, and additional to, the fail2ban that watches sshd.

On the *arr services, `/api`, `/feed` and `/ping` are exempt from the session
check, because an API client cannot answer a redirect to a login page and the
media wiring drives those APIs through the proxy. Those paths demand an
`X-Api-Key` instead, which is why `media_acquisition.auth.required` is pinned
to `Enabled` — Servarr's default waives the key for private source addresses,
and everything arriving through Traefik has one. The UI itself still requires a
session even when a valid API key is presented.

See [docs/IDENTITY.md](IDENTITY.md).

## Remaining Hardening To Consider

- Move SSH to key-only auth if the image still permits passwords.
- Force HTTPS everywhere once every client device trusts the Frey CA.
- Consider `two_factor` for the acquisition stack; TOTP is already enrollable
  per person, and it is one word per service in `identity.yml`.
