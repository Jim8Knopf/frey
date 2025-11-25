# Authelia Forward Authentication for *arr Apps

Enable SSO for services that don't support OIDC natively (Sonarr, Radarr, Prowlarr, etc.) using Authelia's forward authentication.

## What is Forward Auth?

Forward auth protects services by placing Authelia in front of them:

1. User visits `https://sonarr.frey`
2. Traefik checks with Authelia: "Is this user authenticated?"
3. If **not authenticated** → Authelia shows login page
4. If **authenticated** → Authelia passes user info to Sonarr
5. Sonarr trusts the authentication and shows the app

**Result:** Single sign-on without the app needing OIDC support!

## Which Services Support Forward Auth?

**Already working with your Authelia config:**
- ✅ Sonarr (TV shows)
- ✅ Radarr (Movies)
- ✅ Lidarr (Music)
- ✅ Readarr (Books)
- ✅ Prowlarr (Indexer manager)
- ✅ Bazarr (Subtitles)
- ✅ qBittorrent (Torrent client)
- ✅ Jellyseerr (Request system)
- ✅ Any service behind Traefik

**Access control already configured:**
Your Authelia config already allows access to `*.frey` for users in:
- `admin_users` group
- `media_users` group
- `monitoring_users` group
- `automation_users` group

---

## How to Enable Forward Auth

### Option 1: Add Traefik Middleware to docker-compose

Edit `/opt/frey/stacks/media/docker-compose.yml` and add the forward auth middleware to each service:

**Example for Sonarr:**

```yaml
sonarr:
  image: linuxserver/sonarr:latest
  container_name: sonarr
  # ... existing config ...
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.sonarr.rule=Host(`sonarr.frey`)"
    - "traefik.http.routers.sonarr.entrypoints=websecure"
    - "traefik.http.routers.sonarr.tls=true"
    - "traefik.http.routers.sonarr.tls.certresolver=step-ca"
    - "traefik.http.services.sonarr.loadbalancer.server.port=8989"

    # ADD THESE LINES FOR FORWARD AUTH:
    - "traefik.http.routers.sonarr.middlewares=authelia@docker"
    - "traefik.http.middlewares.authelia.forwardauth.address=http://authelia:9091/api/verify?rd=https://auth.frey"
    - "traefik.http.middlewares.authelia.forwardauth.trustForwardHeader=true"
    - "traefik.http.middlewares.authelia.forwardauth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email"
```

**Repeat for each *arr service:** Radarr, Lidarr, Prowlarr, Bazarr, qBittorrent, Jellyseerr

---

### Option 2: Update Ansible Role (Recommended)

Update your media stack docker-compose template to automatically add forward auth:

**Edit:** `roles/media/templates/docker-compose-media.yml.j2`

**Find the labels section** (around line 95-110) and add:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=proxy"
  - "traefik.http.routers.{{ service_name }}.rule=Host(`{{ service_name }}.{{ network.domain_name }}`)"
  - "traefik.http.routers.{{ service_name }}.entrypoints=websecure"
  - "traefik.http.routers.{{ service_name }}.tls=true"
  - "traefik.http.routers.{{ service_name }}.tls.certresolver=step-ca"
  - "traefik.http.services.{{ service_name }}.loadbalancer.server.port={{ service_config.port }}"

  # ADD FORWARD AUTH FOR *ARR SERVICES:
{% if service_name in ['sonarr', 'radarr', 'lidarr', 'readarr', 'prowlarr', 'bazarr', 'qbittorrent', 'jellyseerr'] %}
  - "traefik.http.routers.{{ service_name }}.middlewares=authelia@docker"
  - "traefik.http.middlewares.authelia.forwardauth.address=http://authelia:9091/api/verify?rd=https://auth.{{ network.domain_name }}"
  - "traefik.http.middlewares.authelia.forwardauth.trustForwardHeader=true"
  - "traefik.http.middlewares.authelia.forwardauth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email"
{% endif %}
```

**Then redeploy:**

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media --vault-password-file .vault_pass
```

---

## Testing Forward Auth

1. **Logout from Authelia:**
   - Open https://auth.frey
   - Click logout (if logged in)

2. **Try to access Sonarr:**
   - Open https://sonarr.frey
   - You should be redirected to Authelia login page

3. **Login with LLDAP user:**
   - Enter username/password from LLDAP
   - Make sure user is in `media_users` or `admin_users` group

