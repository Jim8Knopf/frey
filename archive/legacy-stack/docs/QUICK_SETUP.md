# ⚡ Frey Quick Setup Guide

**Goal:** Get from zero to fully running system in under 30 minutes.

**What this covers:** Only the essential steps. For detailed explanations, see [USER_GUIDE.md](USER_GUIDE.md).

---

## ✅ Prerequisites Checklist

Before starting, ensure you have:

- [ ] Raspberry Pi 5 (4GB+ RAM recommended)
- [ ] MicroSD card (32GB+ ) or SSD
- [ ] Raspberry Pi OS Lite installed (64-bit)
- [ ] SSH access to Pi configured
- [ ] Ansible installed on your control machine (`pip install ansible`)
- [ ] Pi connected to your network

---

## 🚀 Part 1: Initial Setup (5 minutes)

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/frey.git
cd frey
```

### 2. Configure Inventory

Edit `inventory/hosts.yml`:

```yaml
all:
  hosts:
    frey:
      ansible_host: 192.168.1.100  # ← Change to your Pi's IP
      ansible_user: pi              # ← Your SSH user
      ansible_become_pass: "{{ vault_ansible_become_pass }}"
```

### 3. Configure Main Settings

Edit `group_vars/all/main.yml`:

**Required changes:**
```yaml
network:
  domain_name: "frey"         # ← Keep or change
  timezone: "Europe/Berlin"    # ← Your timezone

storage:
  base_dir: "/opt/frey"        # ← Keep or change

# Enable features you want:
features:
  infrastructure: true
  media: true
  monitoring: true
  automation: true
  homeassistant: true
  immich: true
  wifi_access_point: false    # ← true if you want WiFi AP
```

### 4. Create Vault Password

```bash
openssl rand -base64 32 > .vault_pass
chmod 600 .vault_pass
```

### 5. Configure Secrets

```bash
ansible-vault edit group_vars/all/secrets.yml
```

**Generate secure random passwords:**
```bash
# Generate passwords
openssl rand -base64 32  # Run this multiple times
```

**Minimal required secrets:**
```yaml
# Ansible
vault_ansible_become_pass: "YourSudoPassword"

# Authentik (SSO)
authentik_secret_key: "GENERATE_RANDOM_50_CHARS"
authentik_postgres_password: "GENERATE_RANDOM_32_CHARS"

# SSO Client Secrets (generate random for each)
grafana_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
homeassistant_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
immich_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
audiobookshelf_oidc_client_secret: "GENERATE_RANDOM_32_CHARS"
authentik_ldap_bind_password: "GENERATE_RANDOM_32_CHARS"

# Leave these for now (set after deployment)
jellyfin_api_token: "CHANGE_AFTER_DEPLOYMENT"
audiobookshelf_api_token: "CHANGE_AFTER_DEPLOYMENT"
```

---

## 🎯 Part 2: Deploy (2 minutes)

### Run Full Deployment

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

**Expected duration:** 15-30 minutes (depends on internet speed for Docker image downloads)

**While it runs:** Get coffee ☕ - the playbook will handle everything automatically.

---

## 🔧 Part 3: Mandatory Manual Steps (15 minutes)

After deployment completes, these steps MUST be done manually:

### 1. Create Authentik Admin Account (2 min)

```bash
# Open browser
http://auth.frey

# Click "Create Admin Account"
# Username: admin
# Password: (choose strong password)
# Email: your@email.com
```

**Verify:** Blueprints should auto-create applications. Check: Admin → Applications

---

### 2. Configure Grafana SSO (0 min - Automatic!)

```bash
# Open browser
https://grafana.frey

# Click "Sign in with Authentik"
```

✅ **No manual steps needed** - works automatically!

---

### 3. Configure Home Assistant OIDC (3 min)

```bash
http://homeassistant.frey
```

1. Complete initial setup wizard (create local admin account)
2. Settings → People → Add Integration → Search "OpenID Connect"
3. Fill in:
   - **Name:** `Authentik`
   - **Client ID:** `homeassistant`
   - **Client Secret:** *(copy from `group_vars/all/secrets.yml`)*
   - **Issuer:** `http://auth.frey/application/o/homeassistant/`
4. Click Submit

---

### 4. Configure Immich OAuth (3 min)

```bash
http://immich.frey
```

1. Create initial admin account
2. Administration (top right) → Settings → OAuth Authentication
3. Enable OAuth:
   - **Issuer URL:** `http://auth.frey/application/o/immich/`
   - **Client ID:** `immich`
   - **Client Secret:** *(copy from `secrets.yml`)*
   - **Auto Register:** Yes
4. Save

---

### 5. Configure Audiobookshelf OIDC (2 min)

```bash
http://audiobookshelf.frey
```

1. Create initial admin account
2. Settings → Authentication → OpenID Connect
3. **Issuer URL:** `http://auth.frey/application/o/audiobookshelf/`
4. Click "Auto Populate" (fills most fields automatically)
5. Enter manually:
   - **Client ID:** `audiobookshelf`
   - **Client Secret:** *(copy from `secrets.yml`)*
