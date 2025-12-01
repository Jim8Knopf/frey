#!/bin/bash
# Quick deployment checklist for WiFi Captive Portal Automation

echo "════════════════════════════════════════════════════════════════"
echo "  WiFi Captive Portal Automation - Deployment Checklist"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check 1: Project directory
echo "✓ Check 1: Project directory exists"
if [ -d "/home/jim/Projects/frey0" ]; then
    echo "  ✅ Found: /home/jim/Projects/frey0"
else
    echo "  ❌ Not found: /home/jim/Projects/frey0"
    exit 1
fi
echo ""

# Check 2: SSH key exists
echo "✓ Check 2: SSH key for Ansible"
if [ -f "$HOME/.ssh/id_rsa_ansible" ]; then
    echo "  ✅ Found: ~/.ssh/id_rsa_ansible"
else
    echo "  ❌ Not found: ~/.ssh/id_rsa_ansible"
    echo "  Create with: ssh-keygen -f ~/.ssh/id_rsa_ansible"
    exit 1
fi
echo ""

# Check 3: Ansible inventory
echo "✓ Check 3: Ansible inventory"
if grep -q "frey" /home/jim/Projects/frey0/inventory/hosts.yml 2>/dev/null; then
    echo "  ✅ Found 'frey' in inventory"
else
    echo "  ⚠️  'frey' not found in inventory - check hosts.yml"
fi
echo ""

# Check 4: WiFi role exists
echo "✓ Check 4: WiFi access point role"
if [ -d "/home/jim/Projects/frey0/roles/wifi_access_point" ]; then
    echo "  ✅ Found: roles/wifi_access_point/"
else
    echo "  ❌ Not found: roles/wifi_access_point/"
    exit 1
fi
echo ""

# Check 5: Scripts exist
echo "✓ Check 5: Captive portal scripts"
if [ -f "/home/jim/Projects/frey0/roles/wifi_access_point/files/frey-wifi-captive-portal-auto.sh" ]; then
    echo "  ✅ Found: frey-wifi-captive-portal-auto.sh"
else
    echo "  ❌ Not found: frey-wifi-captive-portal-auto.sh"
fi

if [ -f "/home/jim/Projects/frey0/roles/wifi_access_point/files/frey-wifi-captive-portal-daemon.sh" ]; then
    echo "  ✅ Found: frey-wifi-captive-portal-daemon.sh"
else
    echo "  ❌ Not found: frey-wifi-captive-portal-daemon.sh"
fi
echo ""

# Check 6: Systemd service template
echo "✓ Check 6: Systemd service template"
if [ -f "/home/jim/Projects/frey0/roles/wifi_access_point/templates/frey-wifi-captive-portal-daemon.service.j2" ]; then
    echo "  ✅ Found: frey-wifi-captive-portal-daemon.service.j2"
else
    echo "  ❌ Not found: frey-wifi-captive-portal-daemon.service.j2"
fi
echo ""

# Check 7: Documentation
echo "✓ Check 7: Documentation"
if [ -f "/home/jim/Projects/frey0/docs/WIFI_CAPTIVE_PORTAL_ANSIBLE.md" ]; then
    echo "  ✅ Found: docs/WIFI_CAPTIVE_PORTAL_ANSIBLE.md"
else
    echo "  ⚠️  Not found: docs/WIFI_CAPTIVE_PORTAL_ANSIBLE.md"
fi
echo ""

# Check 8: Configuration
echo "✓ Check 8: WiFi configuration"
if [ -f "/home/jim/Projects/frey0/group_vars/all/main.yml" ]; then
    echo "  ✅ Found: group_vars/all/main.yml"
    echo ""
    echo "  Current WiFi roaming config:"
    grep -A 5 "roaming:" /home/jim/Projects/frey0/group_vars/all/main.yml | sed 's/^/    /'
else
    echo "  ❌ Not found: group_vars/all/main.yml"
fi
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "  Deployment Commands"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Before deploying, verify WiFi roaming is enabled:"
echo "  grep 'roaming:' /home/jim/Projects/frey0/group_vars/all/main.yml"
echo ""
echo "Then deploy with:"
echo ""
echo "  # Dry-run (see what will change)"
echo "  ansible-playbook -i /home/jim/Projects/frey0/inventory/hosts.yml \\"
echo "    /home/jim/Projects/frey0/playbooks/site.yml \\"
echo "    --tags wifi_access_point \\"
echo "    --vault-password-file /home/jim/Projects/frey0/.vault_pass \\"
echo "    --check --diff"
echo ""
echo "  # Actual deployment"
echo "  ansible-playbook -i /home/jim/Projects/frey0/inventory/hosts.yml \\"
echo "    /home/jim/Projects/frey0/playbooks/site.yml \\"
echo "    --tags wifi_access_point \\"
echo "    --vault-password-file /home/jim/Projects/frey0/.vault_pass"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Post-Deployment Verification"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "After deployment, SSH into your Pi:"
echo ""
echo "  ssh -i ~/.ssh/id_rsa_ansible ansible@frey"
echo ""
echo "Then verify the daemon:"
echo ""
echo "  # Check status"
echo "  sudo systemctl status frey-wifi-captive-portal-daemon"
echo ""
echo "  # View live logs"
echo "  sudo journalctl -u frey-wifi-captive-portal-daemon -f"
echo ""
echo "  # Test manually"
echo "  sudo /usr/local/bin/frey-wifi-captive-portal-auto --verbose"
echo ""
echo "════════════════════════════════════════════════════════════════"