4. **Verify access:**
   - After login, you should be redirected back to Sonarr
   - Sonarr should open without asking for credentials
   - User is authenticated via Authelia!

5. **Test other services:**
   - Open https://radarr.frey - should work immediately (already authenticated)
   - Open https://prowlarr.frey - should work immediately
   - Open https://jellyfin.frey - uses LDAP, separate login

---

## Troubleshooting

### "Forbidden" or "Access Denied"

**Cause:** User not in the correct group

**Fix:**
1. Open LLDAP web UI (http://lldap.frey:17170)
2. Click on the user
3. Add user to `media_users` or `admin_users` group
4. Try accessing service again

### Redirect loop

**Cause:** Forward auth middleware not configured correctly

**Fix:**
1. Check Traefik labels have correct forward auth address
2. Make sure `authelia` container is accessible from Traefik
3. Verify both containers are on same Docker network

```bash
# Check networks
ssh frey "docker inspect authelia | grep -A 10 Networks"
ssh frey "docker inspect sonarr | grep -A 10 Networks"

# Both should have 'proxy' network
```

### Still asks for Sonarr password

**Cause:** Sonarr's built-in authentication is still enabled

**Fix:**
1. Open Sonarr → Settings → General
2. Scroll to "Security"
3. Set **Authentication Method** to:
   - **"External"** (trusts proxy headers) OR
   - **"None"** (disables authentication - only safe if forward auth is working!)
4. Save and reload

**Repeat for all *arr apps**

---

## Access Control Rules

Your Authelia config already has these rules (in `roles/authentication/templates/authelia-configuration.yml.j2`):

```yaml
access_control:
  default_policy: deny  # Deny by default

  rules:
    # Allow authenticated users in these groups
    - domain:
        - "*.frey"  # Covers sonarr.frey, radarr.frey, etc.
      policy: one_factor  # or two_factor if MFA enabled
      subject:
        - "group:admin_users"      # Full access
        - "group:media_users"      # Media services access
        - "group:monitoring_users" # Monitoring access
        - "group:automation_users" # Automation access
```

**To customize access:**

1. **Make Sonarr admin-only:**

```yaml
- domain:
    - "sonarr.frey"
    - "radarr.frey"
  policy: one_factor
  subject:
    - "group:admin_users"  # Only admins
```

2. **Allow all authenticated users:**

```yaml
- domain:
    - "*.frey"
  policy: one_factor
  # No subject = any authenticated user
```

3. **Different policies per service:**

```yaml
# Admin-only services
- domain:
    - "prowlarr.frey"
    - "qbittorrent.frey"
  policy: one_factor
  subject:
    - "group:admin_users"

# User-accessible services
- domain:
    - "jellyseerr.frey"
  policy: one_factor
  subject:
    - "group:media_users"
    - "group:admin_users"
```

After changing rules, redeploy:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags authentication --vault-password-file .vault_pass
```

---

## Advanced: Per-User Access Control

**Example:** Only allow specific users to access Sonarr:

```yaml
- domain:
    - "sonarr.frey"
  policy: one_factor
  subject:
    - "user:jason"
    - "user:admin"
```

**Example:** Require 2FA for download clients:

```yaml
- domain:
    - "qbittorrent.frey"
  policy: two_factor  # Requires 2FA to be configured
  subject:
    - "group:admin_users"
```

---

## Benefits of Forward Auth

✅ **Single sign-on** - Login once, access all services
✅ **Centralized user management** - All users in LLDAP
✅ **Fine-grained access control** - Per-service, per-group, per-user
✅ **Works with any service** - Even if app doesn't support OIDC
✅ **Secure** - Authentication handled by Authelia, not individual apps
✅ **Session management** - Logout from one place logs out everywhere

---

## Summary

**To enable forward auth for *arr apps:**

1. Add Traefik middleware to each service's labels
2. Set *arr apps to "External" authentication mode
3. Ensure users are in `media_users` or `admin_users` group
4. Access services - Authelia handles authentication!

**User experience:**
1. Visit https://sonarr.frey
2. If not logged in → Authelia login page
3. Login with LLDAP credentials
4. Redirected to Sonarr, fully authenticated
5. Access any other *arr app → already logged in!

**Time to set up:** 5-10 minutes to add labels, then it just works!
