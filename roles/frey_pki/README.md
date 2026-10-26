# frey_pki

One private certificate authority, one wildcard-plus-explicit-names
certificate, no ACME and no extra container.

## Purpose

Issues the certificate Traefik serves for every `*.frey` and `*.hub.frey`
hostname, and renews it before it expires.

This exists because single sign-on is not optional-HTTPS. Authelia marks its
session cookie `Secure`, so a forward-auth service on plain HTTP would
authenticate, never get the cookie back, and bounce to the login page forever.
Authelia also flatly refuses plain-HTTP redirect URIs for public OIDC clients,
which is exactly what the Jellyfin SSO plugin needs.

## What It Produces

| Path | What | Mode |
| --- | --- | --- |
| `/opt/frey/pki/ca.key` | Root private key | `0600`, in a `0700` dir |
| `/opt/frey/pki/ca.crt` | Root certificate, 10 years | `0644` |
| `.../traefik/dynamic/certs/frey.{crt,key}` | Service certificate, 365 days | |
| `.../traefik/dynamic/tls.yml` | Makes it Traefik's default certificate | |
| `/opt/frey/pki-public/frey-root-ca.crt` | World-readable copy for containers to mount | |
| `/opt/frey/pki-public/container-init/` | Script that installs the CA into a container's trust store | |
| `./ca/frey-root-ca.crt` | Copy beside the playbook, for your devices | |

## Required Variables

From `inventory/group_vars/all/main.yml`:

- `frey.local_domain`, `frey.service_domain`, `frey.service_address`
- `frey.pki_public_dir`
- `service_proxy.traefik.dynamic_config_dir`

Optional: `identity_hostnames` — every name in the auth matrix. Absent, the
certificate is still correct, just shorter.

Needs `community.crypto`.

## Design Notes

### Why not step-ca

The old stack ran step-ca and had Traefik request a certificate per host over
ACME. It worked — 15 certificates were issued — but ACME needs step-ca to
resolve every `*.frey` name back to Traefik, which the old compose did with a
generated `extra_hosts` list, and the whole loop has to keep working while
parked with no internet. A single certificate signed offline by a local CA has
none of those moving parts and renews in one task.

### 365 days, not ten years

398 days is a hard ceiling: Apple rejects any TLS leaf valid longer than that,
**including one from a CA you installed yourself**. A ten-year leaf looks
tempting and then fails on every iPhone in the van. The role asserts
`valid_days <= 398`.

The root is ten years, because it is installed by hand on each device and
replacing it is the most annoying operation in this design.

### The wildcard is not relied on

`*.frey` and `*.hub.frey` are both in the certificate, but every hostname is
also listed explicitly — 49 of them at the time of writing. Under the Public
Suffix List's default rule an unknown TLD is itself a public suffix, which makes
`*.frey` a wildcard spanning a public suffix, and strict clients (Chrome
included) refuse to match those. The explicit names are what actually work; the
wildcards are a bonus for tolerant clients.

The name list builds itself from `frey.dns.records` and `identity_hostnames`,
under **both** domains. Add a service to the auth matrix and it lands in the
certificate on the next run — the signing request stops matching, so the
certificate is reissued.

### Two independent reasons to reissue

1. **The name list changed** — handled for free. `x509_certificate` reissues
   any certificate that no longer matches its request.
2. **Expiry is close** — *not* free. The module will happily leave a
   certificate that expires tomorrow in place, so the renewal window is checked
   with `x509_certificate_info`'s `valid_at` and forced explicitly.

### Making containers trust the CA

An app doing OIDC makes back-channel calls of its own — fetching the discovery
document, exchanging the code for a token — straight to `https://auth.hub.frey`
from inside its container. Those calls use the container's trust store, not a
browser's, and fail with an opaque TLS error otherwise.

linuxserver.io images run anything in `/custom-cont-init.d` as root before the
service starts, so a service module mounts `container-init/` plus
`frey-root-ca.crt` and gets a trusting container with no custom image. Jellyfin
does this. Non-linuxserver images need their own mechanism — Audiobookshelf is
Node, so it takes `NODE_EXTRA_CA_CERTS` instead.

`pki-public/` is a separate directory from `/opt/frey/pki/` on purpose: the
latter is `0700` because it holds the root private key, and no container should
ever be handed a path into it.

## Rotating

**The service certificate** rotates itself. Nothing to do.

**The root** is a deliberate act with a cost — every device needs the new one:

```bash
sudo rm /opt/frey/pki/ca.key /opt/frey/pki/ca.crt
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags pki --vault-password-file .vault_pass
```

## Validation

```bash
# What Traefik is actually serving
openssl s_client -connect 10.20.0.1:443 -servername auth.hub.frey \
  -CAfile ca/frey-root-ca.crt </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -dates -ext subjectAltName

# Renewal horizon
sudo openssl x509 -in /opt/frey/proxy/traefik/dynamic/certs/frey.crt \
  -noout -dates
```

A `--check` run on a host where `/opt/frey/pki` does not exist yet skips the
certificate tasks and says so: check mode cannot create the directory they
write into. A `--check` against a deployed Pi exercises them properly and will
tell you about an upcoming renewal.
