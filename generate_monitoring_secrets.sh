#!/bin/bash
# Generate secure passwords for monitoring stack
# Run this script, then copy the output to your secrets.yml

set -e

echo "=================================================="
echo "MONITORING STACK - GENERATED SECRETS"
echo "=================================================="
echo ""
echo "Copy these lines into your secrets.yml file:"
echo "(Edit with: ansible-vault edit group_vars/all/secrets.yml)"
echo ""
echo "---"
echo ""

# Generate secure random passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Check if passwords already exist in plaintext config (before vault encryption)
IMMICH_PASS=$(grep -r "DB_PASSWORD=" roles/immich/templates/.env.j2 2>/dev/null | grep -oP "default\('\K[^']+(?=')" || echo "")
COOKBOOK_PASS=$(grep -r "POSTGRES_PASSWORD=" roles/cookbook/templates/.env.j2 2>/dev/null | grep -oP "default\('\K[^']+(?=')" || echo "")
AUTHENTIK_PASS=$(grep -r "POSTGRES_PASSWORD=" roles/infrastructure/templates/docker-compose-infrastructure.yml.j2 2>/dev/null | grep -oP '{{ \K[^}]+(?= }}' | head -1 || echo "")

# Generate passwords if not found in defaults
if [ -z "$IMMICH_PASS" ] || [ "$IMMICH_PASS" == "changeThisSecurePassword123!" ]; then
    IMMICH_PASS=$(generate_password)
fi

if [ -z "$COOKBOOK_PASS" ]; then
    COOKBOOK_PASS=$(generate_password)
fi

GRAFANA_PASS=$(generate_password)
ADGUARD_PASS=$(generate_password)
QBIT_PASS=$(generate_password)

echo "# =============================================================================="
echo "# MONITORING STACK SECRETS"
echo "# =============================================================================="
echo ""
echo "# Grafana admin password (local login + fallback)"
echo "grafana_admin_password: \"$GRAFANA_PASS\""
echo ""
echo "# AdGuard Home credentials (for DNS statistics exporter)"
echo "adguard_username: \"admin\""
echo "adguard_password: \"$ADGUARD_PASS\""
echo ""
echo "# qBittorrent credentials (for torrent metrics exporter)"
echo "qbittorrent_username: \"admin\""
echo "qbittorrent_password: \"$QBIT_PASS\""
echo ""
echo "# =============================================================================="
echo "# DATABASE PASSWORDS (if not already present)"
echo "# =============================================================================="
echo ""
echo "# Immich PostgreSQL password"
echo "immich_db_password: \"$IMMICH_PASS\""
echo ""
echo "# Mealie PostgreSQL password"
echo "cookbook:"
echo "  db_user: \"mealie\""
echo "  db_name: \"mealie\""
echo "  db_password: \"$COOKBOOK_PASS\""
echo ""
echo "# Authentik PostgreSQL password (if not already set)"
echo "# authentik_postgres_password: \"your-existing-authentik-password\""
echo ""
echo "=================================================="
echo ""
echo "IMPORTANT NOTES:"
echo "1. If Authentik is already deployed, use its EXISTING password"
echo "2. If Immich/Mealie are deployed, use their EXISTING passwords"
echo "3. For AdGuard/qBittorrent: Set these passwords in their web UIs after deployment"
echo "4. These passwords are RANDOM - save them securely!"
echo ""
echo "To add these to vault:"
echo "  1. Run: ansible-vault edit group_vars/all/secrets.yml"
echo "  2. Copy the relevant sections above"
echo "  3. Save and exit"
echo ""
echo "To find existing passwords from running containers:"
echo "  Immich: docker exec immich_postgres env | grep POSTGRES_PASSWORD"
echo "  Mealie: docker exec mealie-db env | grep POSTGRES_PASSWORD"
echo "  Authentik: docker exec authentik_postgres env | grep POSTGRES_PASSWORD"
echo ""
