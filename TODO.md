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

### **Example Structure**
```
ansible/
├── roles/
│   ├── db/
│   │   ├── tasks/
│   │   │   ├── main.yml      # Start PostgreSQL, create schemas/users
│   │   │   ├── backup.yml    # Backup tasks
│   │   │   └── restore.yml   # Restore tasks
│   │   ├── templates/      # PostgreSQL configuration
│   │   └── defaults/
│   │       └── main.yml    # Default DB variables (ports, users, etc.)
│   ├── jellyfin/
│   ├── sonarr/
│   └── ...
└── playbooks/
    ├── db.yml            # Manage DB (start/stop/update)
    ├── db_backup.yml      # Backup DB
    └── site.yml          # Main deployment playbook
```

### **Example Tasks for `db` Role**
- **Start PostgreSQL container** (Docker).
- **Create schemas/users** for each service.
- **Backup DB** to a local or remote location.
- **Restore DB** from backup.

### **Example Playbooks**
- `db.yml`: Start/stop/update PostgreSQL.
- `db_backup.yml`: Automate backups with rotation.
- `site.yml`: Include `db` role to ensure DB is running before services start.

---

## ❓ Open Questions

- Should we use a single database for all services or multiple databases? **→ Single PostgreSQL with schemas.**
- How should the media user be handled across services?
- Are there any other services or features we should prioritize?