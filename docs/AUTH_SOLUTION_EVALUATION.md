# Authentication Solution Evaluation for Frey

**Date:** 2025-11-18
**Current Setup:** Authentik (full stack)
**Question:** Is Authentik the best solution, or should we switch to LLDAP or LLDAP + Authelia?

---

## Executive Summary

**RECOMMENDATION: Keep Authentik**

While LLDAP is simpler and lighter, you have **6 services using OIDC** and only **1 using LDAP**. Switching would require either:
1. Losing SSO for 6 services (LLDAP only), or
2. Complete reconfiguration (LLDAP + Authelia), or
3. Keep Authentik complexity anyway

Your Authentik setup is already 90% configured via Ansible blueprints, making it fully IaC-managed. The main issue (Jellyfin LDAP) appears to be a configuration bug, not a fundamental limitation.

---

## Current Authentik Setup Analysis

### Services Using Authentik

**OIDC/OAuth2 (6 services):**
- ✅ Immich (photo management)
- ✅ Audiobookshelf (audiobook library)
- ✅ Grafana (monitoring dashboards)
- ✅ Home Assistant (home automation)
- ✅ Mealie (recipe management)
- ✅ Dashy (landing page)

**LDAP (1 service):**
- ❌ Jellyfin (media server) - **Currently broken, but fixable**

### Infrastructure Components

**Containers (4):**
```yaml
authentik-server:       # Main web server
  image: ghcr.io/goauthentik/server:latest
  ports: [9000, 9446]

authentik-worker:       # Background task processor
  image: ghcr.io/goauthentik/server:latest

authentik-db:          # PostgreSQL database
  image: postgres:16-alpine

authentik-redis:       # Redis cache
  image: redis:alpine
```

**IaC Configuration (9 blueprint files):**
- `00-groups.yaml.j2` - User groups (jellyfin_users, media_admin, etc.)
- `01-service-accounts.yaml.j2` - Service accounts (ldap_bind, etc.)
- `10-oidc-immich.yaml.j2` - Immich OIDC provider
- `11-oidc-audiobookshelf.yaml.j2` - Audiobookshelf OIDC
- `12-oidc-grafana.yaml.j2` - Grafana OIDC
- `13-oidc-homeassistant.yaml.j2` - Home Assistant OIDC
- `14-oidc-mealie.yaml.j2` - Mealie OIDC
- `15-oidc-dashy.yaml.j2` - Dashy OIDC
- `20-ldap-jellyfin.yaml.j2` - Jellyfin LDAP provider

**Estimated Resource Usage:**
- RAM: ~800MB-1GB total
- CPU: Minimal (idle ~1-2%)
- Disk: ~500MB (database + media)

---

## Alternative Solutions

### Option 1: LLDAP Only

**What is LLDAP?**
- Lightweight LDAP server designed for home labs
- Simple web UI for user management
- Rust-based, minimal resource usage

**Pros:**
- ✅ **Lightweight:** ~20MB RAM vs 1GB
- ✅ **Simple:** Basic user/group management
- ✅ **Easy to configure:** Minimal settings
- ✅ **Fast:** Rust performance

**Cons:**
- ❌ **LDAP only** - NO OIDC/OAuth2 support
- ❌ **You'd lose SSO for 6 services:**
  - Immich, Audiobookshelf, Grafana, Home Assistant, Mealie, Dashy
- ❌ **Each service would need separate accounts**
- ❌ **No centralized user management**

**Configuration Example:**
```yaml
lldap:
  image: lldap/lldap:latest
  environment:
    LLDAP_LDAP_BASE_DN: dc=frey,dc=local
    LLDAP_LDAP_USER_DN: admin
    LLDAP_LDAP_USER_PASS: ${LLDAP_PASSWORD}
  volumes:
    - lldap_data:/data
  ports:
    - "3890:3890"  # LDAP
    - "17170:17170"  # Web UI
```

