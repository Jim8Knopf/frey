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

## Container-Side DNS: `traefik.network_aliases`

The gateway wildcard answers `*.frey` for FreyHub clients. It does **not**
answer for containers — those resolve through Docker's embedded resolver, which
knows container names and nothing else. A container calling a Frey hostname
therefore gets `Could not resolve host`, and aiming it at the gateway address
instead times out, because the firewall opens 443 on the downstream radio only
and a Docker bridge is not that interface.

`service_proxy.traefik.network_aliases` attaches extra DNS names to Traefik on
`frey_proxy`, so any container on that network can reach a service by its real
hostname, over TLS, with the certificate still valid.

It defaults to the Authelia hostname, because OIDC is the case that needs it:
an app logging in against Authelia makes a server-side call to the issuer for
discovery and token exchange, and that call fails without this even when the
app is configured perfectly. See `docs/IDENTITY.md`.

Only names Traefik already has a router for are worth adding — an alias is DNS,
not routing.
