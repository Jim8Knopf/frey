# Authentication Solution Comparison - OIDC + IaC Focus

**Date:** 2025-11-18
**Problem:** Authentik ignores IaC configuration, not reliable for automation
**Requirements:**
- ✅ OIDC support (6 services need it)
- ✅ IaC-friendly (Ansible/templatable config)
- ✅ Simple user workflow: create user → assign groups → access services
- ✅ LDAP support for Jellyfin (nice to have)

---

## TL;DR Recommendations

| Solution | Best For | Verdict |
|----------|----------|---------|
| **LLDAP + Authelia** | Simple home lab, don't mind beta OIDC | ⭐⭐⭐⭐ **RECOMMENDED** |
| **Keycloak** | Enterprise-grade, complexity acceptable | ⭐⭐⭐ Good, but heavy |
| **Zitadel** | Modern API-first, minimal complexity | ⭐⭐⭐ Good, less mature |
| **Authentik** | When blueprints work reliably | ⭐⭐ Not working for you |

---

## Option 1: LLDAP + Authelia (RECOMMENDED)

### Why This Works

**LLDAP** - User directory
- Simple web UI for user/group management
- 20MB RAM, fast, reliable
- LDAP server for Jellyfin

**Authelia** - SSO portal
- OIDC provider for other services
- Configuration via YAML files (Ansible-friendly!)
- Connects to LLDAP for user authentication

### User Management Workflow

```
1. Open LLDAP web UI → http://lldap.frey:17170
2. Click "Create User"
3. Fill: username, email, password
4. Assign to groups: jellyfin_users, media_users, etc.
5. Done! User can now log in to all services
```

**Time: 30 seconds per user**

### IaC Configuration

**LLDAP:** Minimal config, mostly static
```yaml
# docker-compose
lldap:
  image: lldap/lldap:latest
  environment:
    LLDAP_LDAP_BASE_DN: dc=frey,dc=local
    LLDAP_JWT_SECRET: {{ lldap_jwt_secret }}
    LLDAP_KEY_SEED: {{ lldap_key_seed }}
```

**Authelia:** Fully templateable YAML
```yaml
# roles/infrastructure/templates/authelia-config.yml.j2
authentication_backend:
  ldap:
    implementation: lldap
    url: ldap://lldap:3890
    base_dn: dc=frey,dc=local
    user: uid=admin,ou=people,dc=frey,dc=local
    password: {{ lldap_admin_password }}

identity_providers:
  oidc:
    clients:
{% for service in oidc_services %}
      - id: {{ service.name }}
        description: {{ service.description }}
        secret: {{ service.secret }}
        redirect_uris:
          - {{ service.redirect_uri }}
        scopes:
          - openid
          - email
          - profile
          - groups
{% endfor %}
```

### Pros & Cons

**Pros:**
- ✅ **Simple user management** - LLDAP web UI is dead simple
- ✅ **IaC-friendly** - Authelia config is just YAML templates
- ✅ **Lightweight** - ~150MB RAM total
- ✅ **Reliable** - Configuration doesn't get ignored
- ✅ **Works offline** - No cloud dependencies
- ✅ **Both OIDC and LDAP** - Covers all your services

**Cons:**
- ⚠️ **OIDC is "beta"** - Authelia docs say OIDC not fully mature
- ⚠️ **Two components** - LLDAP + Authelia (not single solution)
- ⚠️ **Manual YAML** - Not as declarative as Terraform

### Resource Usage
```
lldap:      ~20MB RAM
authelia:   ~130MB RAM
Total:      ~150MB RAM (vs 1GB for Authentik)
```

### Migration Effort
**Time: 4-6 hours**
- Write Authelia config template (2 hours)
- Configure OIDC for 6 services (2 hours)
- Test each service (1 hour)
- Create users in LLDAP (30 min)

---

## Option 2: Keycloak

### Why This Works

- **Mature OIDC/LDAP** - Battle-tested enterprise solution
- **Excellent IaC** - Official Terraform provider, 51% adoption
- **Comprehensive** - Every feature you'll ever need

### User Management Workflow

```
1. Open Keycloak admin → http://keycloak.frey:8080
2. Navigate to: Users → Add User
3. Fill: username, email, first/last name
4. Set password → Credentials tab
5. Assign groups → Groups tab
6. Done! User can log in to all services
```

**Time: 1-2 minutes per user** (more clicks than LLDAP)

### IaC Configuration

**Terraform provider** (most popular approach):
```hcl
# terraform/keycloak/main.tf
resource "keycloak_realm" "frey" {
  realm   = "frey"
  enabled = true
}

resource "keycloak_openid_client" "immich" {
  realm_id  = keycloak_realm.frey.id
  client_id = "immich"
  name      = "Immich Photo Management"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  client_secret         = var.immich_client_secret
  standard_flow_enabled = true

  valid_redirect_uris = [
    "https://immich.frey/auth/callback"
  ]
}

# Repeat for each service...
```

