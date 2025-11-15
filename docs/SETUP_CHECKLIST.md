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

- [ ] Access `https://grafana.frey`
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

## 🗣️ Configure Voice Services (Optional)

### Piper TTS (Text-to-Speech)
- [ ] Set `homeassistant.services.piper.enabled: true` in main.yml
- [ ] Deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation`
- [ ] Verify container running: `ssh frey "docker ps | grep piper"`
- [ ] Add to Home Assistant `configuration.yaml`:
  ```yaml
  tts:
    - platform: wyoming
      uri: "tcp://piper:10200"
  ```
- [ ] Test TTS in Home Assistant: Services → TTS → Speak

### Wyoming Whisper STT (Speech-to-Text) - Optional, Resource-Intensive
- [ ] Set `homeassistant.services.wyoming_whisper.enabled: true` in main.yml
- [ ] Choose model size: `tiny-int8` (fastest), `base-int8`, or `small-int8`
- [ ] Deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation`
- [ ] Verify container running: `ssh frey "docker ps | grep whisper"`
- [ ] Configure in Home Assistant: Settings → Voice Assistants

---

## 🌐 Configure WiFi Automatic Roaming (Optional)

### Enable WiFi Roaming
- [ ] Set `network.wifi.roaming.enabled: true` in main.yml
- [ ] Configure `client_interface: "wlan0"` (or your WiFi interface)
- [ ] (Optional) Add known networks to `networks.wifi.known` list
- [ ] Deploy: `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags wifi`
- [ ] Verify service: `ssh frey "sudo systemctl status frey-wifi-roaming"`
- [ ] Check logs: `ssh frey "sudo journalctl -u frey-wifi-roaming -f"`

### Home Assistant MQTT Integration
- [ ] Add MQTT sensors to Home Assistant `configuration.yaml`:
  ```yaml
  mqtt:
    sensor:
      - name: "Frey WiFi Network"
        state_topic: "frey/wifi/roaming/status/current_ssid"
      - name: "Frey WiFi Signal"
        state_topic: "frey/wifi/roaming/status/signal_dbm"
    binary_sensor:
      - name: "Frey Has Internet"
        state_topic: "frey/wifi/roaming/status/has_internet"
  ```
- [ ] Test: Check if sensors appear in Home Assistant
- [ ] (Optional) Add control button for manual rescan

### Verify WiFi Roaming
- [ ] View network history: `ssh frey "sudo cat /var/lib/frey/wifi-network-history.json | jq"`
- [ ] Test automatic connection to a public WiFi
- [ ] Check captive portal bypass (if applicable)
- [ ] Verify FreyHub AP remains accessible

**See full guide**: `docs/WIFI_ROAMING_SETUP.md`

---

## 🍳 Configure Cookbook (Mealie) - Optional

- [ ] Access `http://cookbook.frey`
- [ ] Create admin account (first-time setup)
- [ ] Settings → Set preferences (units, language, etc.)
- [ ] Test recipe scraping: Add recipe by URL
- [ ] Create meal plan for the week
- [ ] Generate shopping list
- [ ] (Optional) Import existing recipes

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

### SSO/Authentication
- [ ] Test Grafana SSO: `https://grafana.frey` → Sign in with Authentik
- [ ] Test Home Assistant SSO: Log out and log in via Authentik
- [ ] Test Immich OAuth: Log out and use "Login with OAuth"
- [ ] Test Audiobookshelf SSO: Log out and use "Login with Authentik"
- [ ] Test Jellyfin LDAP: Log out and log in with Authentik credentials

### Media Services
- [ ] Test Jellyfin playback: Play a movie/TV show
- [ ] Test Sonarr: Add a TV series, check if episodes download
- [ ] Test Radarr: Add a movie, check if it downloads
- [ ] Test Audiobookshelf: Play an audiobook, verify progress tracking
- [ ] (Optional) Test Mopidy: Access `http://mopidy.frey:6680`, check Jellyfin integration

### Automation & Voice
- [ ] Test Home Assistant: Control a device or trigger an automation
- [ ] (Optional) Test Piper TTS: Use TTS service in Home Assistant
- [ ] (Optional) Test voice assistant: Test wake word and voice commands
- [ ] Test n8n: Create a simple workflow (e.g., webhook → notification)

### Monitoring
- [ ] Test Grafana dashboards: View system metrics
- [ ] Test Prometheus: Query metrics at `http://prometheus.frey`
- [ ] Test Uptime Kuma: Check service status at `http://uptime-kuma.frey`
- [ ] Test log aggregation: View logs in Grafana → Explore → Loki

### Network & WiFi
- [ ] Test DNS resolution: `nslookup jellyfin.frey` from WiFi client
- [ ] Test Traefik routing: All services accessible via `.frey` domain
- [ ] Test FreyHub WiFi: Connect device to FreyHub, access services
- [ ] (Optional) Test WiFi roaming: Move to public WiFi, verify automatic connection
- [ ] (Optional) Test captive portal bypass: Connect to portal network, check auto-auth

### Photos & Other Services
- [ ] Test Immich: Upload a photo from mobile app, check face detection
- [ ] (Optional) Test Cookbook: Add recipe, create meal plan, generate shopping list
- [ ] Test Portainer: View and manage containers at `http://portainer.frey`

---

## 📝 Documentation

- [ ] Read `docs/QUICK_SETUP.md` - Ultra-brief 30-minute setup guide
- [ ] Read `docs/USER_GUIDE.md` - Comprehensive feature reference
- [ ] Read `docs/POST_INSTALLATION_MANUAL_STEPS.md` - Detailed SSO configuration
- [ ] (Optional) Read `docs/WIFI_ROAMING_SETUP.md` - WiFi automation deep dive
- [ ] Bookmark `README.md` for quick reference and architecture overview
- [ ] Save `docs/SETUP_CHECKLIST.md` (this file) for tracking progress

---

## ✅ All Done!

When all boxes are checked, your Frey system is fully configured and operational!

**Enjoy your self-hosted home server! 🎉**
