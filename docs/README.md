# 📚 Frey Documentation

Complete documentation for the Frey home server project.

---

## 📖 Documentation Index

### **Getting Started**
- **[Quick Reference](QUICK_REFERENCE.md)** - Fast lookup for common tasks and configurations
- **[Post-Installation Steps](POST_INSTALLATION_MANUAL_STEPS.md)** - Detailed manual configuration steps after Ansible deployment

### **Architecture** (See main repo)
- Project structure and design patterns
- Network architecture and Docker setup
- Service organization

---

## 🚀 Quick Start

### 1. **Deploy Infrastructure**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

### 2. **Complete Manual Steps**
Follow **[POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md)** to:
- Configure SSO (Authentik) for all services
- Generate API tokens for Jellyfin and Audiobookshelf
- Install required plugins

### 3. **Access Your Services**
- Authentik: `http://auth.frey`
- Grafana: `http://grafana.frey`
- Home Assistant: `http://homeassistant.frey`
- Immich: `http://immich.frey`
- Jellyfin: `http://jellyfin.frey`
- Audiobookshelf: `http://audiobookshelf.frey`

---

## 📋 Essential Files

| File | Purpose |
|------|---------|
| `group_vars/all/main.yml` | Main configuration (features, services) |
| `group_vars/all/secrets.yml` | Encrypted secrets (passwords, tokens) |
| `playbooks/site.yml` | Main Ansible playbook |
| `inventory/hosts.yml` | Target host configuration |

---

## 🎯 Common Tasks

### **Enable a Feature**
1. Edit `group_vars/all/main.yml`
2. Set feature flag to `true` (e.g., `features.homeassistant: true`)
3. Redeploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags <tag>`

### **Add a Secret**
1. Edit encrypted secrets: `ansible-vault edit group_vars/all/secrets.yml`
2. Add your secret
3. Redeploy affected service

### **Update a Service**
```bash
# Specific service stack
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation  # Includes Home Assistant

# Multiple services
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "media,monitoring"
```

---

## 🔧 Troubleshooting

See **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** for quick troubleshooting tips.

For detailed troubleshooting, see the **Troubleshooting** section in **[POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md)**.

---

## 🆘 Getting Help

1. Check the documentation in this folder
2. Review logs: `docker logs <container_name>`
3. Check Ansible output for errors
4. Verify configuration in `group_vars/all/main.yml`

---

**Project**: Frey - Self-Hosted Home Server Platform
**Last Updated**: 2025-10-31
