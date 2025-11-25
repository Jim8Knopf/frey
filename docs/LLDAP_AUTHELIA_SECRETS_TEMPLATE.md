# LLDAP + Authelia Secrets Template

This document shows all the secrets you need to add to `group_vars/all/secrets.yml` for the LLDAP + Authelia authentication stack.

## How to Generate Secrets

All secrets should be **strong random strings**. Use this command to generate them:

```bash
# Generate a random 64-character hex string
openssl rand -hex 32

# Or generate a random 128-character hex string (more secure)
openssl rand -hex 64
```

## Required Secrets for secrets.yml

Add these to your `group_vars/all/secrets.yml` file:

```yaml
# ==============================================================================
# LLDAP SECRETS
# ==============================================================================

# LLDAP admin password (for logging into LLDAP web UI)
lldap_admin_password: "YOUR_STRONG_PASSWORD_HERE"

# LLDAP JWT secret (for web UI authentication)
lldap_jwt_secret: "GENERATE_WITH: openssl rand -hex 32"

# LLDAP key seed (for password hashing)
lldap_key_seed: "GENERATE_WITH: openssl rand -hex 32"

# ==============================================================================
# AUTHELIA SECRETS
# ==============================================================================

# Authelia JWT secret (for session tokens)
authelia_jwt_secret: "GENERATE_WITH: openssl rand -hex 64"

# Authelia session secret (for encrypting session cookies)
authelia_session_secret: "GENERATE_WITH: openssl rand -hex 64"

# Authelia storage encryption key (for encrypting database)
authelia_storage_key: "GENERATE_WITH: openssl rand -hex 64"

# Authelia OIDC HMAC secret (for signing OIDC tokens)
authelia_oidc_hmac_secret: "GENERATE_WITH: openssl rand -hex 64"

# Authelia OIDC private key (RS256 key pair for JWT signing)
# Generate with:
#   openssl genrsa -out /tmp/authelia_private_key.pem 4096
#   cat /tmp/authelia_private_key.pem
# Then paste the ENTIRE key (including -----BEGIN/END lines) below
authelia_oidc_private_key: |
  -----BEGIN RSA PRIVATE KEY-----
  YOUR_GENERATED_PRIVATE_KEY_HERE
  (paste the entire key)
  -----END RSA PRIVATE KEY-----

# ==============================================================================
# OIDC CLIENT SECRETS (HASHED)
# ==============================================================================
# These are the client secrets for each service that uses OIDC
# Generate plain secrets first, then hash them with Authelia

# Step 1: Generate plain client secrets
immich_oidc_secret: "GENERATE_WITH: openssl rand -hex 32"
audiobookshelf_oidc_secret: "GENERATE_WITH: openssl rand -hex 32"
grafana_oidc_secret: "GENERATE_WITH: openssl rand -hex 32"
homeassistant_oidc_secret: "GENERATE_WITH: openssl rand -hex 32"
mealie_oidc_secret: "GENERATE_WITH: openssl rand -hex 32"
dashy_oidc_secret: "GENERATE_WITH: openssl rand -hex 32"

# Step 2: Hash the plain secrets with Authelia (AFTER deployment)
# Run this command for each secret:
#   docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_PLAIN_SECRET'
# Then add the hashed values below:

immich_oidc_secret_hash: "$pbkdf2-sha512$310000$..."  # Hash of immich_oidc_secret
audiobookshelf_oidc_secret_hash: "$pbkdf2-sha512$310000$..."  # Hash of audiobookshelf_oidc_secret
grafana_oidc_secret_hash: "$pbkdf2-sha512$310000$..."  # Hash of grafana_oidc_secret
homeassistant_oidc_secret_hash: "$pbkdf2-sha512$310000$..."  # Hash of homeassistant_oidc_secret
mealie_oidc_secret_hash: "$pbkdf2-sha512$310000$..."  # Hash of mealie_oidc_secret
dashy_oidc_secret_hash: "$pbkdf2-sha512$310000$..."  # Hash of dashy_oidc_secret
```

## Deployment Workflow

1. **Generate all plain secrets** (openssl commands above)
2. **Add plain secrets to secrets.yml** (all except the `*_hash` ones)
3. **Generate RSA private key** for OIDC signing
4. **Encrypt secrets.yml** with Ansible Vault:
   ```bash
   ansible-vault encrypt group_vars/all/secrets.yml
   ```
5. **Deploy the authentication stack**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags authentication --vault-password-file .vault_pass
   ```
6. **Wait for Authelia to be healthy** (30-60 seconds)
7. **Generate hashed client secrets** for each service:
   ```bash
   # SSH to the server
   ssh frey

   # Hash each secret
   docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_IMMICH_SECRET'
   docker exec -it authelia authelia crypto hash generate pbkdf2 --password 'YOUR_AUDIOBOOKSHELF_SECRET'
   # ... repeat for all 6 services
   ```
8. **Add hashed secrets to secrets.yml**
9. **Re-encrypt secrets.yml**:
   ```bash
   ansible-vault encrypt group_vars/all/secrets.yml
   ```
10. **Redeploy authentication stack** to apply hashed secrets:
    ```bash
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags authentication --vault-password-file .vault_pass
    ```

## Alternative: Pre-Hash Secrets

If you want to avoid the two-stage deployment, you can pre-hash secrets before the first deployment:

```bash
# Install Authelia CLI locally (optional)
go install github.com/authelia/authelia/v4/cmd/authelia@latest

# Or use Docker
docker run --rm -it authelia/authelia:latest authelia crypto hash generate pbkdf2 --help

# Generate and hash in one go
SECRET=$(openssl rand -hex 32)
echo "Plain secret: $SECRET"
docker run --rm -it authelia/authelia:latest authelia crypto hash generate pbkdf2 --password "$SECRET"
```

## Verifying Secrets

After deployment, verify all services can connect to Authelia:

```bash
# Check Authelia logs
ssh frey "docker logs authelia --tail 100"

# Check LLDAP is running
ssh frey "docker ps | grep lldap"

# Test LDAP connection
ssh frey "ldapsearch -x -H ldap://localhost:3890 -D 'uid=admin,ou=people,dc=frey,dc=local' -w 'YOUR_LLDAP_PASSWORD' -b 'dc=frey,dc=local'"

# Access Authelia web UI
curl -I https://auth.frey
```

## Removing Old Authentik Secrets (After Migration)

Once everything is working with Authelia, you can remove these old secrets from `secrets.yml`:

- `authentik_postgres_password`
- `authentik_secret_key`
- `authentik_bootstrap_password`
- `authentik_bootstrap_token`
- `authentik_bootstrap_email`
- Any `*_oidc_client_secret` variables that were for Authentik

**Keep these until migration is complete and tested!**
