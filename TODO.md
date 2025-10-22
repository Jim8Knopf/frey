# Frey - Raspberry Pi 5 Hub Ansible Project

This is the structured and prioritized TODO checklist for the Frey project.

---

## 🔴 Critical Security & Stability (Do Now!)

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Encrypt all secrets with Ansible Vault | Hardcoded passwords and API keys are a security risk.                                    | ⬜️     |
|- [ ] Fix Deprecation Warnings              | Outdated modules may cause future errors.                                                | ⬜️     |
|- [ ] Remove hardcoded passwords            | Security vulnerability.                                                                  | ⬜️     |

---

## 🟡 High-Priority Refactoring (Do Next)

| Task                                      | Why?                                                                                     | Status |
|-------------------------------------------|------------------------------------------------------------------------------------------|--------|
|- [ ] Refactor project structure            | Improve maintainability and clarity.                                                     | ⬜️     |
|- [ ] Complete Traefik integration          | Ensure all services are accessible via Traefik with HTTPS.                               | ⬜️     |
|- [ ] Move variables to roles               | Make roles self-contained and reduce global variable clutter.                            | ⬜️     |
|- [ ] Add post-deployment health checks     | Prevent silent failures after deployment.                                                | ⬜️     |
|- [ ] Clarify DB strategy                   | Decide whether to use a single or multiple databases for services.                       | ⬜️     |

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

## ❓ Open Questions

- Should we use a single database for all services or multiple databases?
- How should the media user be handled across services?
- Are there any other services or features we should prioritize?