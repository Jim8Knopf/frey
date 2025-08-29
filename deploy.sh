#!/bin/bash

# Pi5 Hub Ansible Deployment Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Banner9o
echo -e "${BLUE}"
cat << 'BANNER'
╔═══════════════════════════════════════════╗
║           Pi5 Hub Ansible Deploy          ║
║     Raspberry Pi 5 Automation Suite       ║
╚═══════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# Checking prerequisites
echo_info "Checking prerequisites..."

if ! command -v ansible-playbook &> /dev/null; then
    echo_error "Ansible is not installed!"
    echo "Please install Ansible: pip install ansible"
    exit 1
fi

if [ ! -f "inventory/hosts.yml" ]; then
    echo_error "Inventory file not found!"
    echo "Please configure inventory/hosts.yml"
    exit 1
fi

# Installing Ansible Collections
echo_info "Installing Ansible Collections..."
ansible-galaxy install -r requirements.yml

# Running syntax check
echo_info "Running syntax check..."
ansible-playbook --syntax-check -i inventory/hosts.yml playbooks/site.yml

# Deployment Options
echo_info "Deployment Options:"
echo "1) Full Deployment"
echo "2) System Setup Only"
echo "3) Docker Services Only"
echo "4) Dry-Run (Check Mode)"
echo "5) Run a Specific Role"

read -p "Select an option (1-5): " choice

case $choice in
    1)
        echo_info "Starting full deployment..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-become-pass
        ;;
    2)
        echo_info "Starting system setup..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "system" --ask-become-pass
        ;;
    3)
        echo_info "Starting Docker services..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "docker,services" --ask-become-pass
        ;;
    4)
        echo_info "Performing dry-run..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff --ask-become-pass
        ;;
    5)
        echo "Available roles:"
        ls -1 roles/ | sed 's/^/  - /'
        read -p "Enter role name: " role_name
        if [ -d "roles/$role_name" ]; then
            ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "$role_name" --ask-become-pass
        else
            echo_error "Role '$role_name' not found!"
            exit 1
        fi
        ;;
    *)
        echo_error "Invalid selection!"
        exit 1
        ;;
esac

echo_success "Deployment complete!"
echo_info "Logs can be found in: /var/log/ansible/"
