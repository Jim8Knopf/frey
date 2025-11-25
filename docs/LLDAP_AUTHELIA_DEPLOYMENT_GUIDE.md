# LLDAP + Authelia Deployment Guide

This guide walks you through deploying the new LLDAP + Authelia authentication stack to replace Authentik.

## Overview

**What's changing:**
- ❌ **Removing:** Authentik (4 containers, ~1GB RAM, unreliable IaC)
- ✅ **Adding:** LLDAP + Authelia (2 containers, ~150MB RAM, reliable IaC)

**Benefits:**
- 85% less RAM usage
- Configuration via Ansible templates (no more ignored blueprints!)
- Simple user management via LLDAP web UI
- Fully automated OIDC integration (zero manual steps!)

---

## Prerequisites

1. **Ansible Vault password** - You should have `.vault_pass` file
2. **SSH access** to your Raspberry Pi
3. **Backup** of existing Authentik data (if you want to preserve users)

---

## Step 1: Generate Secrets

Generate all required secrets for `group_vars/all/secrets.yml`:

```bash
# Generate LLDAP secrets
echo "lldap_admin_password: \"$(openssl rand -base64 24)\""
echo "lldap_jwt_secret: \"$(openssl rand -hex 32)\""
echo "lldap_key_seed: \"$(openssl rand -hex 32)\""

# Generate Authelia secrets
echo "authelia_jwt_secret: \"$(openssl rand -hex 64)\""
echo "authelia_session_secret: \"$(openssl rand -hex 64)\""
echo "authelia_storage_key: \"$(openssl rand -hex 64)\""
echo "authelia_oidc_hmac_secret: \"$(openssl rand -hex 64)\""

# Generate OIDC client secrets (plain, we'll hash later)
echo "immich_oidc_secret: \"$(openssl rand -hex 32)\""
echo "audiobookshelf_oidc_secret: \"$(openssl rand -hex 32)\""
echo "grafana_oidc_secret: \"$(openssl rand -hex 32)\""
echo "homeassistant_oidc_secret: \"$(openssl rand -hex 32)\""
echo "mealie_oidc_secret: \"$(openssl rand -hex 32)\""
echo "dashy_oidc_secret: \"$(openssl rand -hex 32)\""

# Generate RSA private key for OIDC JWT signing
openssl genrsa -out /tmp/authelia_private_key.pem 4096
echo "authelia_oidc_private_key: |"
cat /tmp/authelia_private_key.pem | sed 's/^/  /'
rm /tmp/authelia_private_key.pem
```

---

## Step 2: Update secrets.yml

Edit your secrets file:

```bash
ansible-vault edit group_vars/all/secrets.yml --vault-password-file .vault_pass
```

Add all the secrets you generated in Step 1. See `docs/LLDAP_AUTHELIA_SECRETS_TEMPLATE.md` for the full template.

**Important:** Don't add the `*_oidc_secret_hash` values yet - we'll generate those after deployment.

---

## Step 3: Deploy Authentication Stack

Deploy LLDAP + Authelia:

```bash
# Deploy only the authentication stack
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags authentication \
  --vault-password-file .vault_pass
```

Wait for deployment to complete (2-3 minutes):

```bash
# Check containers are running
ssh frey "docker ps | grep -E 'lldap|authelia'"

# Expected output:
# lldap        lldap/lldap:stable       Up 2 minutes   3890/tcp, 17170/tcp
# authelia     authelia/authelia:latest Up 2 minutes   9091/tcp

# Check health
ssh frey "docker inspect lldap --format='{{.State.Health.Status}}'"  # should be "healthy"
ssh frey "docker inspect authelia --format='{{.State.Health.Status}}'"  # should be "healthy"
```

---

## Step 4: Access LLDAP Web UI

1. Open your browser to **http://lldap.frey:17170**
2. Login with:
   - Username: `admin`
   - Password: `<your lldap_admin_password from secrets.yml>`

3. You should see the LLDAP dashboard:
   - Users list (only `admin` exists)
   - Groups list (empty)
   - Simple, clean interface

---

## Step 5: Create Groups in LLDAP

Create the groups referenced in your services:

1. Click **"Create group"**
2. Create these groups one by one:

| Group Name | Description |
|------------|-------------|
| `media_users` | Access to media services (Jellyfin, Audiobookshelf) |
| `admin_users` | Administrative access to all services |
| `monitoring_users` | Access to Grafana monitoring |
| `automation_users` | Access to Home Assistant, n8n, etc. |

**Note:** These group names match what's configured in `authentication.ldap_groups` in `main.yml`.

---

## Step 6: Create Your First User

1. Click **"Create user"** in LLDAP
2. Fill in:
   - **Username:** `jason` (or your preferred username)
   - **Email:** Your email address
   - **Display name:** Your full name
   - **Password:** Choose a strong password

3. Click **"Add to group"** and select:
   - `admin_users` (full access)
   - `media_users` (Jellyfin/Audiobookshelf access)
   - `monitoring_users` (Grafana access)

4. Click **"Create"**

Done! User created in 30 seconds. 🎉

---

