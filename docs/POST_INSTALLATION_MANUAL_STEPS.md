# 📋 Post-Installation Manual Steps

Complete these steps after running the Ansible playbook to fully configure SSO and integrations.

---

## 🔐 1. Enable SSO (Single Sign-On)

### Prerequisites
- Set `features.authentication: true` in `group_vars/all/main.yml`
- Deploy infrastructure: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure`
- **Create your first Authentik admin account**: Go to `http://auth.frey` and complete setup

---

## ✅ 2. Configure SSO for Each Service

### 📊 **Grafana** (Automatic ✅)
**Status**: No manual steps required! OAuth works automatically via environment variables.

**Test**: Go to `http://grafana.frey` → Click "Sign in with Authentik"

---

### 🏠 **Home Assistant**

**Steps**:
1. Go to `http://homeassistant.frey`
2. Create initial admin account (first-time setup)
3. Go to **Settings** → **People** → **Add Integration**
4. Search for **"OpenID Connect"**
5. Enter configuration:
   - **Name**: `Authentik`
   - **Client ID**: `homeassistant`
   - **Client Secret**: (from `group_vars/all/secrets.yml` → `homeassistant_oidc_client_secret`)
   - **Issuer**: `http://auth.frey/application/o/homeassistant/`
6. Click **Submit**

**Test**: Log out and log in via Authentik

---

### 📸 **Immich**

**Steps**:
1. Go to `http://immich.frey`
2. Create initial admin account (first-time setup)
3. Go to **Administration** (sidebar) → **Settings** → **OAuth Authentication**
4. Enable OAuth:
   - **Enable**: `Yes`
   - **Issuer URL**: `http://auth.frey/application/o/immich/`
   - **Client ID**: `immich`
   - **Client Secret**: (from `secrets.yml` → `immich_oidc_client_secret`)
   - **Auto Register**: `Yes` (optional)
   - **Auto Launch**: `No` (recommended)
5. Click **Save**

**Test**: Log out → Click "Login with OAuth" → Authenticate with Authentik

---

### 📚 **Audiobookshelf**

**Steps**:
1. Go to `http://audiobookshelf.frey`
2. Create initial admin account (first-time setup)
3. Go to **Settings** → **Authentication** → **OpenID Connect**
4. Enter configuration:
   - **Issuer URL**: `http://auth.frey/application/o/audiobookshelf/`
   - Click **"Auto Populate"** (should fill in URLs automatically)
   - **Client ID**: `audiobookshelf`
   - **Client Secret**: (from `secrets.yml` → `audiobookshelf_oidc_client_secret`)
   - **Button Text**: `Login with Authentik` (optional)
   - **Auto Register**: `Yes` (optional)
   - **Auto Launch**: `No` (recommended)
5. Click **Save**

**Test**: Log out → Click "Login with Authentik"

---

### 🎬 **Jellyfin**

**Steps**:
1. Go to `http://jellyfin.frey`
2. Complete initial setup wizard
3. Install **LDAP Authentication Plugin**:
   - Go to **Dashboard** → **Plugins** → **Catalog**
   - Find **"LDAP Authentication"**
   - Click **Install**
   - Restart Jellyfin container: `docker restart jellyfin`
