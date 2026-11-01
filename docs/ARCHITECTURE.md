# Architecture

`playbooks/site.yml` loads enabled roles in the order declared in
`inventory/group_vars/all/main.yml`. That file contains shared settings and the
module registry; adjacent vars files group operational settings by responsibility.

## Ownership

- **Host:** `network_gateway` owns FreyHub, uplink, DHCP/DNS and NAT;
  `rpi_nvme` owns storage tuning; `security_baseline` owns firewall and SSH safeguards.
- **Access:** `service_proxy` owns Docker and Traefik; `frey_pki` owns certificates;
  `identity` owns the directory, SSO and service access policy.
- **Media:** acquisition owns downloading and uplink-dependent work; library owns
  playback and requests. Both share one data tree so imports can use hardlinks.
- **Interfaces:** `wifi_portal` handles uplink selection; `dashy` lists services.
- **Operations:** `monitoring` owns metrics, logs, alerts, Grafana and Dockge.

Keep these boundaries: changing acquisition must not interrupt offline playback;
changing a service must not require reconfiguring the access point.

## Dependencies and paths

Deploy proxy → PKI → identity before protected services; acquisition before
library for shared API keys; monitoring last to observe deployed services.

Compose files live under `/opt/frey/stacks`, persistent application data under
`/opt/frey/appdata`, and media under `/opt/frey/data`. Ansible owns generated
files. Dockge mounts stack definitions read-only and shares monitoring's Compose
project while retaining its existing appdata directory.

FreyHub DNS resolves `frey` and its subdomains locally. Traefik routes
`<service>.hub.frey`; old short names redirect. New services need proxy labels
and an identity policy, not per-service DNS changes. Containers use bridge
networks; firewall rules deliberately restrict direct access to host services.

The active vault is `inventory/group_vars/all/secrets.yml`. Archived roles and
vaults under `archive/legacy-stack` are never loaded by the active playbook.

See [SERVICE_MODULES](SERVICE_MODULES.md), [IDENTITY](IDENTITY.md),
[MEDIA](MEDIA.md), [MONITORING](MONITORING.md) and [SSH_ACCESS](SSH_ACCESS.md).