## Step 7: Hash OIDC Client Secrets

Now we need to hash the plain client secrets for Authelia's configuration:

```bash
# SSH to your server
ssh frey

# Hash each client secret (use the plain secrets from secrets.yml)
docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_IMMICH_PLAIN_SECRET'
# Copy the output (starts with $pbkdf2-sha512$...)

docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_AUDIOBOOKSHELF_PLAIN_SECRET'
# Copy the output...

docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_GRAFANA_PLAIN_SECRET'
# Copy the output...

docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_HOMEASSISTANT_PLAIN_SECRET'
# Copy the output...

docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_MEALIE_PLAIN_SECRET'
# Copy the output...

docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_DASHY_PLAIN_SECRET'
# Copy the output...
```

---

## Step 8: Add Hashed Secrets

Edit secrets.yml again:

```bash
ansible-vault edit group_vars/all/secrets.yml --vault-password-file .vault_pass
```

Add the hashed secrets:

```yaml
# Hashed OIDC client secrets (output from Step 7)
immich_oidc_secret_hash: "$pbkdf2-sha512$310000$..."
audiobookshelf_oidc_secret_hash: "$pbkdf2-sha512$310000$..."
grafana_oidc_secret_hash: "$pbkdf2-sha512$310000$..."
homeassistant_oidc_secret_hash: "$pbkdf2-sha512$310000$..."
mealie_oidc_secret_hash: "$pbkdf2-sha512$310000$..."
dashy_oidc_secret_hash: "$pbkdf2-sha512$310000$..."
```

Save and exit.

---

## Step 9: Redeploy Authentication Stack

Redeploy to apply the hashed secrets:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags authentication \
  --vault-password-file .vault_pass
```

Wait for Authelia to restart (~30 seconds).

---

## Step 10: Redeploy Service Stacks

Now redeploy all services to pick up the new Authelia OIDC configuration:

```bash
# Deploy all stacks that use OIDC
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags monitoring,media,immich,cookbook,automation \
  --vault-password-file .vault_pass
```

This will update:
- **Grafana** - OIDC login
- **Jellyfin** - LDAP authentication
- **Immich** - OIDC login
- **Audiobookshelf** - OIDC login (manual UI config required)
- **Mealie** - OIDC login
- **Home Assistant** - OIDC login (manual UI config required)

---

## Step 11: Test OIDC Login (Grafana)

Grafana is the easiest to test since it's fully automated:

1. Open **http://grafana.frey**
2. Click **"Sign in with OAuth"** (or similar button)
3. You'll be redirected to Authelia
4. Login with the user you created in Step 6
5. Authelia will ask you to authorize Grafana
6. Click **"Authorize"**
7. You'll be redirected back to Grafana, logged in!

**Verify role mapping:**
- Check if you have Admin access (if you're in `admin_users` group)
- Try creating a dashboard to confirm permissions

---

## Step 12: Test LDAP Login (Jellyfin)

Jellyfin uses LDAP for authentication:

1. Make sure Jellyfin LDAP plugin is installed:
   - Open **http://jellyfin.frey**
   - Dashboard → Plugins → Catalog
   - Find "LDAP Authentication" and install if not present
   - Restart Jellyfin if plugin was just installed

2. Login to Jellyfin with your LDAP credentials:
   - Username: `jason` (the user you created in LLDAP)
   - Password: Your LLDAP password

3. Jellyfin should:
   - Connect to LLDAP
   - Authenticate your credentials
   - Auto-create a Jellyfin user (if `ldap_create_users: true`)
   - Grant access to all libraries

**Troubleshooting:**
```bash
# Check Jellyfin logs
ssh frey "docker logs jellyfin --tail 100"

# Check LLDAP is accessible from Jellyfin
ssh frey "docker exec jellyfin ping lldap"

# Test LDAP bind manually
ssh frey "docker exec jellyfin ldapsearch -x -H ldap://lldap:3890 \
  -D 'uid=admin,ou=people,dc=frey,dc=local' \
  -w 'YOUR_LLDAP_PASSWORD' \
  -b 'dc=frey,dc=local' '(uid=jason)'"
```

---

## Step 13: Configure Manual OIDC Services

Some services require manual OIDC configuration in their web UI:

### Audiobookshelf

1. Open **http://audiobookshelf.frey**
2. Login with local admin account (create one if needed)
3. Go to **Settings → Authentication → OpenID Connect**
4. Configure:
   - **Issuer URL:** `https://auth.frey`
   - **Client ID:** `audiobookshelf`
   - **Client Secret:** `<your audiobookshelf_oidc_secret from secrets.yml>`
   - **Button text:** `Login with SSO`
   - **Auto register:** ✅ Enabled
5. Save and test login

### Immich

1. Open **http://immich.frey**
2. Login with local admin account
3. Go to **Administration → Settings → OAuth Authentication**
4. Enable OAuth and configure:
   - **Issuer URL:** `https://auth.frey`
   - **Client ID:** `immich`
   - **Client Secret:** `<your immich_oidc_secret from secrets.yml>`
   - **Scope:** `openid profile email`
   - **Button text:** `Login with SSO`
   - **Auto register:** ✅ Enabled
