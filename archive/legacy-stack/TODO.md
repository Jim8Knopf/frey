# Frey - Raspberry Pi 5 Hub Ansible Project

This is the structured and prioritized TODO checklist for the Frey project.

---

## 🔴 Critical Security & Stability (Do Now!)

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Encrypt all secrets with Ansible Vault | Hardcoded passwords and API keys are a security risk.                                    | ⬜️     |
|- [ ] Fix Deprecation Warnings              | Outdated modules may cause future errors.                                                | ⬜️     |
|- [ ] Remove hardcoded passwords            | Security vulnerability.                                                                  | ⬜️     |
|- [ ] **Create a separate `db` role**       | To manage PostgreSQL independently from services (start/stop/backup/update).          | ⬜️     |

---

## 🟡 High-Priority Refactoring (Do Next)

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Refactor project structure            | Improve maintainability and clarity.                                                     | ⬜️     |
|- [ ] Complete Traefik integration          | Ensure all services are accessible via Traefik with HTTPS.                               | ⬜️     |
|- [ ] Move variables to roles               | Make roles self-contained and reduce global variable clutter.                            | ⬜️     |
|- [ ] Add post-deployment health checks     | Prevent silent failures after deployment.                                                | ⬜️     |
|- [ ] Clarify DB strategy                   | Use a **single PostgreSQL instance** with separate schemas for each service.            | ⬜️     |
|- [ ] **Implement `db` role tasks**         | Create tasks for starting/stopping PostgreSQL, creating schemas, and managing backups.  | ⬜️     |
|- [ ] **Add `db_backup.yml` playbook**      | Automate PostgreSQL backups with rotation and remote storage.                          | ⬜️     |
|- [ ] **Implement shared `media` user/group** | Create a single `media` user/group (UID/GID 1000) for all media services.               | ⬜️     |
|- [ ] **Set permissions for media directory** | Ensure all services can read/write media files using the shared `media` user/group.   | ⬜️     |

---

## 🟢 Feature Enhancements (Plan for Next Iteration)

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Integrate Cockpit                     | Web-based management for the Raspberry Pi.                                               | ⬜️     |
|- [ ] Implement system notifications (ntfy) | Proactively monitor deployments and backups.                                             | ⬜️     |
|- [ ] Optimize media library with Tdarr     | Save storage space and standardize media formats.                                        | ⬜️     |
|- [ ] Archive YouTube channels (Tube-Archivist)| Local backup of important YouTube content.                                            | ⬜️     |
|- [ ] Test backup/restore strategy          | Ensure backups are functional and usable.                                                | ⬜️     |

---

## 🔐 Single Sign-On (SSO) and User Management

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] **Implement SSO user management**     | Create a single admin user with access to all services via Traefik/SSO.                | ⬜️     |
|- [ ] **Configure Traefik ForwardAuth for SSO** | Use Traefik ForwardAuth to integrate with an SSO provider (e.g., Authelia, OAuth2 Proxy). | ⬜️     |
|- [ ] **Create admin user with global access** | Define a single admin user in Traefik/SSO with access to all services.                | ⬜️     |
|- [ ] **Set up Authelia or OAuth2 Proxy**    | Deploy an SSO provider to manage user authentication and authorization.              | ⬜️     |
|- [ ] **Configure Traefik middleware**     | Add authentication middleware to all Traefik routes for SSO enforcement.                | ⬜️     |

---

## 📌 Technical Debt & Cleanup

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Update README.md                      | Reflect the current state of the project.                                                | ⬜️     |
|- [ ] Add input validation                  | Prevent misconfigurations and errors.                                                    | ⬜️     |
|- [ ] Improve error handling                | Make the project more robust.                                                            | ⬜️     |
|- [ ] Simplify network architecture         | Reduce complexity and improve performance.                                               | ⬜️     |

---

## 💡 Long-Term Ideas (Maybe/Someday)

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Add Umlautarr                         | Improve media library management.                                                        | ⬜️     |
|- [ ] Add automated testing                 | Ensure reliability and catch issues early.                                               | ⬜️     |
|- [ ] Add monitoring for services           | Proactively detect and resolve issues.                                                   | ⬜️     |

---

## 📝 Database Implementation Details

### **Single PostgreSQL Instance with Separate Schemas**
- **Why?** Saves resources on Raspberry Pi 5 while allowing independent management of services.
- **How?**
  1. Create a **dedicated `db` role** in `roles/db/` with tasks for:
     - Starting/stopping PostgreSQL container.
     - Creating schemas and users for each service (Jellyfin, Sonarr, Radarr, etc.).
     - Managing backups and restores.
  2. Add a **separate playbook `db.yml`** for DB-specific operations (backup, update, etc.).
  3. Add a **separate playbook `db_backup.yml`** for automated backups with rotation.

---

## 🔐 Single Sign-On (SSO) and User Management

### **Goal: Single Admin User with Global Access**
- **Why?** Avoid creating separate users for each service. Use a single admin user with access to all services via Traefik/SSO.
- **How?**
  1. **Set up Traefik ForwardAuth** to integrate with an SSO provider (e.g., Authelia, OAuth2 Proxy).
  2. **Define a single admin user** in the SSO provider with access to all services.
  3. **Configure Traefik middleware** to enforce authentication for all services.

### **Implementation Steps**
1. **Choose an SSO Provider** (e.g., Authelia, Keycloak, or OAuth2 Proxy).
2. **Configure Traefik ForwardAuth** in `traefik.yml`:
   ```yaml
   entryPoints:
     web:
       address: ":80"
       forwardAuth:
         address: "http://authelia:9091/api/verify"
         trustForwardHeader: true
   ```
3. **Add authentication middleware** to all Traefik routes:
   ```yaml
   http:
     middlewares:
       auth:
         forwardAuth:
           address: "http://authelia:9091/api/verify"
   ```
4. **Define the admin user** in your SSO provider (e.g., Authelia’s `users_database.yml`).
5. **Test access** to ensure the admin user can reach all services.

---

## 📁 Media User and Permissions

### **Shared `media` User/Group for All Services**
- **Why?** Simplify file permissions across Jellyfin, Sonarr, Radarr, etc.
- **How?**
  1. **Create a `media` user/group** on the host:
     ```bash
     sudo groupadd -g 1000 media
     sudo useradd -u 1000 -g media -d /opt/media -s /bin/false media
     ```
  2. **Configure Docker containers** to use the `media` user:
     ```yaml
     services:
       sonarr:
         user: "1000:1000"  # UID:GID of the media user/group
         volumes:
           - /path/to/media:/media
     ```
  3. **Set permissions** for the media directory:
     ```bash
     sudo chown -R media:media /path/to/media
     sudo chmod -R 775 /path/to/media
     ```

---

## ❓ Open Questions

- Should we use a single database for all services or multiple databases? **→ Single PostgreSQL with schemas.**
- How should the media user be handled across services? **→ Shared `media` user/group (UID/GID 1000).**
- Are there any other services or features we should prioritize?


note tool for whatever:
- notion
- logseq
- tana
- obsidian 


dialog neds to be instled somwher. is dependency for wifi tui