# Repository Guidelines

## Project Structure & Module Organization
- `playbooks/`: Entry points (e.g., `site.yml`) orchestrating all roles via tags.
- `roles/`: Service stacks and system roles (infrastructure, media, automation, monitoring, wifi, security, etc.).
- `inventory/hosts.yml`: Target hosts; update for your Raspberry Pi.
- `group_vars/all/`: Main config (`main.yml`) and encrypted secrets (`secrets.yml`).
- `templates/`, `docs/`, `scripts/`, `git-hooks/`: Jinja templates, documentation, maintenance utilities, and repo hooks.

## Build, Test, and Development Commands
- Install deps: `ansible-galaxy install -r requirements.yml` (role collections).
- Full deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml`.
- Selective deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media`.
- Dry run + diff: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff`.
- Edit secrets: `ansible-vault edit group_vars/all/secrets.yml` (use `.vault_pass`).
- Common ops (Pi): `docker ps`, `docker logs -f <svc>`, `docker compose restart` in `/opt/frey/stacks/<stack>`.

## Coding Style & Naming Conventions
- YAML: 2‑space indentation, no tabs; one document per file.
- Ansible: snake_case variables; task names are imperative (“Configure Traefik labels”).
- Roles: standard layout (`roles/<name>/{tasks,templates,files,handlers,vars}`); idempotent tasks only.
- Files/vars: prefer `group_vars/all/main.yml` for toggles; secrets live only in `secrets.yml` (Vault‑encrypted).

## Testing Guidelines
- Validate locally with `--check --diff`; then run targeted tags (e.g., `--tags infrastructure`).
- Verify idempotency: second run reports 0 changed tasks.
- Limit blast radius: use `--limit <host>` and small, focused PRs.
- Provide evidence in PRs: command output or deployment log snippets.

## Commit & Pull Request Guidelines
- Commit style: Conventional Commits (e.g., `feat(wifi): improve roaming`, `fix(vault): encrypt secrets`).
- Don’ts: never commit plaintext secrets; `.vault_pass` must be local and `chmod 600`.
- PR checklist: clear description, linked issue, scope (tags/roles touched), before/after behavior, logs or screenshots (e.g., service URL working), and docs updates if user‑facing.
- Enable hooks: `git config core.hooksPath git-hooks && chmod +x git-hooks/*` (auto‑encrypt prompts for `secrets.yml`).

## Security & Configuration Tips
- Keep feature toggles in `group_vars/all/main.yml`; rotate credentials in Vault.
- Use `--check` for review, then apply; prefer `--tags` for incremental changes.
- Service configs and stacks live under `/opt/frey/`; avoid manual edits that fight Ansible.

