Here is Claude's plan:
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Complete WiFi Deployment & NVMe Migration Guide

 Phase 1: Restore SSH Access from Laptop

 1.1 SSH from phone to Pi
 ssh jim@<pi-ip-from-phone-hotspot>

 1.2 Clear laptop's iptables ban
 # See what's blocked
 sudo iptables -L INPUT -n -v | grep DROP

 # Clear fail2ban SSH bans
 sudo iptables -F f2b-sshd

 # Restart fail2ban to rebuild clean rules
 sudo systemctl restart fail2ban

 1.3 Add laptop to permanent whitelist (while on Pi)
 # Get laptop's current IP on hotspot
 # (Check from laptop: ip addr or ipconfig)

 # Unban laptop specifically
 sudo fail2ban-client set sshd unbanip <laptop-ip>

 1.4 Test laptop SSH
 # From laptop terminal
 ssh jim@<pi-ip>

 ---
 Phase 2: Deploy WiFi Fixes via Ansible (from Laptop)

 2.1 Update inventory with Pi's current IP
 # Edit inventory/hosts.yml
 nano inventory/hosts.yml

 # Update the ansible_host line:
 ansible_host: <current-pi-ip-on-hotspot>

 2.2 Run WiFi-specific deployment
 cd /home/jim/Projects/frey0

 # Deploy ONLY WiFi access point changes
 ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
   --tags wifi_access_point \
   --vault-password-file .vault_pass

 2.3 Verify WiFi AP is working
 # SSH to Pi and check services
 ssh jim@<pi-ip>

 # Check hostapd (AP broadcasting)
 sudo systemctl status hostapd
 iw dev wlan1 info

 # Check dnsmasq (DHCP/DNS)
 sudo systemctl status dnsmasq
 ss -ulnp | grep dnsmasq

 # Check wpa_supplicant (client networks with priorities)
 cat /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
 sudo systemctl status wpa_supplicant-wlan0

 # Verify FreyHub AP is visible
 # (Check from another device - should see FreyHub network)

 ---
 Phase 3: Copy WiFi Config to NVMe (Prepare for Migration)

 3.1 Verify NVMe is detected
 # On Pi via SSH
 lsblk
 # Should show /dev/nvme0n1

 3.2 Copy critical WiFi configs to NVMe root
 # Mount NVMe partition (if using boot from NVMe)
 sudo mkdir -p /mnt/nvme
 sudo mount /dev/nvme0n1p2 /mnt/nvme  # Adjust partition if different

 # Copy WiFi configurations
 sudo cp -a /etc/wpa_supplicant /mnt/nvme/etc/
 sudo cp -a /etc/hostapd /mnt/nvme/etc/
 sudo cp -a /etc/dnsmasq.d /mnt/nvme/etc/
 sudo cp -a /etc/dhcpcd.conf /mnt/nvme/etc/
 sudo cp -a /etc/systemd/system/wpa_supplicant-wlan0.service /mnt/nvme/etc/systemd/system/
 sudo cp -a /etc/systemd/system/hostapd.service.d /mnt/nvme/etc/systemd/system/
 sudo cp -a /etc/systemd/system/dnsmasq.service.d /mnt/nvme/etc/systemd/system/

 # Copy fail2ban config (with laptop whitelisted)
 sudo cp -a /etc/fail2ban /mnt/nvme/etc/

 # Unmount
 sudo umount /mnt/nvme

 ---
 Phase 4: NVMe Boot Setup (Follow PreSetup.md)

 4.1 Configure NVMe boot on SD card
 # On Pi (still booted from SD)
 sudo rpi-eeprom-config --edit

 # Add/modify:
 BOOT_ORDER=0xf416  # NVMe first, then SD, then USB
 PCIEE_PROBE=1

 # Save and reboot
 sudo reboot

 4.2 After reboot - verify boot device
 # Should boot from NVMe now
 lsblk -o NAME,MOUNTPOINT,SIZE,TYPE
 # Check / is mounted from /dev/nvme0n1p2

 ---
 Phase 5: Full Deployment on NVMe

 5.1 Update inventory for NVMe-booted Pi
 # From laptop, edit inventory/hosts.yml
 # IP might have changed after NVMe boot

 nano inventory/hosts.yml

 5.2 Run complete deployment
 # Full stack deployment
 ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
   --vault-password-file .vault_pass

 # This deploys:
 # - All WiFi fixes (AP + priorities)
 # - Docker infrastructure
 # - Media services
 # - Monitoring stack
 # - All security settings

 5.3 Final verification
 # SSH to Pi
 ssh jim@<pi-ip>

 # Verify WiFi AP
 sudo systemctl status hostapd dnsmasq
 iw dev wlan1 info

 # Verify network priorities
 cat /etc/wpa_supplicant/wpa_supplicant-wlan0.conf | grep -A3 priority

 # Verify Docker services
 docker ps

 # Check FreyHub AP is broadcasting
 # (From another device, connect to FreyHub network)

 ---
 Phase 6: Add Laptop & Phone Hotspot to Permanent Whitelist

 6.1 Get network details
 # On Pi, identify phone hotspot subnet
 ip route | grep default
 ip addr show wlan0

 # Note the subnet (e.g., 172.20.10.0/28)

 6.2 Update Ansible config
 # From laptop, edit group_vars/all/main.yml
 nano group_vars/all/main.yml

 # Add to network_security section:
 network_security:
   trusted_networks:
     - "192.168.0.0/24"
     - "10.20.0.0/24"
     - "172.20.10.0/28"  # ADD: Phone hotspot subnet

   trusted_device_ips:
     - "192.168.0.184"
     - "<laptop-hotspot-ip>"  # ADD: Laptop's IP on phone hotspot

 6.3 Redeploy security config
 ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
   --tags security \
   --vault-password-file .vault_pass

 ---
 Summary Checklist

 ✅ Phase 1: Clear iptables, restore laptop SSH
 ✅ Phase 2: Deploy WiFi fixes (AP + priorities)
 ✅ Phase 3: Copy WiFi configs to NVMe
 ✅ Phase 4: Configure NVMe boot
 ✅ Phase 5: Full deployment on NVMe
 ✅ Phase 6: Whitelist phone hotspot permanently