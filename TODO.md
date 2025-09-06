# Project Improvements & TODOs

This is a list of potential improvements and next steps to make the project more robust and professional.

## 🚀 High-Priority Tasks

- [ ] **Encrypt All Secrets with Ansible Vault**
  - **Why?** To securely store all sensitive data (passwords, API keys) and safely manage the project in a public Git repository. This is the most critical security improvement.
  - **How?**
    1. Create an encrypted file: `ansible-vault create group_vars/secrets.yml`.
    2. Move all secrets from `group_vars/all.yml` to the new `secrets.yml`.
    3. Update playbooks to reference the vaulted variables.
    4. Run playbooks with `--ask-vault-pass`.
  - **AI Prompt:** "Encrypt all sensitive data in `group_vars/all.yml` using Ansible Vault. Create a new `group_vars/secrets.yml` file, move all passwords and API keys there, and update all roles and templates to use the new variables from the vault file."

- [ ] **Complete Traefik Integration & Enable Internal HTTPS**
  - **Why?** To make all services accessible via easy-to-remember domains and to encrypt all internal traffic, even without a public domain.
  - **How?** Add Traefik labels to all remaining services. Configure Traefik to use self-signed certificates for all internal services.
  - **AI Prompt:** "Add Traefik labels to all services in the `docker-compose-*.yml.j2` files that do not have them yet. Then, modify the Traefik static configuration (`traefik.yml.j2`) to enable a self-signed certificate provider and apply it to all routers by default."

- [ ] **Adapt Project Structure to Best Practices (Refactoring)**
  - **Why?** To make the project more maintainable, clearer, and scalable in the long term by separating automation logic from project management files.
  - **How?**
    1. Create a new directory `ansible/`.
    2. Move `roles/`, `group_vars/`, `inventory/`, `playbooks/`, `ansible.cfg`, and `requirements.yml` into it.
    3. Adapt the `deploy.sh` script to use the new paths.
  - **AI Prompt:** "Refactor the project structure. Create a new `ansible/` directory and move the `roles`, `group_vars`, `inventory`, `playbooks`, `ansible.cfg`, and `requirements.yml` directories/files into it. Then, update the `deploy.sh` script to correctly call `ansible-playbook` with the new paths."

  - [ ] **one ore multiple DBs**
  - [ ] media user everywhere?

## 📈 Next Level Enhancements

- [ ] **Refine Variable Scoping**
  - **Why?** To make roles more self-contained and reusable, and to clean up the global `group_vars/all.yml` file.
  - **How?** Move default variable definitions (like ports) from `group_vars/all.yml` to `roles/ROLENAME/defaults/main.yml` for each role.
  - **AI Prompt:** "Refactor the Ansible variables for the `media_stack` role. Create a `roles/media_stack/defaults/main.yml` file and move all default port definitions (e.g., `jellyfin_port`, `sonarr_port`) from `group_vars/all.yml` into it. The values in `group_vars/all.yml` should only be present if they override the default."

- [ ] **Implement System Notifications**
  - **Why?** To be proactively informed about system status, completed backups, or deployment issues.
  - **How?** Add a service like `ntfy` and adapt the `deploy.sh` and `backup.sh` scripts to send notifications on success or failure.
  - **AI Prompt:** "Integrate `ntfy` into the project. Add a new role to deploy `ntfy` as a Docker container. Modify the `deploy.sh` and `backup.sh` scripts to send notifications via a POST request to a configured `ntfy` topic on success and failure."

- [ ] **Add Post-Deployment Health Checks**
  - **Why?** To automatically verify that all services are running correctly after a deployment, preventing silent failures.
  - **How?** Add a new task block at the end of `playbooks/site.yml` that uses the `ansible.builtin.uri` module to check the HTTP status of each service's web endpoint.
  - **AI Prompt:** "Add a new task block to the end of `playbooks/site.yml` named 'Verify Service Health'. Use the `ansible.builtin.uri` module to send a GET request to the main page of each deployed service (e.g., `http://jellyfin.{{ domain_name }}`) and assert that the response status is 200."


## 💡 Possible Enhancements (Maybe)

- [ ] **Optimize Media Library with Tdarr**
  - **Why?** To save storage space and standardize the media library by automatically converting videos to more efficient codecs (e.g., H.265/HEVC). Tdarr can also check file health.
  - **How?** Add Tdarr and a Tdarr-Node as Docker containers to the media stack and configure the libraries for processing.

- [ ] **Archive YouTube Channels with Tube-Archivist**
  - **Why?** To locally back up important videos from YouTube channels and make them accessible via Jellyfin, independent of online availability and ad-free.
  - **How?** Add Tube-Archivist as a Docker container and configure it with the desired channels or playlists.

- [ ] **Implement and Test Backup & Restore Strategy**
  - **Why?** To ensure that backups are not just created, but are also valid and usable for a full recovery. A backup that hasn't been tested is not a backup.
  - **How?** Create a new Ansible playbook or role to automate the restoration of a key service (e.g., Jellyfin) from a backup onto a clean state. Document the process.
  - **AI Prompt:** "Create a new Ansible role named `restore`. This role should contain tasks to stop a service, wipe its configuration volume, and restore the data from the latest backup created by the `backup` role. Start with Jellyfin as the first service to support and make the role tag-based."

- [ ] fix this:
```bash
[WARNING]: Deprecation warnings can be disabled by setting `deprecation_warnings=False` in ansible.cfg.
[DEPRECATION WARNING]: community.general.yaml has been deprecated. The plugin has been superseded by the the option `result_format=yaml` in callback plugin ansible.builtin.default from ansible-core 2.13 onwards. This feature will be removed from collection 'community.general' version 12.0.0.
```
- [ ] add cockpit
- [ ] umlautarr


❌ Security vulnerabilities (hardcoded passwords)
❌ Missing input validation
❌ Incomplete error handling
❌ Network architecture could be simplified