6. Save

---

### 6. Configure Jellyfin LDAP (5 min)

```bash
http://jellyfin.frey
```

1. Complete setup wizard
2. Dashboard → Plugins → Catalog
3. Install "LDAP Authentication" plugin
4. **Restart Jellyfin:**
   ```bash
   ssh frey "docker restart jellyfin"
   ```
5. Dashboard → Plugins → LDAP Authentication → Settings
6. Configure:
   - **Server:** `authentik-ldap-outpost`
   - **Port:** `389`
   - **Base DN:** `dc=ldap,dc=goauthentik,dc=io`
   - **Bind User:** `cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io`
   - **Bind Password:** *(copy `authentik_ldap_bind_password` from `secrets.yml`)*
   - **User Filter:** `(memberOf=cn=jellyfin_users,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
   - **Admin Filter:** `(memberOf=cn=jellyfin_admins,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
7. Save

---

## ✅ Part 4: Verify Everything Works (3 minutes)

### Quick Smoke Tests

```bash
# Check all containers running
ssh frey "docker ps"

# Test DNS resolution (from WiFi client)
nslookup jellyfin.frey

# Test web access
curl -I http://traefik.frey:8082
curl -I https://grafana.frey
```

### Service URLs

| Service | URL | Status Check |
|---------|-----|--------------|
| Traefik Dashboard | http://traefik.frey:8082 | Should show routes |
| Authentik | http://auth.frey | Should show login |
| Grafana | https://grafana.frey | Should show SSO login |
| Home Assistant | http://homeassistant.frey | Should show login |
| Jellyfin | http://jellyfin.frey | Should show library |
| Audiobookshelf | http://audiobookshelf.frey | Should show books |
| Immich | http://immich.frey | Should show photos |
| Portainer | http://portainer.frey | Should show containers |
| n8n | http://n8n.frey | Should show workflows |
| Ollama | http://ai.frey | Should show AI chat |

---

## 🎉 You're Done!

Your Frey system is now fully operational!

---

## 🔮 Optional Next Steps

### Generate API Tokens (for music/audiobook features)

**If you want local music/audiobook playback:**

1. **Jellyfin API Token:**
   ```
   Jellyfin → Dashboard → API Keys → Create: "Mopidy Integration"
   Copy token → Update secrets.yml: jellyfin_api_token
   Enable: media.services.mopidy.enabled: true
   Redeploy: ansible-playbook ... --tags media
   ```

2. **Audiobookshelf API Token:**
   ```
   Audiobookshelf → Settings → Users → Your User → Generate Token
   Copy token → Update secrets.yml: audiobookshelf_api_token
   Enable: media.services.audiobook_bridge.enabled: true
   Redeploy: ansible-playbook ... --tags media
   ```

### Setup WiFi Automatic Roaming

**If you want automatic public WiFi management:**

```yaml
# Edit group_vars/all/main.yml
network:
  wifi:
    roaming:
      enabled: true

# Redeploy
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags wifi
```

See [WIFI_ROAMING_SETUP.md](WIFI_ROAMING_SETUP.md) for details.

### Add Users to Authentik Groups

```
http://auth.frey → Admin → Directory → Groups

Assign users to:
- grafana_admins / grafana_editors / grafana_viewers
- jellyfin_users / jellyfin_admins
```

---

## 🆘 Something Went Wrong?

### Deployment Failed

```bash
# Check what failed
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check

# View container logs
ssh frey "docker logs <container_name>"

# Check service status
ssh frey "docker ps -a"
```

### Can't Access Services

```bash
# Check Traefik is running
ssh frey "docker ps | grep traefik"

# Check DNS
nslookup jellyfin.frey

# Check firewall
ssh frey "sudo ufw status"
```

### SSO Login Fails

1. Check Authentik is running: `docker ps | grep authentik`
2. Verify client secret matches in service and `secrets.yml`
3. Check Authentik logs: `docker logs authentik_server`
4. Verify redirect URIs in Authentik blueprints

---

## 📚 Next: Learn More

- **[USER_GUIDE.md](USER_GUIDE.md)** - Comprehensive guide to all features
- **[POST_INSTALLATION_MANUAL_STEPS.md](POST_INSTALLATION_MANUAL_STEPS.md)** - Detailed manual configuration instructions
- **[SETUP_CHECKLIST.md](SETUP_CHECKLIST.md)** - Step-by-step checklist with checkboxes
- **[WIFI_ROAMING_SETUP.md](WIFI_ROAMING_SETUP.md)** - WiFi automatic roaming system guide
- **[AUTHENTIK_SSO_SETUP.md](AUTHENTIK_SSO_SETUP.md)** - Deep dive into SSO configuration

---

**Time taken:** ~25 minutes setup + 20 minutes deployment = **45 minutes total**

**Ready to explore your new Frey system! 🎊**