**Alternative: Realm export JSON** (Ansible-friendly):
```yaml
# Deploy via Ansible
- name: Template Keycloak realm config
  template:
    src: keycloak-realm.json.j2
    dest: /opt/frey/keycloak/realm-export.json

- name: Import realm on startup
  docker_container:
    name: keycloak
    command: "start --import-realm"
    volumes:
      - /opt/frey/keycloak/realm-export.json:/opt/keycloak/data/import/realm.json
```

### Pros & Cons

**Pros:**
- ✅ **Production-grade** - Used by major enterprises
- ✅ **Best IaC support** - Terraform provider + import/export
- ✅ **Feature-complete** - OIDC, SAML, LDAP, MFA, everything
- ✅ **Active development** - Large community, frequent updates
- ✅ **Reliable** - Configuration works as expected

**Cons:**
- ❌ **Resource-heavy** - ~600MB RAM (lighter than Authentik though)
- ❌ **Complex UI** - Steeper learning curve
- ❌ **Requires Terraform** - Or manual JSON exports (not ideal)
- ❌ **Overkill** - Many features you don't need

### Resource Usage
```
keycloak:   ~600MB RAM
postgres:   ~100MB RAM
Total:      ~700MB RAM
```

### Migration Effort
**Time: 6-8 hours**
- Set up Terraform provider (2 hours)
- Define realms/clients in Terraform (3 hours)
- Test each service (2 hours)
- Create users (1 hour)

---

## Option 3: Zitadel

### Why This Works

- **API-first** - Everything via GRPC API (IaC-friendly)
- **Lightweight** - Modern Go-based solution
- **Cloud-native** - Designed for modern deployments

### User Management Workflow

```
1. Open Zitadel console → http://zitadel.frey
2. Navigate to: Users → New
3. Fill: username, email, password
4. Assign to organizations/projects
5. Done! User can log in
```

**Time: 1 minute per user**

### IaC Configuration

**Terraform/Pulumi provider:**
```hcl
# terraform/zitadel/main.tf
resource "zitadel_project" "frey" {
  name = "Frey Services"
  org_id = zitadel_org.frey.id
}

resource "zitadel_application_oidc" "immich" {
  project_id              = zitadel_project.frey.id
  name                    = "Immich"
  redirect_uris           = ["https://immich.frey/auth/callback"]
  response_types          = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types             = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type                = "OIDC_APP_TYPE_WEB"
  auth_method_type        = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version                 = "OIDC_VERSION_1_0"
  dev_mode                = false
  access_token_type       = "OIDC_TOKEN_TYPE_JWT"
}
```

**Alternative: GRPC API via Ansible:**
```yaml
# Ansible task
- name: Create OIDC application via API
  uri:
    url: "http://zitadel.frey:8080/management/v1/projects/{{ project_id }}/apps/oidc"
    method: POST
    headers:
      Authorization: "Bearer {{ zitadel_service_token }}"
    body_format: json
    body:
      name: immich
      redirectUris: ["https://immich.frey/auth/callback"]
      responseTypes: ["OIDC_RESPONSE_TYPE_CODE"]
```

### Pros & Cons

**Pros:**
- ✅ **Lightweight** - ~200MB RAM
- ✅ **Modern** - API-first design, everything via API
- ✅ **IaC-friendly** - Terraform/Pulumi providers
- ✅ **Fast** - Go-based, excellent performance
- ✅ **Cloud-native** - Designed for modern deployments

**Cons:**
- ⚠️ **Less mature** - Newer than Keycloak/Authentik
- ⚠️ **Smaller community** - Less examples/guides
- ⚠️ **GRPC API** - Different paradigm than REST
- ⚠️ **Complex concepts** - Organizations, projects, apps hierarchy

### Resource Usage
```
zitadel:    ~200MB RAM
postgres:   ~100MB RAM (or CockroachDB)
Total:      ~300MB RAM
```

### Migration Effort
**Time: 6-10 hours**
- Learn Zitadel concepts (2 hours)
- Set up Terraform/API calls (3 hours)
- Configure OIDC for 6 services (3 hours)
- Test and debug (2 hours)

---

## Head-to-Head Comparison

### User Creation Workflow

**LLDAP + Authelia:**
```
1. Open LLDAP UI
2. Click "Create User"
3. Fill form (username, email, password)
4. Click checkboxes for groups
5. Click "Create"
Time: 30 seconds
```

**Keycloak:**
```
1. Open Keycloak admin
2. Select realm → Users → Add User
3. Fill form (username, email, first/last name)
4. Click "Save"
5. Go to Credentials tab → Set password → Save
6. Go to Groups tab → Join groups → Save
Time: 1-2 minutes
```

