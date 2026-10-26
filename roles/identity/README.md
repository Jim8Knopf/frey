# identity

LLDAP + Authelia. The directory of people, the login page, and the forward-auth
endpoint Traefik asks about everything that cannot log in for itself.

User-facing documentation is [docs/IDENTITY.md](../../docs/IDENTITY.md). This
file is about the role.

## Purpose

| Container | Job | Footprint |
| --- | --- | --- |
| `lldap` | User directory, LDAP on 3890, web UI on 17170 | ~20 MB |
| `authelia` | OIDC provider and forward-auth endpoint, 9091 | ~100 MB |

Deliberately no Postgres and no Redis. Authelia keeps sessions, TOTP secrets
and OIDC consents in SQLite on the NVMe; that is a small amount of data and not
worth two more containers that have to come back cleanly after a power cut.

## Required Variables

All in `inventory/group_vars/all/identity.yml`:

- `identity_versions` — pinned image tags
- `identity_enable` — which of the two run
- `identity_hosts` — `auth` and `directory` short names
- `identity_users`, `identity_groups` — who exists
- `identity_services` — the auth matrix
- `identity_protect`, `identity_hostnames` — derived; do not hand-edit

Also needs, from `inventory/group_vars/all/main.yml`:

- `frey.service_domain` — **must contain a period.** Asserted by the role.

## Dependencies

- `frey_pki` must run first. The role fails with an explanation if
  `.../traefik/dynamic/certs/frey.crt` is absent, because SSO over plain HTTP
  cannot work.
- `service_proxy` provides `secure-headers@file` and `to-canonical@file`, and
  the Traefik instance the forward-auth middleware is installed into.
- `community.docker` and `community.crypto`.

Module order in `frey.modules.enabled` matters: `frey_pki` → `identity` →
media. A Traefik router naming a middleware Traefik does not know about is
dropped **entirely**, so the service 404s with a perfectly healthy container.

## Tags

| Tag | What it does |
| --- | --- |
| `identity`, `sso` | Everything |
| `identity_config` | Secrets, config, bootstrap — no image pulls |
| `identity_jellyfin` | Just reprint the Jellyfin plugin values |

## How It Is Kept Declarative

Authelia's whole state is one rendered YAML file: render, validate, restart.
LLDAP's users and groups are JSON files applied by LLDAP's own idempotent
`/app/bootstrap.sh`. Nothing calls an API, nothing reconciles a database, and a
second run reports zero changes.

### The configuration file contains no secrets

Every secret is read at startup from a file in `/secrets` by Authelia's own
`secret` template filter, enabled with `X_AUTHELIA_CONFIG_FILTERS=template`.
So the file you actually read and edit — clients, access rules, policies — is
safe to show in `--check --diff`. Only the OIDC client *hashes* appear in it,
and a hash is not a secret.

The compose file is the exception and is `no_log` + `0640`: LLDAP takes its
secrets as environment variables.

### Validation before restart

`authelia validate-config` runs in a throwaway container against the real
rendered file, the real secrets and the pinned version, **before** the running
Authelia is asked to reload anything. Authelia's schema moves between minor
releases, so a bad config fails the deploy with a precise error instead of
leaving you with a login page that will not start — and therefore no way into
anything.

This guard has already earned its place twice during development: once on a
YAML indentation fault, once on an empty client secret.

## Gotchas Worth Knowing

**`authelia healthcheck` does not exist.** Use `/app/healthcheck.sh`, which the
image ships. The subcommand form gives a container that is permanently
unhealthy while working perfectly.

**LLDAP must start as root.** Its entrypoint chowns its own files and then
drops to `UID`/`GID`. Setting `user:` in compose makes that chown fail with
`Operation not permitted` and the container restart-loops before it ever
listens. Authelia is the opposite — it is started directly as the pinned uid.

**Authelia binds to LDAP before it serves.** The account it binds with is
created by the LLDAP bootstrap, so the role starts LLDAP, waits, seeds it, and
only then starts Authelia. Starting both together gives a crash loop with
`LDAP Result Code 49 "Invalid Credentials"` that only resolves because of
`restart: unless-stopped`.

**Do not put a `{# Jinja comment #}` on its own line inside an indented block
in the config template.** Ansible renders with `trim_blocks` on, the newline
after the closing marker is eaten, and the next line's indentation is appended
to the previous line. That produced a 16-space `client_secret` under an 8-space
`public` and a YAML error eighty lines further down. Keep commentary in the
header blocks.

**`refresh_token` needs `offline_access`.** Authelia warns, and says it will
later refuse, if a client is granted the `refresh_token` grant without
`offline_access` among its allowed scopes.

**The cookie domain needs a period.** See
[docs/IDENTITY.md](../../docs/IDENTITY.md). This is why services live at
`*.hub.frey`.

## Adding An OIDC App

Two steps, in two places, and the split is the point:

1. **`identity.oidc_catalog`** in `defaults/main.yml` — facts about the app:
   redirect URIs, scopes, whether it can keep a secret, whether it needs a
   claims policy to get groups into the ID token.
2. **`identity_services`** in `identity.yml` — whether it is on, and who may
   use it.

The role asserts that any service set to `auth: oidc` has a catalog entry, so a
missing one fails with an explanation rather than rendering a broken client.

Clients for Immich, Grafana and Mealie are already in the catalog but not
enabled. The day those modules land, SSO is waiting for them.

## Jellyfin

The plugin config is **not** templated, and that is deliberate — see
[docs/IDENTITY.md](../../docs/IDENTITY.md). Short version: the maintained fork
is tested on Jellyfin 12.0–12.2, this runs 12.3, and its config schema is
undocumented outside its own source. A guessed schema would give a plugin that
loads, claims to be configured, and authenticates nobody.

Authelia's side is complete. `--tags identity_jellyfin` reprints the four
values to paste in.