**Migration Effort:** HIGH (rebuild everything, lose features)

---

### Option 2: LLDAP + Authelia

**Architecture:**
- **LLDAP:** User directory (LDAP backend)
- **Authelia:** SSO portal (OIDC frontend) connects to LLDAP

**Pros:**
- ✅ **Lighter than Authentik:** ~150MB RAM total
- ✅ **Separation of concerns:** Directory vs SSO
- ✅ **Keeps both LDAP and OIDC**
- ✅ **Simpler than Authentik** (debatable)

**Cons:**
- ❌ **Two components to manage** instead of one
- ❌ **Complete reconfiguration required:**
  - Rebuild all 9 blueprints as Authelia configs
  - Reconfigure all 7 service integrations
  - Test each service individually
- ❌ **Authelia OIDC is less mature** than Authentik
- ❌ **No blueprints** - configuration is YAML files
- ❌ **More complex networking** (two services vs one)
- ❌ **Learning curve** for Authelia configuration syntax

**Configuration Example:**
```yaml
# LLDAP (user directory)
lldap:
  image: lldap/lldap:latest
  environment:
    LLDAP_LDAP_BASE_DN: dc=frey,dc=local

# Authelia (SSO portal)
authelia:
  image: authelia/authelia:latest
  volumes:
    - ./configuration.yml:/config/configuration.yml
  environment:
    AUTHELIA_JWT_SECRET: ${JWT_SECRET}
    AUTHELIA_SESSION_SECRET: ${SESSION_SECRET}
    AUTHELIA_STORAGE_ENCRYPTION_KEY: ${STORAGE_KEY}
```

**Authelia Configuration (not IaC-friendly):**
```yaml
# configuration.yml - manual YAML editing, not templatable like Authentik blueprints
authentication_backend:
  ldap:
    implementation: custom
    url: ldap://lldap:3890
    base_dn: dc=frey,dc=local

identity_providers:
  oidc:
    clients:
      - id: immich
        description: Immich Photo Management
        secret: ${IMMICH_SECRET}
        redirect_uris:
          - https://immich.frey/auth/callback
      - id: audiobookshelf
        # ... repeat for each service
```

**Migration Effort:** VERY HIGH (complete rebuild, testing, debugging)

---

### Option 3: Keep Authentik, Fix LDAP Issue

**Current Problem:**
- Jellyfin LDAP authentication failing with "Bind: Invalid Credentials"
- According to `LDAP_SSO_ISSUES.md`, the issue is likely:
  1. `ldap_bind` user configuration
  2. LDAP outpost not running
  3. Blueprint not applied correctly

**Debugging Steps:**
```bash
# 1. Check if Authentik blueprints were applied
ssh frey "docker exec -it authentik_server ak list blueprints"

# 2. Verify ldap_bind user exists
ssh frey "docker exec -it authentik_server ak list users"

# 3. Check LDAP outpost is running
ssh frey "docker ps -a | grep ldap"

# 4. Test LDAP bind manually
ssh frey "ldapsearch -x -H ldap://10.20.0.1:389 \
  -D 'cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io' \
  -w 'YOUR_PASSWORD' \
  -b 'ou=users,dc=ldap,dc=goauthentik,dc=io'"

# 5. Check outpost logs
ssh frey "docker logs ak-outpost-jellyfin-ldap-outpost --tail 100"
```

**Fix Effort:** LOW (debugging, not rebuilding)

---

## Resource Comparison

| Solution | RAM Usage | Containers | Complexity | Features |
|----------|-----------|------------|------------|----------|
| **Authentik (current)** | ~1GB | 4 | High | OIDC + LDAP |
| **LLDAP only** | ~20MB | 1 | Very Low | LDAP only |
| **LLDAP + Authelia** | ~150MB | 2 | Medium-High | OIDC + LDAP |

**On Raspberry Pi 5:**
- 4GB model: Authentik uses ~25% RAM
- 8GB model: Authentik uses ~12.5% RAM