**Zitadel:**
```
1. Open Zitadel console
2. Users → New
3. Fill form (email, username, password)
4. Assign to organization/project
5. Save
Time: 1 minute
```

### IaC Friendliness

| Feature | LLDAP + Authelia | Keycloak | Zitadel |
|---------|------------------|----------|---------|
| **Config format** | YAML templates | Terraform HCL | Terraform/API |
| **Ansible support** | ✅ Native (templates) | ⚠️ Via JSON export | ⚠️ Via API calls |
| **Terraform support** | ❌ No provider | ✅ Official provider | ✅ Community provider |
| **Declarative** | ⚠️ Config file based | ✅ Terraform state | ✅ Terraform state |
| **Version control** | ✅ Easy | ✅ Easy | ✅ Easy |
| **Automated deployment** | ✅ Easy | ✅ Easy | ✅ Medium |

### Service Integration Comparison

**Example: Configuring Immich OIDC**

**LLDAP + Authelia:**
```yaml
# authelia-config.yml.j2
identity_providers:
  oidc:
    clients:
      - id: immich
        secret: {{ immich_oidc_secret }}
        redirect_uris:
          - https://immich.frey/auth/callback
```
```yaml
# immich .env
IMMICH_AUTH_ISSUER_URL=http://authelia.frey:9091
IMMICH_AUTH_CLIENT_ID=immich
IMMICH_AUTH_CLIENT_SECRET={{ immich_oidc_secret }}
```

**Keycloak (Terraform):**
```hcl
resource "keycloak_openid_client" "immich" {
  realm_id    = "frey"
  client_id   = "immich"
  client_secret = var.immich_secret
  redirect_uris = ["https://immich.frey/auth/callback"]
}
```
```yaml
# immich .env
IMMICH_AUTH_ISSUER_URL=http://keycloak.frey:8080/realms/frey
IMMICH_AUTH_CLIENT_ID=immich
IMMICH_AUTH_CLIENT_SECRET={{ immich_oidc_secret }}
```

**Zitadel (Terraform):**
```hcl
resource "zitadel_application_oidc" "immich" {
  project_id = zitadel_project.frey.id
  name = "Immich"
  redirect_uris = ["https://immich.frey/auth/callback"]
}
```
```yaml
# immich .env
IMMICH_AUTH_ISSUER_URL=http://zitadel.frey:8080
IMMICH_AUTH_CLIENT_ID={{ zitadel_immich_client_id }}
IMMICH_AUTH_CLIENT_SECRET={{ zitadel_immich_secret }}
```

### Reliability (Does IaC actually work?)

| Solution | IaC Reliability | Notes |
|----------|----------------|-------|
| **Authentik** | ❌ **FAILS** | Blueprints get ignored (your experience) |
| **LLDAP + Authelia** | ✅ **WORKS** | Config files always respected |
| **Keycloak** | ✅ **WORKS** | Terraform provider very reliable |
| **Zitadel** | ⚠️ **MOSTLY** | API works, but provider has quirks |

---

## Detailed Deployment Examples

### LLDAP + Authelia Deployment

**Directory structure:**
```
roles/authentication/
├── tasks/
│   └── main.yml
├── templates/
│   ├── lldap/
│   │   └── lldap_config.toml.j2
│   ├── authelia/
│   │   ├── configuration.yml.j2
│   │   └── users_database.yml.j2
│   └── docker-compose-auth.yml.j2
└── defaults/
    └── main.yml
```

**Docker Compose template:**
```yaml
# docker-compose-auth.yml.j2
services:
  lldap:
    image: lldap/lldap:stable
    container_name: lldap
    restart: unless-stopped
    environment:
      LLDAP_LDAP_BASE_DN: dc={{ network.domain_name }},dc=local
      LLDAP_LDAP_USER_DN: admin
      LLDAP_LDAP_USER_PASS: {{ lldap_admin_password }}
      LLDAP_JWT_SECRET: {{ lldap_jwt_secret }}
      LLDAP_KEY_SEED: {{ lldap_key_seed }}
    volumes:
      - {{ storage.appdata_dir }}/lldap:/data
    networks:
      - proxy
      - auth_network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.lldap.rule=Host(`lldap.{{ network.domain_name }}`)"
      - "traefik.http.services.lldap.loadbalancer.server.port=17170"

  authelia:
    image: authelia/authelia:latest
    container_name: authelia
    restart: unless-stopped
    environment:
      AUTHELIA_JWT_SECRET: {{ authelia_jwt_secret }}
      AUTHELIA_SESSION_SECRET: {{ authelia_session_secret }}
      AUTHELIA_STORAGE_ENCRYPTION_KEY: {{ authelia_storage_key }}
    volumes:
      - {{ storage.appdata_dir }}/authelia/configuration.yml:/config/configuration.yml:ro
    networks:
      - proxy
      - auth_network
    depends_on:
      - lldap
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.authelia.rule=Host(`auth.{{ network.domain_name }}`)"
      - "traefik.http.services.authelia.loadbalancer.server.port=9091"

networks:
  proxy:
    external: true
  auth_network:
    driver: bridge
```

