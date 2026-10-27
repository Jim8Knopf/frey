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

SSH on the **uplink** radio is opened only to networks named explicitly in
`security_baseline.firewall.ssh_control_sources`, which is empty by default.
The role used to infer this from the live Ansible connection and fell back to
"from anywhere" when it could not — see
[SSH Lockout Prevention](#ssh-lockout-prevention). Deployment is never cut off
by an empty list, because SSH is always allowed on the downstream interface and
FreyHub's `10.20.0.1` is the one address that never changes.

## Service Exposure

Traefik binds to `10.20.0.1`, not all interfaces. Docker services should not publish ports directly. Use Traefik labels instead.

## SSH Protection

Fail2ban is enabled for `sshd`.

### SSH Lockout Prevention

sshd is the only way into a Pi with no Ethernet port and no console, so it gets
treated as the critical service it is. On 2026-10-27 it stopped answering: the
port stayed open and the handshake completed, but every connection was closed
before the banner. That is invisible to a port check, affects every account at
once (no username is sent that early), and is unreachable by fail2ban, which
only ever sees authentication failures. Recovery meant pulling the NVMe.

The baseline now:

- refuses to generate a sourceless SSH rule on the uplink, and retracts the one
  earlier runs left behind;
- caps pre-auth connections per source (`PerSourceMaxStartups`) so one scanner
  cannot exhaust `MaxStartups` for everyone, and shortens `LoginGraceTime` so
  abandoned slots recycle;
- gives sshd `OOMScoreAdjust=-1000` and `Restart=always`;
- runs a watchdog that demands an actual SSH banner and restarts sshd if two
  probes ten seconds apart both fail;
- keeps journald persistent, so a repeat is diagnosable instead of being erased
  by the reboot that recovers the box.

Full detail, including the stock-value table and recovery steps, is in
[roles/security_baseline/README.md](../roles/security_baseline/README.md).

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
