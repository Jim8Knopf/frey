# LDAP & SSO Authentication Issues

## Issue 1: Jellyfin LDAP Authentication - NOT FIXED

### Problem
- **Error**: "Connect (Success); Bind: Invalid Credentials"
- **Goal**: Use dedicated `ldap_bind` service user (not akadmin) for LDAP authentication
- **Status**: ❌ NOT RESOLVED

### Root Causes Identified
1. **User Type Issue**: ldap_bind user was created as `type: service_account`
   - Service accounts in Authentik only support token authentication
   - LDAP bind requires password authentication
   - **Fix Applied**: Changed to `type: internal` in `01-service-accounts.yaml.j2:21`

2. **Bind Mode Issue**: LDAP provider using `bind_mode: direct`
   - Direct mode = full auth flow every time (slow)
   - **Fix Applied**: Changed to `bind_mode: cached` in `20-ldap-jellyfin.yaml.j2:20`

3. **Group Membership Issue**: ldap_bind user not in jellyfin_users group
   - Required for LDAP search permissions
   - **Fix Applied**: Added group membership in `01-service-accounts.yaml.j2:29-36`

### Files Modified
- `/home/jim/Projects/frey/roles/infrastructure/templates/authentik-blueprints/01-service-accounts.yaml.j2`
  - Line 21: Changed `type: service_account` → `type: internal`
  - Line 27: Added `password: "{{ authentik_ldap_bind_password }}"`
  - Lines 29-36: Added group membership to `jellyfin_users`

- `/home/jim/Projects/frey/roles/infrastructure/templates/authentik-blueprints/20-ldap-jellyfin.yaml.j2`
  - Line 20: Changed `bind_mode: direct` → `bind_mode: cached`

### Deployment Status
- ✅ Infrastructure stack deployed (4 changes)
- ✅ Media stack deployed (3 changes)
- ❌ Authentication still failing

### LDAP Configuration
- **Server**: `10.20.0.1:389`
- **Bind User DN**: `cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io`
- **Bind Password**: `c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2` (from secrets.yml:83)
- **Base DN**: `ou=users,dc=ldap,dc=goauthentik,dc=io`
- **Search Filter**: `(memberOf=cn=jellyfin_users,ou=groups,dc=ldap,dc=goauthentik,dc=io)`

### Next Steps
1. Verify Authentik blueprints actually applied (check Authentik UI)
2. Verify ldap_bind user exists in Authentik
3. Test LDAP bind manually with ldapsearch
4. Check LDAP outpost logs: `docker logs ak-outpost-jellyfin-ldap-outpost`
5. Install Jellyfin LDAP plugin if not already installed

---

## Issue 2: Audiobookshelf SSO - NEW ISSUE

### Problem
- **Error**: "Unauthorized"
- **Status**: ❌ NEW ISSUE - User will handle deployment

### OIDC Configuration (from secrets.yml)
- **Client ID**: `audiobookshelf` (configured in blueprint)
- **Client Secret**: `password` (from secrets.yml:80)
- **Issuer URL**: `http://auth.frey:9300/application/o/audiobookshelf/`

### Blueprint Location
- `/home/jim/Projects/frey/roles/infrastructure/templates/authentik-blueprints/11-oidc-audiobookshelf.yaml.j2`

### Possible Causes
1. Client secret mismatch between Authentik and Audiobookshelf
2. Redirect URI not configured correctly
3. User not in required group
4. Blueprint not applied after changes
5. Audiobookshelf OIDC settings incorrect

### Container Status
- `ghcr.io/advplyr/audiobookshelf:latest` - Running (Up 3 hours)
- Port: Check media docker-compose for port mapping

---

## Related Files
- `/home/jim/Projects/frey/group_vars/all/secrets.yml` - All authentication secrets
- `/home/jim/Projects/frey/roles/infrastructure/templates/authentik-blueprints/` - SSO blueprints
- `/home/jim/Projects/frey/roles/media/templates/docker-compose-media.yml.j2` - Jellyfin config

## Deployment Commands
```bash
# Deploy infrastructure (Authentik blueprints)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure --vault-password-file .vault_pass

# Deploy media (Jellyfin + Audiobookshelf)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags media --vault-password-file .vault_pass

# Check container logs
ssh frey "docker logs ak-outpost-jellyfin-ldap-outpost --tail 100"
ssh frey "docker logs authentik_server --tail 100"
ssh frey "docker logs jellyfin --tail 100"
```