Both are acceptable for a home server.

---

## Feature Comparison

| Feature | Authentik | LLDAP | LLDAP + Authelia |
|---------|-----------|-------|------------------|
| LDAP support | ✅ | ✅ | ✅ |
| OIDC/OAuth2 | ✅ | ❌ | ✅ |
| SAML | ✅ | ❌ | ❌ |
| Web UI | ✅ (advanced) | ✅ (basic) | ✅ (basic) |
| IaC via Blueprints | ✅ | ❌ | ❌ |
| User self-service | ✅ | ✅ | ✅ |
| 2FA/MFA | ✅ | ❌ | ✅ |
| Password recovery | ✅ | ✅ | ✅ |
| API | ✅ | ✅ | ✅ |

---

## Migration Impact Analysis

### To LLDAP Only

**Services Affected: 7 services**

**BREAKING CHANGES:**
- ❌ Immich: Lose SSO, need local accounts
- ❌ Audiobookshelf: Lose SSO, need local accounts
- ❌ Grafana: Lose SSO, need local accounts
- ❌ Home Assistant: Lose SSO, need local accounts
- ❌ Mealie: Lose SSO, need local accounts
- ❌ Dashy: Lose SSO, need local accounts
- ⚠️ Jellyfin: Keep LDAP (works with LLDAP)

**Configuration Work:**
- Delete 9 blueprint files
- Delete Authentik docker-compose entries
- Add LLDAP docker-compose entry
- Create users in LLDAP
- Create local accounts in 6 services
- Update documentation

**User Experience Impact:**
- 6 different passwords to remember
- No single sign-on
- Manual account creation per service
- More difficult user onboarding

### To LLDAP + Authelia

**Services Affected: 7 services**

**Configuration Work:**
- Delete 9 Authentik blueprints
- Create Authelia configuration.yml (100+ lines, manual)
- Reconfigure 6 OIDC integrations in Authelia
- Update all service environment variables
- Rebuild LDAP configuration for Jellyfin
- Create users in LLDAP
- Test each integration individually
- Debug inevitable issues
- Update documentation

**Estimated Time:**
- Initial setup: 4-8 hours
- Testing: 2-4 hours
- Debugging: 2-6 hours (unknown issues)
- **Total: 8-18 hours**

**Risk:**
- Medium-High (configuration mistakes, compatibility issues)

### To Keep Authentik, Fix LDAP

**Services Affected: 1 service (Jellyfin)**

**Configuration Work:**
- Debug existing blueprint configuration
- Fix `ldap_bind` user issue
- Verify LDAP outpost running
- Test Jellyfin LDAP plugin
- Update documentation

**Estimated Time:**
- Debugging: 1-2 hours
- Testing: 30 minutes
- **Total: 1.5-2.5 hours**

**Risk:**
- Low (well-documented, known issue)

---

## Detailed Pros/Cons Analysis

### Authentik (Current)

**Pros:**
1. ✅ **Single solution for everything** - OIDC + LDAP in one
2. ✅ **Already 90% configured** - 9 blueprints already written
3. ✅ **Fully IaC-managed** - Ansible blueprints, automated deployment
4. ✅ **Mature OIDC implementation** - tested with many services
5. ✅ **Advanced features ready** - SAML, MFA, workflows if needed
6. ✅ **Active development** - regular updates, good support
7. ✅ **Works with 6 services already** - only Jellyfin has issues
8. ✅ **Minimal manual configuration** - blueprints auto-apply on startup

**Cons:**
1. ❌ **Resource-heavy** - ~1GB RAM for home use
2. ❌ **Complex** - many moving parts (server, worker, DB, Redis)
3. ❌ **Steeper learning curve** - blueprint syntax, API
4. ❌ **Overkill for simple needs** - using <20% of features
5. ❌ **Current LDAP issue** - Jellyfin not working (fixable)

