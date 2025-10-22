# Frey - Raspberry Pi 5 Hub Ansible Project

This is the structured and prioritized TODO list for the Frey project. It includes security improvements, refactoring tasks, and feature enhancements.

---

## 🔴 Critical Security & Stability (Do Now!)

| Task                                      | Why?                                                                                     | How?                                                                                     |
|-------------------------------------------|------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| **Encrypt all secrets with Ansible Vault** | Hardcoded passwords and API keys are a security risk.                                    | `ansible-vault create group_vars/secrets.yml`, move all secrets, update playbooks.       |
| **Fix Deprecation Warnings**               | Outdated modules may cause future errors.                                                | Update `ansible.cfg` or replace deprecated modules.                                     |
| **Remove hardcoded passwords**             | Security vulnerability.                                                                  | Move all secrets to `group_vars/secrets.yml` and encrypt with Ansible Vault.             |

---

## 🟡 High-Priority Refactoring (Do Next)

| Task                                      | Why?                                                                                     | How?                                                                                     |
|-------------------------------------------|------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| **Refactor project structure**             | Improve maintainability and clarity.                                                     | Create `ansible/` directory, move Ansible files, update `deploy.sh`.                    |
| **Complete Traefik integration**           | Ensure all services are accessible via Traefik with HTTPS.                               | Add Traefik labels to all services in `docker-compose-*.yml.j2`.                        |
| **Move variables to roles**                | Make roles self-contained and reduce global variable clutter.                            | Move port definitions to `roles/ROLENAME/defaults/main.yml`.                             |
| **Add post-deployment health checks**      | Prevent silent failures after deployment.                                                | Add `ansible.builtin.uri` tasks to `playbooks/site.yml` to verify service availability.   |
| **Clarify DB strategy**                    | Decide whether to use a single or multiple databases for services.                       | Document and implement the chosen strategy in the relevant roles.                       |

---

## 🟢 Feature Enhancements (Plan for Next Iteration)

| Task                                      | Why?                                                                                     | How?                                                                                     |
|-------------------------------------------|------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| **Integrate Cockpit**                      | Web-based management for the Raspberry Pi.                                               | Add a new role for Cockpit and include it in `site.yml`.                                 |
| **Implement system notifications (ntfy)**  | Proactively monitor deployments and backups.                                             | Deploy `ntfy` as a Docker container, adapt scripts to send notifications.                |
| **Optimize media library with Tdarr**      | Save storage space and standardize media formats.                                        | Add Tdarr as a Docker container to the media stack.                                      |
| **Archive YouTube channels (Tube-Archivist)| Local backup of important YouTube content.                                                | Add Tube-Archivist as a Docker container.                                                |
| **Test backup/restore strategy**           | Ensure backups are functional and usable.                                                | Create a `restore` role, test with Jellyfin, and document the process.                   |

---

## 📌 Technical Debt & Cleanup

| Task                                      | Why?                                                                                     | How?                                                                                     |
|-------------------------------------------|------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| **Update README.md**                       | Reflect the current state of the project.                                                | Rewrite `README.md` to match the actual features and setup.                              |
| **Add input validation**                   | Prevent misconfigurations and errors.                                                    | Add validation for critical variables in `group_vars/all.yml`.                           |
| **Improve error handling**                 | Make the project more robust.                                                            | Add error handling in playbooks and scripts.                                             |
| **Simplify network architecture**          | Reduce complexity and improve performance.                                               | Review and refactor network-related roles and playbooks.                                 |

---

## 💡 Long-Term Ideas (Maybe/Someday)

| Task                                      | Why?                                                                                     | How?                                                                                     |
|-------------------------------------------|------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| **Add Umlautarr**                          | Improve media library management.                                                        | Integrate Umlautarr into the media stack.                                                |
| **Add automated testing**                  | Ensure reliability and catch issues early.                                               | Implement CI/CD with GitHub Actions or similar.                                          |
| **Add monitoring for services**            | Proactively detect and resolve issues.                                                   | Extend Prometheus/Grafana setup to monitor all services.                                 |

---

## ❓ Open Questions

- Should we use a single database for all services or multiple databases?
- How should the media user be handled across services?
- Are there any other services or features we should prioritize?