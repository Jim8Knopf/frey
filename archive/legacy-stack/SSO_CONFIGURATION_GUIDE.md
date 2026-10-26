# Authentik SSO Configuration Guide

## Status: SSL Certificates Working ✅

**Date:** November 6, 2025
**Certificates Issued:** 15 services
**Certificate Authority:** Step CA (Frey CA)

### Successfully Secured Services:
- ✅ https://auth.frey (Authentik SSO)
- ✅ https://audiobookshelf.frey
- ✅ https://grafana.frey
- ✅ https://immich.frey
- ✅ https://jellyfin.frey
- ✅ https://portainer.frey
- ✅ https://traefik.frey
- ✅ https://jellyseerr.frey
- ✅ https://cookbook.frey
- ✅ https://qbittorrent.frey
- ✅ https://sonarr.frey
- ✅ https://radarr.frey
- ✅ https://prowlarr.frey
- ✅ https://bazarr.frey
- ✅ https://lidarr.frey

---

## Step 1: Access Your Services via HTTPS

From a device on your FreyHub WiFi network (10.20.0.x), you can now access:

```
https://audiobookshelf.frey
https://auth.frey
https://grafana.frey
... etc
```

**Note:** You must have the Step CA root certificate installed on your device for trusted HTTPS. See Android certificate section below.

---

## Step 2: Configure Authentik SSO for Audiobookshelf

Audiobookshelf **cannot** be configured via environment variables. You must configure SSO manually through the web UI.

### 2.1 Login to Audiobookshelf Admin

1. Go to https://audiobookshelf.frey
2. Login with your local Audiobookshelf admin account
3. Click Settings (gear icon) → Authentication

### 2.2 Enable OpenID Connect

1. In Authentication settings, scroll to **OpenID Connect**
2. Click **Enable OpenID Connect**
3. Configure with these values:

| Setting | Value |
|---------|-------|
| **Issuer URL** | `https://auth.frey/application/o/audiobookshelf/` |
| **Authorization URL** | `https://auth.frey/application/o/authorize/` |
| **Token URL** | `https://auth.frey/application/o/token/` |
| **Userinfo URL** | `https://auth.frey/application/o/userinfo/` |
| **Client ID** | `audiobookshelf` |
| **Client Secret** | See `group_vars/all/secrets.yml`: `audiobookshelf_oidc_client_secret` |
| **Button Text** | `Login with Authentik` |
| **Auto Register** | ✅ Enabled |
| **Auto Launch** | ❌ Disabled (allows local login fallback) |

4. Click **Save**

### 2.3 Test SSO Login

1. Logout of Audiobookshelf
2. Return to https://audiobookshelf.frey
3. Click **"Login with Authentik"** button
4. You'll be redirected to https://auth.frey
5. Login with your Authentik credentials
6. You'll be redirected back to Audiobookshelf, now logged in!

---

## Step 3: Configure SSO for Other Services

### Grafana (Already Configured via Environment Variables) ✅

Grafana SSO is configured automatically through the docker-compose environment variables. Just visit https://grafana.frey and click **"Sign in with Authentik"**.

### Immich (Requires Authentik Provider Setup)

**In Authentik Admin:**
1. Go to https://auth.frey
2. Login as admin
3. Navigate to Applications → Providers
4. Create OAuth2/OIDC Provider:
   - Name: `immich`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Redirect URIs: `https://immich.frey/auth/login`, `https://immich.frey/user-settings`, `app.immich:///oauth-callback`
   - Signing Key: Select your Frey CA key
5. Create Application:
   - Name: `Immich`
   - Slug: `immich`
   - Provider: Select the provider you just created
6. Save

**In Immich:**
1. Go to https://immich.frey
2. Login as admin
3. Go to Administration → Settings → OAuth
4. Enable OAuth Authentication
5. Configure:
   - Issuer URL: `https://auth.frey/application/o/immich/`
   - Client ID: `immich`
   - Client Secret: (from Authentik provider)
   - Scope: `openid profile email`
   - Auto Register: Enabled
   - Auto Launch: Disabled

### Jellyfin (Uses LDAP - Already Configured) ✅

Jellyfin is configured to use Authentik's LDAP interface. The LDAP plugin should already be installed and configured via the docker-compose template.

**To verify:**
1. Go to https://jellyfin.frey
2. Dashboard → Plugins → LDAP Authentication
3. Configuration should show:
   - LDAP Server: `ak-outpost-jellyfin-ldap-outpost`
   - Port: `3389`
   - Base DN: `dc=ldap,dc=goauthentik,dc=io`

Users in the `jellyfin_users` group in Authentik can now login to Jellyfin with their Authentik credentials.

---

## Step 4: Verify Authentik Providers

