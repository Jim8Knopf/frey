#!/bin/bash
# Check for existing services and extract passwords if they exist

set -e

echo "=============================================="
echo "CHECKING FOR EXISTING SERVICES & PASSWORDS"
echo "=============================================="
echo ""

# Function to check if container exists and extract password
check_service() {
    local container_name=$1
    local password_var=$2
    local service_name=$3

    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "✓ ${service_name} FOUND (container: ${container_name})"
        password=$(docker exec ${container_name} env 2>/dev/null | grep "${password_var}" | cut -d'=' -f2 || echo "")
        if [ -n "$password" ]; then
            echo "  Password: ${password}"
            echo "  → Use this existing password in secrets.yml"
        else
            echo "  ⚠ Could not extract password"
        fi
        echo ""
        return 0
    else
        echo "✗ ${service_name} NOT FOUND (container: ${container_name})"
        echo "  → Use generated password from SECRETS_TO_ADD.yml"
        echo ""
        return 1
    fi
}

# Check each service
echo "Checking PostgreSQL databases..."
echo "---"
check_service "authentik_postgres" "POSTGRES_PASSWORD" "Authentik Database" || true
check_service "immich_postgres" "POSTGRES_PASSWORD" "Immich Database" || true
check_service "mealie-db" "POSTGRES_PASSWORD" "Mealie Database" || true

echo ""
echo "Checking application services..."
echo "---"
check_service "adguardhome" "PASSWORD" "AdGuard Home" || true
check_service "qbittorrent" "PASSWORD" "qBittorrent" || true

echo ""
echo "=============================================="
echo "SUMMARY"
echo "=============================================="
echo ""

# Check if any containers are running
if [ $(docker ps -q | wc -l) -eq 0 ]; then
    echo "📋 NO CONTAINERS RUNNING"
    echo ""
    echo "This appears to be a FRESH INSTALL."
    echo ""
    echo "✅ ACTION REQUIRED:"
    echo "   1. Open: SECRETS_TO_ADD.yml"
    echo "   2. Copy ALL passwords to your secrets.yml"
    echo "   3. Run: ansible-vault edit group_vars/all/secrets.yml"
    echo "   4. Paste the content from SECRETS_TO_ADD.yml"
    echo "   5. Deploy: ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring,infrastructure --ask-vault-pass"
    echo ""
else
    echo "📋 SOME CONTAINERS FOUND"
    echo ""
    echo "✅ ACTION REQUIRED:"
    echo "   1. For services marked '✓ FOUND' above: Use the EXISTING passwords shown"
    echo "   2. For services marked '✗ NOT FOUND': Use passwords from SECRETS_TO_ADD.yml"
    echo "   3. Edit: ansible-vault edit group_vars/all/secrets.yml"
    echo "   4. Add/update the passwords"
    echo "   5. Deploy: ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags monitoring,infrastructure --ask-vault-pass"
    echo ""
fi

echo "=============================================="
echo ""
echo "💡 TIP: If you're unsure, open both files side-by-side:"
echo "   - SECRETS_TO_ADD.yml (generated passwords)"
echo "   - group_vars/all/secrets.yml (your encrypted secrets)"
echo ""
