# Repository Guidelines

## Project Structure & Module Organization

Frey is an Ansible project that configures a Raspberry Pi 5 as a private van
network; the desired state of that host is the deliverable. `playbooks/site.yml`
loads enabled modules from the registry in `inventory/group_vars/all/main.yml`.
Roles live in `roles/<module>/` with the usual `tasks/`, `defaults/`,
`templates/`, `files/`, and `handlers/` layout. Day-to-day module settings live
in `inventory/group_vars/all/{identity,media,monitoring}.yml`; host inventory is
`inventory/hosts.yml`. `archive/legacy-stack/` is reference-only and must not be
used by active roles. See `docs/ADDING_MODULES.md` before creating a module.

## Build, Test, and Development Commands

- `ansible-galaxy install -r requirements.yml` installs required collections.
- `ansible-playbook playbooks/site.yml` deploys all enabled modules; use
  `--tags media` or `--limit <host>` to narrow scope.
- `ansible-playbook playbooks/site.yml --check --diff` previews changes. In an
  agent session, redirect its output to a file (for example,
  `> /tmp/deploy.log 2>&1`) before reading it.
- `ansible-vault edit inventory/group_vars/all/secrets.yml` safely edits
  encrypted configuration. `ansible.cfg` already supplies inventory and vault
  password settings.
- Run the relevant acceptance check after deployment:
  `scripts/monitoring-check.sh`, `scripts/identity-check.sh`, or
  `scripts/media-check-updates.sh`. Use `git-hooks/test-pre-commit.sh` to test
  the vault hook.

## Coding Style & Naming Conventions

Use two-space YAML indentation, no tabs, and one document per file. Use
`snake_case` variable names and imperative Ansible task names, such as
`Configure Traefik labels`. Keep roles idempotent. Place module-local defaults
in `roles/<module>/defaults/main.yml`; reserve `main.yml` for the module
registry and settings shared by multiple modules. Keep feature toggles in vars
files and secrets only in the Vault-encrypted `secrets.yml`. Pin container image
versions; never use `:latest`.

## Testing & Safe Deployment

Run a focused dry run, deploy the affected tag, then repeat the deployment: the
second run should report zero changes. Confirm behavior with the matching check
script rather than only checking that containers started. `network_gateway`,
`security_baseline`, firewall, and SSH changes are high-risk because the Pi has
no Ethernet or console; preserve rollback and trusted-device safeguards. Never
edit generated files under `/opt/frey/` directly.

## Commits, Pull Requests, and Security

Use Conventional Commits, for example `feat(monitoring): add relay check` or
`fix(network_gateway): retain uplink radio`. Name branches `<type>/<slug>` and
base work on `new`, not `main`. PRs should describe the affected roles/tags,
link the issue where applicable, document before/after behavior, and include
deployment logs or service evidence.

Never commit plaintext secrets or `.vault_pass`; keep the latter local with
mode `600`. Enable repository hooks with
`git config core.hooksPath git-hooks && chmod +x git-hooks/*`.