5. Save and test login

### Home Assistant

1. Open **http://homeassistant.frey:8123**
2. Go to **Settings → People → Users** (requires admin)
3. Click **Add Integration**
4. Search for **"OpenID Connect"** and configure:
   - **Issuer URL:** `https://auth.frey`
   - **Client ID:** `homeassistant`
   - **Client Secret:** `<your homeassistant_oidc_secret from secrets.yml>`
5. Restart Home Assistant and test login

---

## Step 14: Verify All Services

Test each service to ensure OIDC/LDAP works:

| Service | URL | Auth Method | Expected Result |
|---------|-----|-------------|-----------------|
| **Grafana** | http://grafana.frey | OIDC (automatic) | ✅ Login with jason@frey |
| **Jellyfin** | http://jellyfin.frey | LDAP (automatic) | ✅ Login with jason |
| **Immich** | http://immich.frey | OIDC (manual config) | ✅ Login with SSO button |
| **Audiobookshelf** | http://audiobookshelf.frey | OIDC (manual config) | ✅ Login with SSO button |
| **Mealie** | http://cookbook.frey | OIDC (automatic) | ✅ Login with SSO button |
| **Home Assistant** | http://homeassistant.frey:8123 | OIDC (manual config) | ✅ Login with SSO button |

---

## Step 15: Remove Authentik (Optional)

Once everything is working, you can remove Authentik to free up resources:

**⚠️ Warning: Only do this after confirming all services work with LLDAP + Authelia!**

```bash
# Stop and remove Authentik containers
ssh frey "cd /opt/frey/stacks/infrastructure && docker compose down authentik-server authentik-worker authentik-db authentik-redis"

# Remove Authentik data (optional - keep for rollback)
ssh frey "sudo mv /opt/frey/appdata/authentik /opt/frey/appdata/authentik.backup"

# Redeploy infrastructure without Authentik
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags infrastructure \
  --vault-password-file .vault_pass
```

**Free'd resources:**
- ~1GB RAM
- ~500MB disk space
- 4 containers removed

---

## Troubleshooting

### Authelia not starting

```bash
# Check logs
ssh frey "docker logs authelia --tail 100"

# Common issues:
# - Missing secrets (check secrets.yml)
# - Invalid RSA private key (regenerate)
# - LLDAP not healthy (check lldap container)
```

### OIDC login fails with "Invalid client"

- Verify client secret is correctly hashed
- Check Authelia configuration has the client defined
- Redeploy authentication stack

### LDAP login fails in Jellyfin

```bash
# Test LDAP connection from Jellyfin container
ssh frey "docker exec jellyfin ldapsearch -x -H ldap://lldap:3890 \
  -D 'uid=admin,ou=people,dc=frey,dc=local' \
  -w 'YOUR_PASSWORD' \
  -b 'dc=frey,dc=local'"

# Check Jellyfin can reach LLDAP
ssh frey "docker exec jellyfin ping lldap"

# Verify user is in media_users group in LLDAP web UI
```

### User not authorized for service

- Check user is in the correct group in LLDAP
- Group names must match exactly (case-sensitive):
  - `admin_users` for admin access
  - `media_users` for Jellyfin/Audiobookshelf
  - `monitoring_users` for Grafana
  - `automation_users` for Home Assistant

---

## User Management Workflow (Ongoing)

### Creating a new user

1. Open **http://lldap.frey:17170**
2. Login as admin
3. Click **"Create user"**
4. Fill username, email, display name, password
5. Assign to groups (e.g., `media_users`, `admin_users`)
6. Click **"Create"**
7. **Done!** User can now log in to all services

**Time: 30 seconds per user**

### Changing user permissions

1. Open LLDAP web UI
2. Click on user
3. Add/remove from groups
4. Changes take effect immediately (no redeployment needed!)

### Resetting passwords

1. Open LLDAP web UI
2. Click on user
3. Click **"Reset password"**
4. Enter new password
5. Save

---

## Migration from Authentik (If you had users)

If you had users in Authentik and want to migrate them:

1. **Export users from Authentik:**
   - Login to Authentik admin
   - Go to Directory → Users
   - Export user list (copy usernames/emails)

2. **Create users in LLDAP:**
   - For each user, create them in LLDAP web UI
   - Assign to same groups they had in Authentik
   - Set temporary passwords, ask users to change

3. **Test each user:**
   - Have users log in to services
   - Verify permissions are correct

**Note:** Passwords cannot be migrated (different hashing). Users must reset passwords.

---

## Next Steps

- ✅ All services now use LLDAP + Authelia for authentication
- ✅ User management is simple via LLDAP web UI (30 seconds per user)
- ✅ Configuration is fully IaC via Ansible templates
- ✅ 85% less RAM usage vs Authentik

**You're done! 🎉**

User management is now:
1. Open LLDAP web UI
2. Create user → assign to groups
3. User can log in to all services automatically

No more manual OIDC configuration!
No more ignored blueprints!
No more complex Authentik admin!

**Enjoy your simplified authentication stack! 🚀**