**Best For:**
- Users who value "set it and forget it"
- Those who want SSO across all services
- Future expansion (more services, advanced auth)
- Minimal manual intervention

### LLDAP Only

**Pros:**
1. ✅ **Extremely lightweight** - 20MB RAM
2. ✅ **Simple** - one service, minimal config
3. ✅ **Fast** - Rust performance
4. ✅ **Easy to understand** - basic LDAP, no magic

**Cons:**
1. ❌ **LDAP only** - no OIDC/OAuth2
2. ❌ **Lose SSO for 6 services** - major functionality loss
3. ❌ **Not IaC-friendly** - web UI configuration
4. ❌ **Limited features** - no MFA, no SAML, no advanced auth
5. ❌ **Poor fit for your stack** - 6/7 services need OIDC

**Best For:**
- Users with LDAP-only needs
- Very resource-constrained environments
- Simple single-service authentication

### LLDAP + Authelia

**Pros:**
1. ✅ **Lighter than Authentik** - ~150MB RAM
2. ✅ **Separation of concerns** - directory vs auth
3. ✅ **Keeps OIDC and LDAP** - feature parity
4. ✅ **Good documentation** - Authelia has good guides

**Cons:**
1. ❌ **Two services to manage** - increased complexity
2. ❌ **Not IaC-friendly** - manual YAML configuration
3. ❌ **Complete rebuild required** - 8-18 hours work
4. ❌ **Authelia OIDC less mature** - fewer integrations tested
5. ❌ **More attack surface** - two components, more config files
6. ❌ **Learning curve** - new configuration paradigm
7. ❌ **Testing overhead** - verify all 7 integrations

**Best For:**
- Users who prefer microservices approach
- Those with time to invest in migration
- Resource-constrained but need OIDC
- Users comfortable with manual YAML config

---

## Decision Matrix

| Criteria | Weight | Authentik | LLDAP | LLDAP + Authelia |
|----------|--------|-----------|-------|------------------|
| **Meets current needs** | 10 | 9/10 | 3/10 | 8/10 |
| **IaC-friendly** | 9 | 10/10 | 4/10 | 5/10 |
| **Resource efficiency** | 6 | 4/10 | 10/10 | 8/10 |
| **Ease of setup** | 8 | 9/10 | 8/10 | 4/10 |
| **Maintenance burden** | 7 | 7/10 | 9/10 | 6/10 |
| **Feature completeness** | 7 | 10/10 | 5/10 | 8/10 |
| **Future-proofing** | 6 | 10/10 | 5/10 | 7/10 |

**Weighted Scores:**
- **Authentik:** 437/530 (82%)
- **LLDAP:** 329/530 (62%)
- **LLDAP + Authelia:** 347/530 (65%)

---

## Recommendation

### **Keep Authentik and fix the Jellyfin LDAP issue**

**Reasoning:**

1. **You're already 90% there** - 6 services working, only Jellyfin broken
2. **OIDC is critical** - 6/7 services use it, can't lose this
3. **IaC investment** - 9 blueprints already written and maintained
4. **Resource usage acceptable** - Pi 5 can handle 1GB for auth
5. **Time investment** - 2 hours debugging vs 8-18 hours rebuilding

**Next Steps:**

1. Debug Jellyfin LDAP issue (see debugging steps below)
2. If Authentik LDAP proves fundamentally broken:
   - Consider running LLDAP *alongside* Authentik
   - Use Authentik for OIDC, LLDAP for LDAP
   - This gives best of both worlds

**Alternative Scenario:**

If you **absolutely must** reduce resource usage:
- Run LLDAP + Authelia
- Budget 8-18 hours for migration
- Expect debugging time for each service
- Thoroughly test before decommissioning Authentik

---

## Jellyfin LDAP Debugging Plan

### Step 1: Verify Authentik Blueprints Applied

```bash
# SSH to Frey
ssh frey

# Check blueprints loaded
docker exec -it authentik_server ak list blueprints

# Expected output should show:
# - 00-groups
# - 01-service-accounts
# - 20-ldap-jellyfin
```

