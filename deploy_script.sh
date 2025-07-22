#!/bin/bash
# Enhanced Pi 5 Hub Deployment Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${PURPLE}"
    echo "======================================"
    echo "🚀 Pi 5 Off-Grid Hub Deployment"
    echo "======================================"
    echo -e "${NC}"
}

check_requirements() {
    log_info "Checking system requirements..."
    
    # Check if running on Pi 5
    if ! grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
        log_warning "Not running on Raspberry Pi 5 - some optimizations may not apply"
    else
        log_success "Raspberry Pi 5 detected"
    fi

    # Check available storage
    AVAILABLE_GB=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if [ "$AVAILABLE_GB" -lt 32 ]; then
        log_error "Insufficient storage: ${AVAILABLE_GB}GB available (32GB+ recommended)"
        exit 1
    else
        log_success "Storage check passed: ${AVAILABLE_GB}GB available"
    fi

    # Check memory
    TOTAL_RAM=$(free -m | awk 'NR==2{print $2}')
    if [ "$TOTAL_RAM" -lt 3000 ]; then
        log_warning "Limited RAM: ${TOTAL_RAM}MB (4GB recommended for all services)"
    else
        log_success "RAM check passed: ${TOTAL_RAM}MB available"
    fi
}

install_prerequisites() {
    log_info "Installing prerequisites..."
    
    # Update system
    sudo apt update && sudo apt upgrade -y
    
    # Install required packages
    sudo apt install -y \
        python3-pip \
        python3-venv \
        git \
        curl \
        vim \
        htop \
        tree
    
    # Install Ansible if not present
    if ! command -v ansible &> /dev/null; then
        log_info "Installing Ansible..."
        
        # Create virtual environment for Ansible
        python3 -m venv ~/.ansible-venv
        source ~/.ansible-venv/bin/activate
        pip install ansible
        
        # Add to PATH
        echo 'export PATH="$HOME/.ansible-venv/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/.ansible-venv/bin:$PATH"
        
        log_success "Ansible installed"
    else
        log_success "Ansible already installed"
    fi
}

setup_ansible() {
    log_info "Setting up Ansible environment..."
    
    # Activate virtual environment if it exists
    if [ -d "$HOME/.ansible-venv" ]; then
        source ~/.ansible-venv/bin/activate
    fi
    
    # Install required collections
    if [ -f "requirements.yml" ]; then
        ansible-galaxy collection install -r requirements.yml
        log_success "Ansible collections installed"
    fi
    
    # Install Python dependencies
    pip install docker docker-compose
    log_success "Python dependencies installed"
}

validate_inventory() {
    log_info "Validating inventory configuration..."
    
    if [ ! -f "inventory/hosts.yml" ]; then
        log_error "inventory/hosts.yml not found!"
        log_info "Please copy inventory/hosts.yml.example and configure it"
        exit 1
    fi
    
    # Test connectivity
    if ansible all -i inventory/hosts.yml -m ping; then
        log_success "Inventory validation passed"
    else
        log_error "Cannot connect to target host(s)"
        log_info "Please check your inventory configuration and SSH access"
        exit 1
    fi
}

run_deployment() {
    log_info "Starting deployment..."
    
    # Activate virtual environment if it exists
    if [ -d "$HOME/.ansible-venv" ]; then
        source ~/.ansible-venv/bin/activate
    fi
    
    # Run the playbook
    if [ "$1" = "--check" ]; then
        log_info "Running in check mode (dry run)..."
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --ask-become-pass
    elif [ "$1" = "--tags" ] && [ -n "$2" ]; then
        log_info "Running with tags: $2"
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "$2" --ask-become-pass
    else
        ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-become-pass
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Deployment completed successfully!"
        show_post_deployment_info
    else
        log_error "Deployment failed!"
        exit 1
    fi
}

show_post_deployment_info() {
    echo -e "${GREEN}"
    echo "========================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "========================================="
    echo -e "${NC}"
    
    PI_IP=$(hostname -I | cut -d' ' -f1)
    
    echo -e "${BLUE}📋 QUICK ACCESS:${NC}"
    echo "  Dockge (Management):   http://${PI_IP}:5001"
    echo "  Grafana (Monitoring):  http://${PI_IP}:3001"
    echo "  Jellyfin (Media):      http://${PI_IP}:8096"
    echo ""
    
    echo -e "${YELLOW}🔧 NEXT STEPS:${NC}"
    echo "  1. Change all default passwords!"
    echo "  2. Configure your services via Dockge"
    echo "  3. Set up monitoring dashboards"
    echo "  4. Check system health: sudo /opt/scripts/health_check.sh"
    echo ""
    
    echo -e "${PURPLE}📖 Documentation and scripts available in /opt/${NC}"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --check         Run in check mode (dry run)"
    echo "  --tags TAGS     Run only specified tags (e.g., --tags media,monitoring)"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full deployment"
    echo "  $0 --check           # Dry run"
    echo "  $0 --tags media      # Deploy only media stack"
    echo "  $0 --tags monitoring,ai  # Deploy monitoring and AI services"
}

# Main execution
main() {
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
    esac
    
    print_header
    check_requirements
    install_prerequisites
    setup_ansible
    validate_inventory
    run_deployment "$@"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi