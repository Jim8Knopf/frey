# service_proxy

Provides the local service foundation:

- Docker runtime with bounded JSON logs.
- Docker data root under `/opt/frey/docker`, intended for NVMe-backed systems.
- A shared Docker network, `frey_proxy`.
- Traefik listening on the private Frey LAN address only.

New Docker services should join `frey_proxy` and add Traefik labels. DNS is handled by the gateway wildcard, so a new service does not need a DNS change.

Docker assigns new automatically addressed networks a /24 from
`10.21.0.0/16`. This pool is separate from FreyHub's `10.20.0.0/24`;
explicitly configured networks keep their own subnets. Changing the pool does
not move existing Docker networks or the default `bridge`. Existing networks
must be recreated by their owning stack to receive a new subnet, which
interrupts their containers. Check for static addresses and dependencies before
recreating them; do not prune networks or remove volumes. In particular, an
older `local-ai_ai_private` network on `172.20.0.0/16` can capture the APNK
Library DNS servers at `172.20.1.15` and `172.20.1.16`. The legacy local AI
stack must be assessed and migrated separately if it is still present.

See [Adding Modules](../../docs/ADDING_MODULES.md) for service routing and authentication.
