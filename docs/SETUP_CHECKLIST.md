# ✅ Frey Setup Checklist

Use this checklist to track your deployment and configuration progress.

---

## 📦 Initial Deployment

- [ ] Clone repository to local machine
- [ ] Configure `inventory/hosts.yml` with target Pi details
- [ ] Update `group_vars/all/main.yml` with desired features
- [ ] Generate vault password: `openssl rand -base64 32 > .vault_pass`
- [ ] Review/update `group_vars/all/secrets.yml` (encrypted with ansible-vault)
- [ ] Run initial deployment: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml`
- [ ] Verify all containers are running: `ssh frey "docker ps"`

---

## 🔐 Enable SSO (Authentik)

- [ ] Set `features.authentication: true` in main.yml
- [ ] Deploy infrastructure: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure`
- [ ] Access `http://auth.frey`
- [ ] Create Authentik admin account
- [ ] Verify blueprints applied (check Authentik logs)

---

## 📊 Configure Grafana

- [ ] Access `http://grafana.frey`
- [ ] Click "Sign in with Authentik"
- [ ] Verify successful login
- [ ] **Status**: ✅ Works automatically (no manual steps)

---

## 🏠 Configure Home Assistant

- [ ] Set `features.homeassistant: true` and `homeassistant.services.homeassistant.enabled: true`
- [ ] Deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation`
- [ ] Access `http://homeassistant.frey`
- [ ] Create initial admin account
- [ ] Settings → People → Add Integration → "OpenID Connect"
- [ ] Enter configuration:
  - Name: `Authentik`
  - Client ID: `homeassistant`
  - Client Secret: (from secrets.yml)
  - Issuer: `http://auth.frey/application/o/homeassistant/`
- [ ] Test SSO login

---

## 📸 Configure Immich

- [ ] Access `http://immich.frey`
- [ ] Create initial admin account
- [ ] Administration → Settings → OAuth Authentication
- [ ] Enable OAuth:
  - Issuer URL: `http://auth.frey/application/o/immich/`
  - Client ID: `immich`
  - Client Secret: (from secrets.yml)
  - Auto Register: Yes
- [ ] Test OAuth login

---

## 📚 Configure Audiobookshelf

- [ ] Access `http://audiobookshelf.frey`
- [ ] Create initial admin account
- [ ] Settings → Authentication → OpenID Connect
- [ ] Enter Issuer URL: `http://auth.frey/application/o/audiobookshelf/`
- [ ] Click "Auto Populate"
- [ ] Enter:
  - Client ID: `audiobookshelf`
  - Client Secret: (from secrets.yml)
- [ ] Test SSO login

---

## 🎬 Configure Jellyfin

- [ ] Access `http://jellyfin.frey`
- [ ] Complete setup wizard
- [ ] Dashboard → Plugins → Catalog
- [ ] Install "LDAP Authentication" plugin
- [ ] Restart Jellyfin: `ssh frey "docker restart jellyfin"`
- [ ] Dashboard → Plugins → LDAP Authentication → Settings
- [ ] Configure LDAP:
  - Server: `authentik-ldap-outpost`
  - Port: `389`
  - Base DN: `dc=ldap,dc=goauthentik,dc=io`
  - Bind User: `cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io`
  - Bind Password: (from secrets.yml)
  - User Filter: `(memberOf=cn=jellyfin_users,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
  - Admin Filter: `(memberOf=cn=jellyfin_admins,ou=groups,dc=ldap,dc=goauthentik,dc=io)`
- [ ] Test LDAP login

---

## 🎵 Configure Music Playback (Optional)

### Jellyfin Smart Playlist Plugin
- [ ] Jellyfin Dashboard → Plugins → Catalog
- [ ] Install "Smart Playlist" plugin
- [ ] Restart Jellyfin
- [ ] Create tag-based playlists (e.g., tags: `me`, `dad`)

### Jellyfin API Token (for Mopidy)
- [ ] Jellyfin Dashboard → API Keys
- [ ] Create new key: "Mopidy Integration"
- [ ] Copy token
- [ ] Update secrets.yml: `jellyfin_api_token: "YOUR_TOKEN"`
- [ ] Set `media.services.mopidy.enabled: true` in main.yml
- [ ] Redeploy media: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media`
- [ ] Test: Access `http://mopidy.frey:6680`

---

## 🎧 Configure Audiobook Playback (Optional)

- [ ] Access Audiobookshelf → Settings → Users → Your User
- [ ] Generate API Token
- [ ] Copy token
- [ ] Update secrets.yml: `audiobookshelf_api_token: "YOUR_TOKEN"`
- [ ] Set `media.services.audiobook_bridge.enabled: true` in main.yml
- [ ] Redeploy media: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media`
- [ ] Copy script to container:
  ```bash
  ssh frey
  docker cp roles/media/templates/audiobook-bridge/play_book.py audiobook-bridge:/app/
  ```
- [ ] Test playback: `docker exec audiobook-bridge python3 /app/play_book.py --book-id <ID>`

---

## 👥 Configure User Groups in Authentik

### Grafana Groups
- [ ] `http://auth.frey` → Directory → Groups
- [ ] Verify groups exist: `grafana_admins`, `grafana_editors`, `grafana_viewers`

### Jellyfin Groups
- [ ] Verify groups exist: `jellyfin_users`, `jellyfin_admins`

### Assign Users
- [ ] Directory → Users → Select user
- [ ] Groups tab → Add to existing group
- [ ] Add user to appropriate groups
- [ ] Repeat for all users

---

## 🧪 Final Testing

- [ ] Test Grafana SSO: `http://grafana.frey` → Sign in with Authentik
- [ ] Test Home Assistant SSO: Log out and log in via Authentik
- [ ] Test Immich OAuth: Log out and use "Login with OAuth"
- [ ] Test Audiobookshelf SSO: Log out and use "Login with Authentik"
- [ ] Test Jellyfin LDAP: Log out and log in with Authentik credentials
- [ ] Test Mopidy: Access `http://mopidy.frey:6680`, check Jellyfin integration
- [ ] Test DNS resolution: `nslookup auth.frey` from WiFi client
- [ ] Test Traefik routing: All services accessible via `.frey` domain

---

## 📝 Documentation

- [ ] Read `docs/POST_INSTALLATION_MANUAL_STEPS.md` for detailed instructions
- [ ] Bookmark `docs/QUICK_REFERENCE.md` for quick lookups
- [ ] Save `docs/SETUP_CHECKLIST.md` (this file) for tracking progress

---

## ✅ All Done!

When all boxes are checked, your Frey system is fully configured and operational!

**Enjoy your self-hosted home server! 🎉**
