# service_proxy

Provides the local service foundation:

- Docker runtime with bounded JSON logs.
- Docker data root under `/opt/frey/docker`, intended for NVMe-backed systems.
- A shared Docker network, `frey_proxy`.
- Traefik listening on the private Frey LAN address only.

New Docker services should join `frey_proxy` and add Traefik labels. DNS is handled by the gateway wildcard, so a new service does not need a DNS change.

Example labels for `immich.frey`:

```yaml
labels:
  traefik.enable: "true"
  traefik.docker.network: frey_proxy
  traefik.http.routers.immich.rule: Host(`immich.frey`)
  traefik.http.routers.immich.entrypoints: web
  traefik.http.routers.immich.middlewares: secure-headers@file
  traefik.http.services.immich.loadbalancer.server.port: "2283"
networks:
  - frey_proxy
```
