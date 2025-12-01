#!/bin/bash
# Capture LibrariesSA-Free Portal Page for Analysis

echo "This script will help capture the actual portal page HTML"
echo ""
echo "Requirements:"
echo "  - Pi must be connected to LibrariesSA-Free"
echo "  - You have SSH access"
echo "  - You're willing to lose internet temporarily"
echo ""
read -p "Continue? (y/N): " -r
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

echo ""
echo "Connecting to Pi and capturing portal page..."
echo ""

# Capture full response with headers and body
ssh -i ~/.ssh/id_rsa_ansible ansible@frey << 'EOF'
  echo "[*] Capturing portal page from LibrariesSA-Free..."
  sudo bash -c 'curl -v "http://www.google.com/generate_204" 2>&1' | head -100 | tee /tmp/portal-capture.txt
  echo ""
  echo "[*] Portal page saved to /tmp/portal-capture.txt"
EOF

# Copy to local machine
echo ""
echo "Copying portal page to local machine..."
scp -i ~/.ssh/id_rsa_ansible ansible@frey:/tmp/portal-capture.txt /tmp/portal-capture.txt

echo ""
echo "✓ Portal page captured at: /tmp/portal-capture.txt"
echo ""
echo "Next steps:"
echo "  1. Review the HTML at /tmp/portal-capture.txt"
echo "  2. Look for:"
echo "     - Form fields (<input name='...'>)"
echo "     - Checkboxes to check"
echo "     - Buttons to click"
echo "     - Form action URL"
echo ""
echo "  3. Share the relevant parts with me so I can fix the bypass script"
