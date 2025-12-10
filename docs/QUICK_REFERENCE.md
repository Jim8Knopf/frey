# ⚡ Quick Reference - Manual Configuration Steps

**TL;DR**: What you need to do manually after Ansible deployment.

---

## 🔐 SSO Configuration

| Service | Manual Steps | Config Location |
|---------|-------------|----------------|
| **Grafana** | ✅ None (automatic) | Environment variables |
| **Home Assistant** | Add "OpenID Connect" integration | Settings → People → Add Integration |
| **Immich** | Enable OAuth in settings | Administration → Settings → OAuth |
| **Audiobookshelf** | Configure OIDC, use "Auto Populate" | Settings → Authentication → OpenID |
| **Jellyfin** | Install LDAP plugin + configure | Dashboard → Plugins → Catalog |

---

## 🎵 Music & Audiobooks

| Feature | Required Token | Generate Location |
|---------|---------------|-------------------|
| **Mopidy (Music)** | Jellyfin API Token | Jellyfin Dashboard → API Keys |
| **Audiobook Bridge** | Audiobookshelf API Token | Audiobookshelf Settings → Users → API Tokens |

**After generating tokens**: Update `group_vars/all/secrets.yml` and redeploy media stack.

---

## 📍 Service URLs

| Service | URL | Initial Setup |
|---------|-----|---------------|
| Authentik | `http://auth.frey` | Create admin account |
| Grafana | `https://grafana.frey` | Login via Authentik |
| Home Assistant | `http://homeassistant.frey` | Create admin account first |
| Immich | `http://immich.frey` | Create admin account first |
| Audiobookshelf | `http://audiobookshelf.frey` | Create admin account first |
| Jellyfin | `http://jellyfin.frey` | Complete setup wizard |
| Mopidy | `http://mopidy.frey:6680` | No UI login needed |

---

## 🔑 Secrets Reference

All secrets are in `group_vars/all/secrets.yml`:

```yaml
# SSO Client Secrets (pre-generated)
grafana_oidc_client_secret: "..."
homeassistant_oidc_client_secret: "..."
immich_oidc_client_secret: "..."
audiobookshelf_oidc_client_secret: "..."
authentik_ldap_bind_password: "..."

# API Tokens (YOU MUST GENERATE THESE)
jellyfin_api_token: "GENERATE_IN_JELLYFIN_UI"
audiobookshelf_api_token: "GENERATE_IN_AUDIOBOOKSHELF_UI"
```

---

## ⚙️ Enable Features

Edit `group_vars/all/main.yml`:

```yaml
features:
  homeassistant: true    # Enable Home Assistant + voice
  authentication: true   # Enable Authentik SSO

media:
  services:
    mopidy:
      enabled: true       # Enable music playback
    audiobook_bridge:
      enabled: true       # Enable audiobook playback
```

Then deploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags homeassistant
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
```

---

## 🚀 Deployment Commands

| Task | Command |
|------|---------|
| Full deployment | `ansible-playbook -i inventory/hosts.yml playbooks/site.yml` |
| Infrastructure only | `--tags infrastructure` |
| Media stack only | `--tags media` |
| Automation (incl. HA, n8n, Ollama) | `--tags automation` |
| Home Assistant only | `--tags homeassistant` |
| Monitoring only | `--tags monitoring` |

---

## 🐛 Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| Immich ML container reboot loop (model downloads blocked) | Set `immich.services.immich.machine_learning_enabled: false` (or `preload_models: false`) in `group_vars/all/main.yml`, then redeploy `--tags immich`; re-enable once models are cached or internet is back. |
| OAuth "Redirect URI Error" | Check service is using correct redirect URI from blueprint |
| "Invalid Client" | Verify client_id and secret match |
| Jellyfin LDAP not working | Install LDAP plugin, restart container |
| Mopidy can't connect | Check Jellyfin API token in secrets.yml |
| No audio output | Verify `/dev/snd` device is mounted |

---

**For detailed instructions**, see: `docs/POST_INSTALLATION_MANUAL_STEPS.md`