4. Configure LDAP plugin:
   - **Dashboard** → **Plugins** → **LDAP Authentication** → **Settings**
   - **LDAP Server**: `authentik-ldap-outpost`
   - **LDAP Port**: `389`
   - **Base DN**: `dc=ldap,dc=goauthentik,dc=io`
   - **Bind User**: `cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io`
   - **Bind Password**: (from `secrets.yml` → `authentik_ldap_bind_password`)
   - **User Search Filter**: `(memberOf=cn=jellyfin_users,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
   - **Admin Filter**: `(memberOf=cn=jellyfin_admins,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
5. Click **Save**

**Test**: Log out → Log in with your Authentik username/password

---

## 🎵 3. Configure Music Playback (Mopidy)

### **Generate Jellyfin API Token**

**Steps**:
1. Go to `http://jellyfin.frey`
2. Login as admin
3. Go to **Dashboard** → **API Keys**
4. Click **"+ Create New Key"**
5. Name it: `Mopidy Integration`
6. Copy the generated token
7. Update `group_vars/all/secrets.yml`:
   ```yaml
   jellyfin_api_token: "YOUR_TOKEN_HERE"
   ```
8. Redeploy media stack:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
   ```

### **Install Jellyfin Smart Playlist Plugin**

**Steps**:
1. In Jellyfin, go to **Dashboard** → **Plugins** → **Repositories**
2. Add repository (if not already present):
   - **Repository Name**: `Jellyfin Plugin Repository`
   - **Repository URL**: `https://repo.jellyfin.org/releases/plugin/manifest-stable.json`
3. Go to **Catalog** → Search for **"Smart Playlist"**
4. Install the plugin
5. Restart Jellyfin container: `docker restart jellyfin`
6. Configure smart playlists:
   - **Dashboard** → **Plugins** → **Smart Playlist** → **Settings**
   - Create playlists with tag-based rules (e.g., tags: `me`, `dad`, `friend1`)

**Test**: Check if playlists appear in Jellyfin library

---

## 🎧 4. Configure Audiobook Playback

### **Generate Audiobookshelf API Token**

**Steps**:
1. Go to `http://audiobookshelf.frey`
2. Login as admin
3. Go to **Settings** → **Users** → Select your user
4. Scroll down to **API Tokens**
5. Click **"Generate New Token"**
6. Copy the token
7. Update `group_vars/all/secrets.yml`:
   ```yaml
   audiobookshelf_api_token: "YOUR_TOKEN_HERE"
   ```
8. Redeploy media stack:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media
   ```

**Deploy Playback Script**:
```bash
# Copy the Python script to the audiobook-bridge container
ssh frey
docker cp roles/media/templates/audiobook-bridge/play_book.py audiobook-bridge:/app/play_book.py
```

**Test**: Run playback manually:
```bash
docker exec audiobook-bridge python3 /app/play_book.py --book-id YOUR_BOOK_ID
```

---

## 👥 5. Create Authentik User Groups (For Role-Based Access)

### **Grafana Groups**

1. Go to `http://auth.frey` → **Directory** → **Groups**
2. Create groups (already created by blueprints, but verify):
   - `grafana_admins` - Full admin access
   - `grafana_editors` - Edit dashboards
   - `grafana_viewers` - View only

### **Jellyfin Groups**

1. In Authentik, create/verify groups:
   - `jellyfin_users` - Can access Jellyfin
   - `jellyfin_admins` - Admin privileges in Jellyfin

### **Assign Users to Groups**

1. Go to **Directory** → **Users**
2. Click on a user
3. Go to **Groups** tab
4. Click **Add to existing group**
5. Select appropriate groups
6. Click **Add**

---

## 🏁 Verification Checklist

- [ ] Authentik admin account created at `http://auth.frey`
- [ ] Grafana SSO works (`http://grafana.frey`)
- [ ] Home Assistant OIDC configured
- [ ] Immich OAuth enabled
- [ ] Audiobookshelf OIDC configured
- [ ] Jellyfin LDAP plugin installed and configured
- [ ] Jellyfin API token generated for Mopidy
- [ ] Jellyfin Smart Playlist plugin installed
- [ ] Audiobookshelf API token generated
- [ ] Authentik user groups configured
- [ ] Test users assigned to appropriate groups

---

## 🆘 Troubleshooting

### **OAuth/OIDC Errors**

- **"Redirect URI Error"**: Check that the service's redirect URI matches one configured in Authentik blueprint
- **"Invalid Client"**: Verify client ID and secret match between service and Authentik
- **"Connection Refused"**: Ensure Authentik is running (`docker ps | grep authentik`)

### **LDAP Connection Issues** (Jellyfin)

- Verify `authentik-ldap-outpost` container is running
- Check LDAP bind password in `secrets.yml` matches Authentik
- Ensure Jellyfin and Authentik are on the same Docker network

### **Mopidy Not Connecting to Jellyfin**

- Verify Jellyfin API token is correct in `secrets.yml`
- Check Mopidy logs: `docker logs mopidy`
- Ensure Jellyfin is accessible from Mopidy container: `docker exec mopidy curl http://jellyfin.frey:8096`

### **Audiobook Bridge Not Playing**

- Check Audiobookshelf API token is correct
- Verify audio device is accessible: `docker exec audiobook-bridge ls -la /dev/snd`
- Check bridge logs: `docker logs audiobook-bridge`

---

## 📚 Additional Resources

- **Authentik Documentation**: https://goauthentik.io/docs/
- **Home Assistant OAuth**: https://www.home-assistant.io/integrations/auth/
- **Jellyfin LDAP Plugin**: https://github.com/jellyfin/jellyfin-plugin-ldapauth
- **Mopidy Documentation**: https://docs.mopidy.com/
- **Audiobookshelf API**: https://api.audiobookshelf.org/

---

**Last Updated**: 2025-10-31