**Authelia configuration:**
```yaml
# configuration.yml.j2
server:
  host: 0.0.0.0
  port: 9091

log:
  level: info

authentication_backend:
  ldap:
    implementation: lldap
    url: ldap://lldap:3890
    timeout: 5s
    start_tls: false
    base_dn: dc={{ network.domain_name }},dc=local
    username_attribute: uid
    additional_users_dn: ou=people
    users_filter: (&(|({username_attribute}={input})({mail_attribute}={input}))(objectClass=person))
    additional_groups_dn: ou=groups
    groups_filter: (member={dn})
    group_name_attribute: cn
    mail_attribute: mail
    display_name_attribute: displayName
    user: uid=admin,ou=people,dc={{ network.domain_name }},dc=local
    password: {{ lldap_admin_password }}

session:
  name: authelia_session
  secret: {{ authelia_session_secret }}
  expiration: 1h
  inactivity: 5m
  domain: {{ network.domain_name }}

storage:
  local:
    path: /config/db.sqlite3

access_control:
  default_policy: deny
  rules:
    - domain: "*.{{ network.domain_name }}"
      policy: one_factor
      subject:
        - ["group:media_users"]

identity_providers:
  oidc:
    hmac_secret: {{ authelia_oidc_hmac_secret }}
    issuer_private_key: {{ authelia_oidc_private_key }}

    clients:
      # Immich
      - id: immich
        description: Immich Photo Management
        secret: {{ immich_oidc_secret_hash }}  # Use authelia hash-password to generate
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://immich.{{ network.domain_name }}/auth/login
          - https://immich.{{ network.domain_name }}/user-settings
        scopes:
          - openid
          - email
          - profile
          - groups

      # Audiobookshelf
      - id: audiobookshelf
        description: Audiobookshelf
        secret: {{ audiobookshelf_oidc_secret_hash }}
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://audiobookshelf.{{ network.domain_name }}/auth/openid/callback
          - https://audiobookshelf.{{ network.domain_name }}/auth/openid/mobile-redirect
        scopes:
          - openid
          - email
          - profile

      # Grafana
      - id: grafana
        description: Grafana Monitoring
        secret: {{ grafana_oidc_secret_hash }}
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://grafana.{{ network.domain_name }}/login/generic_oauth
        scopes:
          - openid
          - email
          - profile
          - groups

      # Home Assistant
      - id: homeassistant
        description: Home Assistant
        secret: {{ homeassistant_oidc_secret_hash }}
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://homeassistant.{{ network.domain_name }}/auth/external/callback
        scopes:
          - openid
          - email
          - profile

      # Mealie
      - id: mealie
        description: Mealie Recipe Manager
        secret: {{ mealie_oidc_secret_hash }}
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://mealie.{{ network.domain_name }}/login
        scopes:
          - openid
          - email
          - profile
          - groups

      # Dashy
      - id: dashy
        description: Dashy Dashboard
        secret: {{ dashy_oidc_secret_hash }}
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://{{ network.domain_name }}/
        scopes:
          - openid
          - email
          - profile
```

---

## Final Recommendation

### 🏆 Winner: LLDAP + Authelia

**Why:**
1. ✅ **Simple user management** - LLDAP web UI is perfect for "create user, add to groups, done"
2. ✅ **IaC-friendly** - Authelia config is just Ansible templates (you're already using Ansible)
3. ✅ **Lightweight** - 85% less RAM than Authentik (150MB vs 1GB)
4. ✅ **Reliable** - Config files don't get ignored
5. ✅ **OIDC + LDAP** - Covers all 7 services
6. ⚠️ **OIDC is beta** - But people report it works fine for home labs

**Migration path:**
1. Keep Authentik running (don't break current setup)
2. Deploy LLDAP + Authelia in parallel
3. Migrate one service at a time (start with Dashy, easiest to test)
4. Once all services work, decommission Authentik
5. **Total time: 4-6 hours spread over a weekend**

### Alternative: Keycloak (if you want enterprise-grade)

**Choose Keycloak if:**
- You want production-grade reliability
- You're comfortable with Terraform
- 700MB RAM is acceptable
- You value maturity over simplicity

---

## Next Steps

1. **Decision point:** LLDAP + Authelia or Keycloak?
2. I'll create migration guide for your choice
3. We'll deploy in parallel (keep Authentik running)
4. Test thoroughly before switching

**What do you think? Want to go with LLDAP + Authelia?**
