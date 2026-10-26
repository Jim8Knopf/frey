# Service Modules

Local service access is split into two layers:

- DNS: `network_gateway` resolves `*.frey` to the Pi.
- Routing: `service_proxy` routes each hostname to the correct Docker container.

Because DNS is wildcarded, new services do not need DNS edits. A service module only needs to attach to `frey_proxy` and add Traefik labels.

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
      traefik.http.routers.example.rule: Host(`example.frey`)
      traefik.http.routers.example.entrypoints: web
      traefik.http.routers.example.middlewares: secure-headers@file
      traefik.http.services.example.loadbalancer.server.port: "8080"

networks:
  frey_proxy:
    external: true
```

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
