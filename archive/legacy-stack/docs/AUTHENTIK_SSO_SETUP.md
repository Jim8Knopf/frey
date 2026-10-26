# Authentik SSO Setup Guide

This guide walks you through setting up Authentik SSO for centralized authentication across your Frey services.

**✨ NEW: Automated Configuration with Blueprints**
Authentik is now pre-configured automatically using blueprints! All groups, OIDC providers, LDAP providers, and applications are created automatically during deployment. You only need to generate secrets and create users.

## Table of Contents
1. [Quick Start (Automated Setup)](#quick-start-automated-setup)
2. [Initial Deployment](#initial-deployment)
3. [Authentik Initial Setup](#authentik-initial-setup)
4. [Creating Users](#creating-users)
5. [Verifying Automatic Configuration](#verifying-automatic-configuration)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)
8. [Manual Configuration (Legacy)](#manual-configuration-legacy)

---

## Quick Start (Automated Setup)

### Prerequisites
All SSO configuration is automated via Authentik blueprints. Before deployment, you only need to:

1. **Generate all secrets** using the commands in `group_vars/all/secrets.yml`
2. **Enable Authentik** in configuration
3. **Deploy** the infrastructure stack
4. **Create users** through the Authentik UI

### What's Automated
The following are automatically configured via blueprints:
- ✅ All user groups (`immich_users`, `immich_admins`, `jellyfin_users`, etc.)
- ✅ OIDC providers for Immich, Audiobookshelf, and Grafana
- ✅ LDAP provider for Jellyfin
- ✅ All applications with proper redirect URIs
- ✅ Role mappings (e.g., Grafana roles based on groups)

### What's Manual
- Creating individual users (intentionally manual for security)
- Assigning users to groups

---

## Initial Deployment

### 1. Enable Authentik in Configuration

Edit `group_vars/all/main.yml`:

```yaml
infrastructure:
  services:
    authentik:
      enabled: true  # Change from false to true
```

### 2. Generate All Secrets

**IMPORTANT:** With blueprint-based configuration, ALL secrets must be generated BEFORE deployment. Blueprints will automatically use these secrets to configure SSO providers.

Edit `group_vars/all/secrets.yml` (encrypt with `ansible-vault` after editing):

```yaml
# Authentik core secrets
authentik_secret_key: "your-very-long-random-string-at-least-50-characters"
authentik_bootstrap_password: "your-initial-admin-password"
authentik_bootstrap_token: "your-initial-api-token"
authentik_postgres_password: "your-postgres-password"

# OIDC client secrets (used by blueprints - generate BEFORE deployment!)
immich_oidc_client_secret: "generate-with-openssl-rand-hex-32"
audiobookshelf_oidc_client_secret: "generate-with-openssl-rand-hex-32"
grafana_oidc_client_secret: "generate-with-openssl-rand-hex-32"

# LDAP bind password (used by blueprints - generate BEFORE deployment!)
authentik_ldap_bind_password: "generate-with-openssl-rand-hex-32"
```

**Generate all secrets at once:**

```bash
# Authentik core secrets
openssl rand -base64 60   # authentik_secret_key
openssl rand -base64 32   # authentik_bootstrap_password
openssl rand -hex 32      # authentik_bootstrap_token
openssl rand -base64 24   # authentik_postgres_password

# OIDC and LDAP secrets
openssl rand -hex 32      # immich_oidc_client_secret
openssl rand -hex 32      # audiobookshelf_oidc_client_secret
openssl rand -hex 32      # grafana_oidc_client_secret
openssl rand -hex 32      # authentik_ldap_bind_password
```

**Note:** The file already contains these commands as comments for easy reference.

### 3. Deploy Infrastructure Stack

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure
```

### 4. Verify Deployment

```bash
# Check Authentik containers are running
docker ps | grep authentik

# Check Authentik logs
docker logs authentik_server

# Access Authentik web UI
curl http://auth.frey
```

---

## Authentik Initial Setup

### 1. Access Authentik UI

Navigate to: `http://auth.frey` (or `http://<pi-ip>:9000`)

### 2. Initial Login

- **Username**: `akadmin`
- **Password**: Value of `authentik_bootstrap_password` from secrets.yml

### 3. Change Admin Password (Recommended)

1. Click your username (top-right) → **Settings**
2. Go to **Security** → **Change Password**
3. Update to a strong password
4. Update `authentik_bootstrap_password` in secrets.yml to match

---

## Verifying Automatic Configuration

After deployment, Authentik blueprints automatically configure everything. Verify the configuration:

### 1. Check Groups

Navigate to: **Admin Interface** → **Directory** → **Groups**

You should see these groups automatically created:

| Group Name | Description |
|------------|-------------|
| `immich_users` | Can access Immich (photos) |
| `immich_admins` | Admin access to Immich |
| `audiobookshelf_users` | Can access Audiobookshelf |
| `jellyfin_users` | Can access Jellyfin |
| `jellyfin_admins` | Admin access to Jellyfin |
| `grafana_viewers` | Read-only access to Grafana |
| `grafana_editors` | Can edit Grafana dashboards |
| `grafana_admins` | Full Grafana admin access |

### 2. Check Applications

Navigate to: **Admin Interface** → **Applications** → **Applications**

You should see these applications automatically created:
- **Immich** (OIDC provider)
- **Audiobookshelf** (OIDC provider)
- **Grafana** (OIDC provider with role mapping)
- **Jellyfin** (LDAP provider)

### 3. Check Providers

Navigate to: **Admin Interface** → **Applications** → **Providers**

You should see:
- **immich-provider** (OAuth2/OIDC)
- **audiobookshelf-provider** (OAuth2/OIDC)
- **grafana-provider** (OAuth2/OIDC)
- **jellyfin-ldap-provider** (LDAP)

### 4. Check Outposts

Navigate to: **Admin Interface** → **Applications** → **Outposts**

You should see:
- **jellyfin-ldap-outpost** (LDAP outpost for Jellyfin authentication)

If any of the above are missing, check the deployment logs and ensure all secrets were properly generated.

---

## Creating Users

Groups and applications are now pre-configured via blueprints. You only need to create users and assign them to groups.

### Create a New User

1. **Admin Interface** → **Directory** → **Users** → **Create**

For each user:
- **Username**: `john.doe`
- **Name**: `John Doe`
- **Email**: `john.doe@example.com`
- **Password**: Set or let user set on first login
- **Groups**: Add to relevant groups (e.g., `immich_users`, `jellyfin_users`)

---

## Manual Configuration (Legacy)

**⚠️ NOTE:** The sections below describe manual configuration through the Authentik UI. With blueprints enabled, this is NO LONGER NECESSARY. All providers, applications, and groups are automatically configured during deployment.

These sections are kept for reference only, in case you need to:
- Modify existing configurations
- Add additional services not covered by blueprints
- Understand how the automatic configuration works
- Troubleshoot blueprint-generated configurations

---

## Configuring OIDC Applications

**⚠️ This section is LEGACY - Blueprints now auto-configure OIDC applications**

Configure OIDC for Immich, Audiobookshelf, and Grafana.

### General OIDC Setup Pattern

For each application:
1. **Admin Interface** → **Applications** → **Create**
2. Create **Provider** first, then link to **Application**

---

### Immich OIDC Configuration

#### Step 1: Create OAuth2 Provider

**Admin Interface** → **Applications** → **Providers** → **Create** → **OAuth2/OpenID Provider**

**Settings:**
- **Name**: `immich-provider`
- **Authentication flow**: `default-authentication-flow (Welcome)`
- **Authorization flow**: `default-provider-authorization-implicit-consent`
- **Client type**: `Confidential`
- **Client ID**: `immich`
- **Client Secret**: Copy this value (needed for secrets.yml)
- **Redirect URIs**:
  ```
  http://immich.frey/auth/login
  http://immich.frey/user-settings
  http://<pi-ip>:2283/auth/login
  http://<pi-ip>:2283/user-settings
  app.immich:/
  ```
- **Signing Key**: `authentik Self-signed Certificate`
- **Scopes**: `openid`, `profile`, `email`

#### Step 2: Create Application

**Admin Interface** → **Applications** → **Applications** → **Create**

- **Name**: `Immich`
- **Slug**: `immich`
- **Provider**: Select `immich-provider`
- **Icon**: Upload Immich logo (optional)
- **Policy engine mode**: `any`

#### Step 3: Update Secrets

Add the client secret to `group_vars/all/secrets.yml`:
```yaml
immich_oidc_client_secret: "<paste-client-secret-from-authentik>"
```

---

### Audiobookshelf OIDC Configuration

#### Step 1: Create OAuth2 Provider

**Settings:**
- **Name**: `audiobookshelf-provider`
- **Client ID**: `audiobookshelf`
- **Client Secret**: Copy this value
- **Redirect URIs**:
  ```
  http://audiobookshelf.frey/auth/openid/callback
  http://audiobookshelf.frey/auth/openid/mobile-redirect
  http://<pi-ip>:13378/auth/openid/callback
  http://<pi-ip>:13378/auth/openid/mobile-redirect
  audiobookshelf://oauth
  ```

#### Step 2: Create Application

- **Name**: `Audiobookshelf`
- **Slug**: `audiobookshelf`
- **Provider**: Select `audiobookshelf-provider`

#### Step 3: Update Secrets

```yaml
audiobookshelf_oidc_client_secret: "<paste-client-secret-from-authentik>"
```

#### Step 4: Configure in Audiobookshelf UI

Audiobookshelf OIDC is configured through its web interface:

1. Access `http://audiobookshelf.frey`
2. **Settings** → **Authentication**
3. Enable **OpenID Connect Authentication**
4. **Issuer URL**: `http://auth.frey/application/o/audiobookshelf/`
5. Click **Auto-populate** (fills most fields automatically)
6. **Client ID**: `audiobookshelf`
7. **Client Secret**: `<value-from-secrets.yml>`
8. **Auto Register**: Enable (creates users automatically)
9. **Auto Launch**: Disable (allows local admin login)
10. **Save**

**Important**: You can always bypass SSO and login locally by navigating to:
```
http://audiobookshelf.frey/login/?autoLaunch=0
```

---

### Grafana OIDC Configuration

#### Step 1: Create OAuth2 Provider

**Settings:**
- **Name**: `grafana-provider`
- **Client ID**: `grafana`
- **Client Secret**: Copy this value
- **Redirect URIs**:
  ```
  https://grafana.frey/login/generic_oauth
  http://<pi-ip>:3000/login/generic_oauth
  ```

#### Step 2: Create Application

- **Name**: `Grafana`
- **Slug**: `grafana`
- **Provider**: Select `grafana-provider`

#### Step 3: Update Secrets and Config

**Secrets** (`group_vars/all/secrets.yml`):
```yaml
grafana_oidc_client_secret: "<paste-client-secret-from-authentik>"
```

**Enable OIDC** (`group_vars/all/main.yml`):
```yaml
monitoring:
  grafana:
    oidc_enabled: true
    oidc_client_id: "grafana"
```

#### Step 4: Redeploy Monitoring Stack

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring
```

---

## Configuring LDAP Provider (for Jellyfin)

**⚠️ This section is LEGACY - Blueprints now auto-configure LDAP provider and outpost**

Jellyfin uses LDAP authentication instead of OIDC.

### Step 1: Create LDAP Provider in Authentik

**Admin Interface** → **Applications** → **Providers** → **Create** → **LDAP Provider**

**Settings:**
- **Name**: `jellyfin-ldap-provider`
- **Base DN**: `dc=ldap,dc=goauthentik,dc=io`
- **Bind DN**: `cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io`
- **Bind Password**: Auto-generated (copy this)
- **Search group**: Leave empty or select `jellyfin_users`

### Step 2: Create LDAP Outpost

**Admin Interface** → **Applications** → **Outposts** → **Create**

**Settings:**
- **Name**: `jellyfin-ldap-outpost`
- **Type**: `LDAP`
- **Integration**: `Local Docker connection`
- **Applications**: Select `Jellyfin` (create application first if needed)

This creates a new LDAP server container accessible at `authentik-ldap-outpost:389`.

### Step 3: Create Jellyfin Application

**Admin Interface** → **Applications** → **Applications** → **Create**

- **Name**: `Jellyfin`
- **Slug**: `jellyfin`
- **Provider**: Select `jellyfin-ldap-provider`

### Step 4: Install Jellyfin LDAP Plugin

1. Access Jellyfin: `http://jellyfin.frey`
2. **Dashboard** → **Plugins** → **Catalog**
3. Search for **LDAP Authentication Plugin**
4. Click **Install**
5. **Restart Jellyfin** when prompted

### Step 5: Configure LDAP in Jellyfin

1. **Dashboard** → **Plugins** → **LDAP-Auth**
2. **Add LDAP Server**:

**Settings:**
- **LDAP Server**: `auth.frey` (or `<pi-ip>`)
- **LDAP Port**: `389`
- **Secure LDAP**: Unchecked
- **LDAP Bind User**: `cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io`
- **LDAP Bind Password**: `<from-authentik-ldap-provider>`
- **LDAP Base DN**: `dc=ldap,dc=goauthentik,dc=io`
- **LDAP User Filter**: `(memberOf=cn=jellyfin_users,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
- **LDAP Admin Filter**: `(memberOf=cn=jellyfin_admins,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
- **Enable User Creation**: Checked (auto-creates Jellyfin users)

3. **Save**

### Step 6: Update Secrets

```yaml
authentik_ldap_bind_password: "<paste-bind-password-from-authentik>"
```

---

## Enabling SSO in Services

### Immich

Edit `group_vars/all/main.yml`:

```yaml
immich:
  services:
    immich:
      oidc_enabled: true
      oidc_client_id: "immich"
      oidc_auto_register: true
      oidc_auto_launch: false  # Allow local admin login
```

Redeploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags immich
```

### Audiobookshelf

Configure through web UI (see [Audiobookshelf OIDC Configuration](#step-4-configure-in-audiobookshelf-ui) above).

### Jellyfin

Already configured through LDAP plugin (see [Configuring LDAP Provider](#configuring-ldap-provider-for-jellyfin) above).

### Grafana

Edit `group_vars/all/main.yml`:

```yaml
monitoring:
  grafana:
    oidc_enabled: true
```

Redeploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring
```

---

## Testing

### Test User Access

For each service, test login with a regular user account:

1. **Immich** (`http://immich.frey`):
   - Click **Login with Authentik**
   - Redirects to Authentik
   - Login with user credentials
   - Should redirect back to Immich

2. **Audiobookshelf** (`http://audiobookshelf.frey`):
   - Automatically redirects to Authentik (if `auto_launch` enabled)
   - Login with user credentials
   - Redirects back to Audiobookshelf

3. **Jellyfin** (`http://jellyfin.frey`):
   - Enter Authentik username and password
   - LDAP authentication happens in background
   - Logs into Jellyfin

4. **Grafana** (`https://grafana.frey`):
   - Click **Sign in with Authentik**
   - Redirects to Authentik
   - Login with user credentials
   - Redirects back to Grafana with correct role

### Test Role-Based Access

**Grafana Roles Test:**

| User Group | Expected Role |
|------------|---------------|
| `grafana_admins` | Admin |
| `grafana_editors` | Editor |
| `grafana_viewers` | Viewer |
| No grafana group | Viewer (default) |

### Test Mobile Apps

**Immich Mobile:**
1. Download Immich app (iOS/Android)
2. **Server URL**: `http://<pi-ip>:2283` or `http://immich.frey`
3. Login with Authentik credentials
4. Should authenticate via mobile redirect

**Audiobookshelf Mobile:**
1. Download Audiobookshelf app
2. **Server URL**: `http://<pi-ip>:13378` or `http://audiobookshelf.frey`
3. Login with Authentik credentials

---

## Troubleshooting

### Authentik Not Accessible

**Check containers:**
```bash
docker ps | grep authentik
docker logs authentik_server
docker logs authentik_postgres
docker logs authentik_redis
```

**Check network:**
```bash
curl http://auth.frey
curl http://auth.frey/-/health/ready/
```

### OIDC Login Fails

1. **Check redirect URIs** in Authentik provider match exactly
2. **Check client secret** matches between Authentik and service config
3. **Check logs:**
   ```bash
   # Authentik
   docker logs authentik_server | grep -i error

   # Immich
   docker logs immich_server | grep -i oidc

   # Grafana
   docker logs grafana | grep -i oauth
   ```

### Jellyfin LDAP Authentication Fails

1. **Check LDAP outpost is running:**
   ```bash
   docker ps | grep ldap
   docker logs authentik-ldap-outpost
   ```

2. **Test LDAP connection from Jellyfin:**
   - Jellyfin Dashboard → Plugins → LDAP-Auth
   - Click **Test**

3. **Check user is in correct group:**
   - Authentik → Directory → Users → [User] → Groups
   - Should include `jellyfin_users`

### Users Not Created Automatically

**Immich/Audiobookshelf:**
- Check `oidc_auto_register: true` is enabled
- User must complete login flow once

**Jellyfin:**
- Check "Enable User Creation" is enabled in LDAP plugin
- User must exist in Authentik and be in `jellyfin_users` group

### Bypass SSO for Admin Access

**Immich:**
```
http://immich.frey/auth/login?autoLaunch=0
```

**Audiobookshelf:**
```
http://audiobookshelf.frey/login/?autoLaunch=0
```

**Grafana:**
- Login with local admin account (username: `admin`)

### Reset Authentik Admin Password

```bash
docker exec -it authentik_server ak set_password akadmin
```

---

## Additional Resources

- **Authentik Documentation**: https://docs.goauthentik.io/
- **Immich OAuth Docs**: https://immich.app/docs/administration/oauth/
- **Audiobookshelf OIDC Guide**: https://www.audiobookshelf.org/guides/oidc_authentication/
- **Grafana OAuth Docs**: https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/
- **Jellyfin LDAP Plugin**: https://github.com/jellyfin/jellyfin-plugin-ldapauth

---

## Quick Reference

### Service URLs

| Service | URL | Port |
|---------|-----|------|
| Authentik | `http://auth.frey` | 9000 |
| Immich | `http://immich.frey` | 2283 |
| Audiobookshelf | `http://audiobookshelf.frey` | 13378 |
| Jellyfin | `http://jellyfin.frey` | 8096 |
| Grafana | `https://grafana.frey` | 3000 |

### Default Credentials

**Authentik:**
- Username: `akadmin`
- Password: From `authentik_bootstrap_password` in secrets.yml

**Grafana (before SSO):**
- Username: `admin`
- Password: From `monitoring.grafana.default_password` in secrets.yml

### Important Files

- Configuration: `group_vars/all/main.yml`
- Secrets: `group_vars/all/secrets.yml` (encrypted)
- Infrastructure Compose: `roles/infrastructure/templates/docker-compose-infrastructure.yml.j2`
- This Guide: `docs/AUTHENTIK_SSO_SETUP.md`
