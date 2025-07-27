# Project Improvements & TODOs

This is a list of potential improvements and next steps to make the project more robust and professional.

## 🚀 Next Steps

- [ ] **Enhance Security: Encrypt Passwords with Ansible Vault**
  - **Why?** To securely store sensitive data like passwords and safely manage the project in a Git repository.
  - **How?**
    1. Create an encrypted file: `ansible-vault create group_vars/secrets.yml`
    2. Move passwords from `group_vars/all.yml` there.
    3. Run playbook with `--ask-vault-pass`.

- [ ] **Complete Traefik Integration**
  - **Why?** To make all services accessible via easy-to-remember domains (e.g., `grafana.frey`) instead of IP addresses and ports.
  - **How?** Add Traefik labels (as already done for Jellyfin and Dockge) to the Docker Compose files of the remaining services (e.g., Grafana, Portainer, Sonarr, Radarr, etc.).

- [ ] **Optimize Backup Script**
  - **Why?** To reduce backup size and duration by excluding unnecessary cache directories.
  - **How?** Extend the backup script (`roles/backup/templates/backup.sh.j2`) with `--exclude` parameters for `tar`, e.g., for `appdata/jellyfin/cache`.

- [ ] **Enable HTTPS with Let's Encrypt**
  - **Why?** To encrypt all communication with the services. This is an advanced step that requires a publicly accessible domain and open ports (80/443).
  - **How?** Extend the Traefik configuration with a "Certificate Resolver" for Let's Encrypt.

- [ ] **Set Up System Notifications**
  - **Why?** To be proactively informed about system status, completed backups, or issues.
  - **How?** Add a service like `ntfy` or `gotify` and adapt the scripts (e.g., `backup.sh`, `health_check.sh`) to send a notification upon completion or failure.

- [ ] **Adapt Project Structure to Best Practices (Refactoring)**
  - **Why?** To make the project more maintainable, clearer, and scalable in the long term. A dedicated `ansible/` structure clearly separates the automation logic from the rest of the project management (like `deploy.sh`, `README.md`) and facilitates the integration of future tools (e.g., CI/CD, other scripts). It is a common convention that improves readability for you and others.
  - **How?**
    1. Create a new directory `ansible/` in the project's root directory.
    2. Move the following directories and files into the new `ansible/` folder:
        - `roles/`
        - `group_vars/`
        - `inventory/`
        - `playbooks/` (falls vorhanden)
        - `ansible.cfg`
        - `requirements.yml`
    3. Adapt the `deploy.sh` script to use the paths correctly (e.g., `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml`).

## 💡 Possible Enhancements (Maybe)

- [ ] **Optimize Media Library with Tdarr**
  - **Why?** To save storage space and standardize the media library by automatically converting videos to more efficient codecs (e.g., H.265/HEVC). Tdarr can also check file health.
  - **How?** Add Tdarr and a Tdarr-Node as Docker containers to the media stack and configure the libraries for processing.

- [ ] **Archive YouTube Channels with Tube-Archivist**
  - **Why?** To locally back up important videos from YouTube channels and make them accessible via Jellyfin, independent of online availability and ad-free.
  - **How?** Add Tube-Archivist as a Docker container and configure it with the desired channels or playlists.