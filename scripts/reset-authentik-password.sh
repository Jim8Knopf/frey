#!/bin/bash
# ==============================================================================
# Reset Authentik Admin Password
# ==============================================================================
# This script properly resets the akadmin password in Authentik
#
# The AUTHENTIK_BOOTSTRAP_PASSWORD environment variable ONLY works on initial
# user creation. For password resets, we must use the Django management command.
#
# Usage:
#   ./reset-authentik-password.sh <new_password>
#   ./reset-authentik-password.sh --generate  (generates and sets random password)
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on the target host
if [ ! -f /opt/frey/stacks/infrastructure/docker-compose.yml ]; then
    echo -e "${RED}Error: This script must be run on the Frey server${NC}"
    echo "Run it via: ssh frey 'bash -s' < scripts/reset-authentik-password.sh [password]"
    exit 1
fi

# Check if Authentik is running
if ! docker ps | grep -q authentik_server; then
    echo -e "${RED}Error: Authentik container is not running${NC}"
    exit 1
fi

# Parse arguments
if [ "$1" == "--generate" ]; then
    NEW_PASSWORD=$(openssl rand -hex 16)
    echo -e "${YELLOW}Generated password: ${GREEN}${NEW_PASSWORD}${NC}"
elif [ -n "$1" ]; then
    NEW_PASSWORD="$1"
else
    echo "Usage: $0 <new_password> | --generate"
    exit 1
fi

# Reset the password
echo -e "${YELLOW}Resetting akadmin password...${NC}"
echo -e "$NEW_PASSWORD\n$NEW_PASSWORD" | docker exec -i authentik_server python -m manage changepassword akadmin

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Password reset successful!${NC}"
    echo ""
    echo "Login credentials:"
    echo "  URL: http://auth.frey (or http://$(hostname -I | awk '{print $1}'):9300)"
    echo "  Username: akadmin"
    echo "  Password: $NEW_PASSWORD"
    echo ""
    echo -e "${YELLOW}⚠️  Important: Update this password in secrets.yml:${NC}"
    echo "  authentik_bootstrap_password: \"$NEW_PASSWORD\""
else
    echo -e "${RED}❌ Password reset failed!${NC}"
    exit 1
fi