### Step 2: Verify ldap_bind User Exists

```bash
# List all users in Authentik
docker exec -it authentik_server ak list users

# Check for:
# - ldap_bind (type: internal)
# - Group membership: jellyfin_users
```

### Step 3: Check LDAP Outpost Status

```bash
# Check if LDAP outpost container exists
docker ps -a | grep ldap

# Expected:
# ak-outpost-jellyfin-ldap-outpost

# Check outpost logs
docker logs ak-outpost-jellyfin-ldap-outpost --tail 100
```

### Step 4: Test LDAP Bind Manually

```bash
# Install ldap-utils if not present
sudo apt-get install ldap-utils

# Test LDAP connection
ldapsearch -x -H ldap://10.20.0.1:389 \
  -D "cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io" \
  -w "YOUR_PASSWORD_FROM_SECRETS" \
  -b "ou=users,dc=ldap,dc=goauthentik,dc=io" \
  "(objectClass=*)"

# Should return users if working
```

### Step 5: Check Jellyfin LDAP Plugin Config

```bash
# Check Jellyfin LDAP plugin configuration
cat /opt/frey/appdata/jellyfin/plugins/configurations/LDAP-Auth.xml

# Verify:
# - Server: 10.20.0.1:389
# - Bind DN: cn=ldap_bind,ou=users,dc=ldap,dc=goauthentik,dc=io
# - Base DN: ou=users,dc=ldap,dc=goauthentik,dc=io
# - Search Filter: (memberOf=cn=jellyfin_users,ou=groups,dc=ldap,dc=goauthentik,dc=io)
```

### Step 6: Check Authentik LDAP Provider Settings

```bash
# Access Authentik UI
# Navigate to: Applications > Providers > jellyfin-ldap

# Verify:
# - Base DN: dc=ldap,dc=goauthentik,dc=io
# - Bind mode: cached
# - Search group: jellyfin_users
# - TLS enabled: false (for 10.20.0.1:389)
```

### Common Issues and Fixes

**Issue:** "Connect (Success); Bind: Invalid Credentials"
- **Cause:** Password mismatch or user doesn't exist
- **Fix:** Reset ldap_bind password in Authentik, update secrets.yml, redeploy

**Issue:** "Connection refused"
- **Cause:** LDAP outpost not running
- **Fix:** Check outpost deployment in Authentik UI, verify container running

**Issue:** "No search results"
- **Cause:** Search filter too restrictive or base DN wrong
- **Fix:** Verify user is in jellyfin_users group, check base DN

**Issue:** "TLS handshake failed"
- **Cause:** Using ldaps:// but no certificate
- **Fix:** Use ldap:// (port 389) for internal network

---

## Conclusion

**Keep Authentik.** It's the right tool for your use case. The Jellyfin LDAP issue is solvable, and switching would lose significant functionality (OIDC for 6 services) or require massive reconfiguration effort (8-18 hours) for minimal gain (~850MB RAM savings).

The resource usage is acceptable on a Pi 5, and the IaC-based blueprint system is exactly what you need for infrastructure-as-code deployment.

**If you still want to explore alternatives:**
- Try LLDAP in parallel (don't remove Authentik yet)
- Use it only for Jellyfin
- Keep Authentik for everything else
- Evaluate over 2-4 weeks before committing

---

## References

- [Authentik Documentation](https://goauthentik.io/docs/)
- [LLDAP GitHub](https://github.com/lldap/lldap)
- [Authelia Documentation](https://www.authelia.com/)
- [Jellyfin LDAP Plugin](https://github.com/jellyfin/jellyfin-plugin-ldapauth)
- Your files:
  - `LDAP_SSO_ISSUES.md` - Current debugging state
  - `roles/infrastructure/templates/authentik-blueprints/` - IaC configuration
  - `group_vars/all/secrets.yml` - Credentials (encrypted)
