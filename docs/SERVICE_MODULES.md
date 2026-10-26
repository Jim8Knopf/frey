# Service Modules

Local service access is split into two layers:

- DNS: `network_gateway` resolves `*.frey` to the Pi.
- Routing: `service_proxy` routes each hostname to the correct Docker container.

Because DNS is wildcarded, new services do not need DNS edits. A service module only needs to attach to `frey_proxy` and add Traefik labels.

## Hostnames And Authentication

Services live at `<name>.hub.frey` (`frey.service_domain`), served over HTTPS.
`<name>.frey` still resolves and redirects there — see
[IDENTITY.md](IDENTITY.md) for why the domain has an extra label.

In practice each service gets three routers, which the `proxy_labels` macro in
the existing media modules generates for you:

| Router | Entrypoint | Does |
| --- | --- | --- |
| `<name>` | `websecure` | Serves the service. Carries `authelia@file` if protected. |
| `<name>-legacy` | `websecure` | Old `.frey` name → `to-canonical@file` |
| `<name>-http` | `web` | Serves directly if unprotected; redirects if protected |

A protected service **cannot** be served over plain HTTP: Authelia's session
cookie is `Secure`, so it would authenticate and then redirect to the login
page forever. An unprotected one keeps answering HTTP so that clients which
cannot install a private CA — televisions, consoles — keep working.

To put a service behind the login page, add one entry to `identity_services` in
`inventory/group_vars/all/identity.yml`. Nothing in the service changes.

## Minimal Docker Compose Pattern

```yaml
services:
  app:
    image: example/image:stable
    networks:
      - frey_proxy
    labels:
      traefik.enable: "true"
      traefik.docker.network: frey_proxy
      traefik.http.services.example.loadbalancer.server.port: "8080"

      # Canonical: HTTPS on the service domain. `tls=true` is all that is
      # needed - frey_pki installs the Frey certificate as Traefik's default,
      # so no service names a certificate of its own.
      traefik.http.routers.example.rule: Host(`example.hub.frey`)
      traefik.http.routers.example.entrypoints: websecure
      traefik.http.routers.example.tls: "true"
      # Append ,authelia@file to put it behind the login page.
      traefik.http.routers.example.middlewares: secure-headers@file

      # The old short name, redirected so bookmarks survive.
      traefik.http.routers.example-legacy.rule: Host(`example.frey`)
      traefik.http.routers.example-legacy.entrypoints: websecure
      traefik.http.routers.example-legacy.tls: "true"
      traefik.http.routers.example-legacy.middlewares: to-canonical@file
      traefik.http.routers.example-legacy.service: example

      # Plain HTTP on either name. Serve it directly only if the service is
      # NOT behind Authelia; if it is, use to-canonical@file here instead.
      traefik.http.routers.example-http.rule: Host(`example.hub.frey`) || Host(`example.frey`)
      traefik.http.routers.example-http.entrypoints: web
      traefik.http.routers.example-http.middlewares: secure-headers@file
      traefik.http.routers.example-http.service: example

networks:
  frey_proxy:
    external: true
```

Rather than writing this out, copy the `proxy_labels` macro from
`roles/media_acquisition/templates/docker-compose.yml.j2`. It takes the service
name and port, reads `identity_protect` to decide whether the service is
protected, and emits all three routers correctly.

## Module Checklist

- Store persistent data under `/opt/frey/appdata/<service>`.
- Join only the networks the service actually needs.
- Do not publish container ports directly unless there is a clear non-HTTP reason.
- Put secrets in `inventory/group_vars/all/secrets.yml`, not in role defaults.
- Add the module to `frey.modules.available` and then to `frey.modules.enabled`.

## Immich Hostname Example

When an Immich module is added, its web container should use labels equivalent to:

```yaml
traefik.enable: "true"
traefik.docker.network: frey_proxy
traefik.http.routers.immich.rule: Host(`immich.frey`)
traefik.http.routers.immich.entrypoints: web
traefik.http.routers.immich.middlewares: secure-headers@file
traefik.http.services.immich.loadbalancer.server.port: "2283"
```

No dnsmasq change is required because `immich.frey` matches the wildcard.
