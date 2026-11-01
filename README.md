# Frey

Ansible configures a Raspberry Pi 5 as the private network and service host in a
van. FreyHub runs on `wlan0`; `wlan1` supplies an optional public Wi-Fi uplink.
Local services and playback keep working offline.

Services use `https://<service>.hub.frey`. Old `<service>.frey` names redirect.
Install `ca/frey-root-ca.crt` on client devices for trusted HTTPS.

## Where to change things

All settings below live in `inventory/group_vars/all/`.

| File | Responsibility |
| --- | --- |
| `main.yml` | Shared paths, domains, trusted devices and ordered module registry |
| `network.yml` | AP, uplink, known networks and rollback settings |
| `system.yml` | NVMe, boot and journal settings |
| `security.yml` | Firewall, SSH and fail2ban |
| `proxy.yml` | Docker and Traefik |
| `identity.yml` | Accounts, groups and service access |
| `media.yml` | Storage, playback, acquisition switches and VPN |
| `monitoring.yml` | Metrics, logs, alerts, Grafana and Dockge switches |
| `images.yml` | Pinned container versions |
| `secrets.yml` | Ansible Vault encrypted credentials |

Roles contain implementation defaults, templates and tasks. Monitoring and
media acquisition have short `tasks/main.yml` entry points; follow their imports
to edit a particular part. Generated files under `/opt/frey` belong to Ansible.
The old stack in `archive/legacy-stack/` is reference-only.

## Stack layout

| Module | Owns |
| --- | --- |
| `network_gateway`, `rpi_nvme`, `security_baseline` | Network, host storage and access safeguards |
| `service_proxy`, `frey_pki`, `identity` | Docker, routing, certificates and login |
| `media_acquisition` | Downloads, *arrs, resolver and uplink gating |
| `media_library` | Playback, requests and library services |
| `wifi_portal`, `dashy` | Wi-Fi controls and service dashboard |
| `monitoring` | Metrics, logs, alerts, Grafana and Dockge |

The registry keeps dependencies ordered: proxy → PKI → identity, acquisition →
library, monitoring last. Acquisition stays separate because it can pause when
there is no uplink without interrupting playback.

## Deploy and check

```bash
ansible-galaxy install -r requirements.yml
ansible-vault edit inventory/group_vars/all/secrets.yml
ansible-playbook playbooks/site.yml --tags monitoring --check --diff > /tmp/frey-check.log 2>&1
ansible-playbook playbooks/site.yml --tags monitoring
ansible-playbook playbooks/site.yml --tags monitoring  # should report zero changes
scripts/monitoring-check.sh
```

Omit `--tags` for a full deployment. Use `media`, `identity`, `proxy`, `uplink`
or `hub` for focused changes. `--tags dockge` is an alias for the monitoring
module; switch Dockge off with `monitoring_enable.dockge: false`.

`ansible.cfg` supplies inventory and `.vault_pass`; keep that file local and
mode `600`. Override the target with `-e frey_host=<address>` if needed.

There is no Ethernet or console. Preserve network rollback and trusted-device
SSH exemptions. For first setup or radio changes, follow [GATEWAY](docs/GATEWAY.md).
Move storage before deploying services: [NVME_MIGRATION](docs/NVME_MIGRATION.md).

## Maintenance

- Edit image pins in `images.yml`, then deploy the owning module.
- Use Dockge at `dockge.hub.frey` for logs and restarts. Its stack files are
  read-only; make lasting changes in the roles.
- Run `scripts/identity-check.sh` after authentication changes and
  `scripts/monitoring-check.sh` after monitoring changes.
- Run `python3 scripts/check-repository-files.py` and
  `python3 -m unittest discover -s tests` for local repository checks.

See [IDENTITY](docs/IDENTITY.md), [MEDIA](docs/MEDIA.md),
[MONITORING](docs/MONITORING.md) and [ADDING_MODULES](docs/ADDING_MODULES.md).
CI runs syntax, shell, YAML/JSON and focused regression checks without the Pi.
