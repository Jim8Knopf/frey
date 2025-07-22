#!/bin/bash

# Pi5 Hub Ansible Deployment Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Farben für Output
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

# Banner
echo -e "${BLUE}"
cat << 'BANNER'
╔═══════════════════════════════════════════╗
║           Pi5 Hub Ansible Deploy          ║
║     Raspberry Pi 5 Automation Suite      ║
╚═══════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# Voraussetzungen prüfen
echo_info "Prüfe Voraussetzungen..."

if ! command -v ansible-playbook &> /dev/null; then
    echo_error "Ansible ist nicht installiert!"
    echo "Installiere Ansible: pip install ansible"
    exit 1
fi

if [ ! -f "inventory/hosts.yml" ]; then
    echo_error "Inventory-Datei nicht gefunden!"
    echo "Bitte inventory/hosts.yml konfigurieren"
    exit 1
fi

# Ansible Collections installieren
echo_info "Installiere Ansible Collections..."
ansible-galaxy install -r requirements.yml

# Syntax-Check
echo_info "Führe Syntax-Check durch..."
ansible-playbook --syntax-check -i inventory/hosts.yml playbooks/site.yml

# Deployment-Optionen
echo_info "Deployment-Optionen:"
echo "1) Vollständiges Deployment"
echo "2) Nur System-Setup (common, security, ssd_optimization)"
echo "3) Nur Docker Services"
echo "4) Dry-Run (Check-Modus)"
echo "5) Bestimmte Rolle ausführen"

read -p "Wählen Sie eine Option (1-5): " choice

case $choice in
    1)
        echo_info "Starte vollständiges Deployment..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml
        ;;
    2)
        echo_info "Starte System-Setup..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "system"
        ;;
    3)
        echo_info "Starte Docker Services..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "docker,services"
        ;;
    4)
        echo_info "Führe Dry-Run durch..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff
        ;;
    5)
        echo "Verfügbare Rollen:"
        ls -1 roles/ | sed 's/^/  - /'
        read -p "Rolle eingeben: " role_name
        if [ -d "roles/$role_name" ]; then
            ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "$role_name"
        else
            echo_error "Rolle '$role_name' nicht gefunden!"
            exit 1
        fi
        ;;
    *)
        echo_error "Ungültige Auswahl!"
        exit 1
        ;;
esac

echo_success "Deployment abgeschlossen!"
echo_info "Logs finden Sie in: /var/log/ansible/"