Check that all application providers are configured in Authentik:

### Via Authentik Web UI:
1. Go to https://auth.frey
2. Login as admin
3. Navigate to **Applications**
4. You should see applications for:
   - Audiobookshelf (OAuth2/OIDC)
   - Grafana (OAuth2/OIDC)
   - Home Assistant (OAuth2/OIDC)
   - Immich (OAuth2/OIDC)
   - Mealie/Cookbook (OAuth2/OIDC)
   - Jellyfin LDAP Outpost (LDAP Provider)

### Via Blueprint Verification:
Check that blueprints were applied:
```bash
ssh frey "ls -la /opt/frey/appdata/authentik/blueprints/"
```

Expected files:
- `00-groups.yaml`
- `01-service-accounts.yaml`
- `10-oidc-immich.yaml`
- `11-oidc-audiobookshelf.yaml`
- `12-oidc-grafana.yaml`
- `13-oidc-homeassistant.yaml`
- `14-oidc-mealie.yaml`
- `20-ldap-jellyfin.yaml`

---

## Android Certificate Installation (For App-Level SSL)

### Current Status:
✅ You've already installed the Step CA root certificate at **user level** on Android 15
❌ Android 15's "VPN and app user certificate" option is **NOT** for CA root certificates

### Understanding Android Certificate Levels:

| Level | Purpose | Use Case |
|-------|---------|----------|
| **User CA** | Trusted root certificates | HTTPS websites (browsers, apps) |
| **VPN & App** | Client certificates with private keys | VPN authentication, client cert auth |

### Your Setup (Correct!):
Your Step CA root certificate is installed at **user level**, which is correct for HTTPS websites. This allows:
- ✅ Chrome/Firefox to trust https://audiobookshelf.frey
- ✅ Mobile apps to trust SSL connections
- ✅ No browser warnings

### Why "VPN & App" Failed:
The "VPN and app user certificate" option expects a **client certificate** (certificate + private key) for authentication purposes, NOT a root CA certificate. This is used for:
- VPN connections requiring client certificates
- Enterprise apps with mutual TLS authentication
- Not applicable for your use case

### To Verify Your Certificate:
1. Settings → Security → More security settings → Encryption & credentials
2. Trusted credentials → User tab
3. Look for "Frey CA Root CA" in the list
4. It should show as active

### Export Certificate for Other Devices:

**From server:**
```bash
scp frey:/opt/frey/appdata/step-ca/certs/root_ca.crt ~/Downloads/frey-ca-root.crt
```

**Install on other devices:**
- **iOS/iPadOS**: AirDrop → Settings → General → VPN & Device Management → Install → Trust
- **Windows**: Right-click → Install Certificate → Trusted Root Certification Authorities
- **macOS**: Double-click → Add to Keychain → Trust → Always Trust
- **Linux**: Copy to `/usr/local/share/ca-certificates/` → `sudo update-ca-certificates`
- **Firefox (all platforms)**: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import

---

## Troubleshooting

### Issue: "Certificate not trusted" in browser

**Solution:**
1. Verify Step CA root certificate is installed
2. Check certificate was installed as "User CA" not "VPN & App"
3. Restart browser/app
4. Clear browser cache

### Issue: SSO login redirects to wrong URL

**Solution:**
1. Check Authentik provider redirect URIs include both HTTP and HTTPS
2. Verify GF_SERVER_ROOT_URL in Grafana matches `https://grafana.frey`
3. Check service environment variables use `https://` not `http://`

### Issue: Can't access services from phone

**Solution:**
1. Verify phone is connected to FreyHub WiFi (10.20.0.x IP)
2. Check DNS is resolving (ping `auth.frey` from Terminal app)
3. Install Step CA root certificate if not already done

---

## Success Criteria

✅ All 15 services accessible via HTTPS without warnings
✅ Audiobookshelf SSO configured and working
✅ Grafana SSO working
✅ Jellyfin LDAP authentication working
✅ Step CA root certificate installed on all devices
✅ No browser certificate warnings

---

## Next Steps

1. ✅ Access https://audiobookshelf.frey from your Android device
2. ⏳ Configure Audiobookshelf OIDC in web UI (manual step required)
3. ⏳ Test SSO login flow
4. ⏳ Configure remaining services (Immich, Home Assistant, etc.)
5. ⏳ Create Authentik user accounts for family/friends

---

## Reference

- Authentik Admin: https://auth.frey
- Traefik Dashboard: https://traefik.frey
- Portainer: https://portainer.frey
- Step CA Health: `ssh frey "docker exec step-ca step ca health"`
- Certificate List: `ssh frey "docker exec traefik cat /acme/acme.json | jq -r '.\"step-ca\".Certificates[]? | .domain'"`
