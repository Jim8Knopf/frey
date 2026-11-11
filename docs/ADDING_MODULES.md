# Adding Modules

A module is an Ansible role with a narrow responsibility and explicit defaults.

## Contract

Each module should provide:

- `roles/<module>/defaults/main.yml` with safe defaults.
- `roles/<module>/tasks/main.yml` as the entry point.
- `roles/<module>/README.md` with purpose, required variables, and validation commands.
- Tags matching the module name and domain, for example `[media, jellyfin]`.

## Register A Module

Add it to `inventory/group_vars/all/main.yml`:

```yaml
frey:
  modules:
    enabled:
      - network_gateway
      - example_module
    available:
      example_module:
        role: example_module
        tags:
          - example
```

## Recommendations

- Keep one module to one operational concern.
- Put module-specific variables in role defaults first.
- Keep only cross-module choices in `inventory/group_vars/all/main.yml`.
- Do not make modules depend on archived roles.
- Prefer compose-file modules for services, but keep networking, storage, and security as separate modules.
- For web services, use `frey_proxy` plus Traefik labels rather than editing DNS.

## Web services

FreyHub DNS resolves `*.frey` to the Pi; connect services to `frey_proxy`
and use Traefik labels rather than adding DNS entries. Services use HTTPS at
`<name>.hub.frey`, with the old `<name>.frey` name redirected. Copy the
`proxy_labels` macro from `roles/media_acquisition/templates/docker-compose.yml.j2`
to generate canonical HTTPS, legacy and HTTP routers. Protected services must
redirect HTTP to HTTPS because Authelia uses secure cookies; unprotected
services may serve HTTP for clients that cannot trust the Frey CA. Configure
protection in `identity_services` in `inventory/group_vars/all/identity.yml`.

Store persistent data under `/opt/frey/appdata/<service>`, join only required
networks, avoid publishing ports unless needed, and keep secrets in the vault.
See [IDENTITY](IDENTITY.md) for access policy.
