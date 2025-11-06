# Step CA Setup Guide - Permanent SSL Certificate Solution

This guide provides step-by-step instructions for implementing Step CA as a private Certificate Authority for the Frey infrastructure, eliminating SSL certificate warnings permanently.

## Overview

**Step CA** is a professional-grade certificate authority that provides:
- ✅ Automated certificate generation via ACME protocol
- ✅ Automatic certificate renewal (no manual intervention needed)
- ✅ Trusted certificates on all devices after one-time CA installation
- ✅ No more "accept risk" warnings in browsers
- ✅ Works with Firefox (which has a separate certificate store)
- ✅ Production-ready PKI infrastructure

## Current Status

Step CA configuration is **prepared but disabled** in the Frey infrastructure. The service is commented in docker-compose and can be enabled when ready.

**Location:** `roles/infrastructure/templates/docker-compose-infrastructure.yml.j2` (lines 180-210)

## Prerequisites

Before enabling Step CA:
1. ✅ Frey infrastructure fully deployed and running
2. ✅ Traefik reverse proxy operational
3. ✅ DNS resolution working for `*.frey` domain
4. ✅ Current self-signed certificates working (baseline functionality)

## Phase 1: Enable Step CA Service

### Step 1.1: Enable in Configuration

Edit `group_vars/all/main.yml` line 356:

```yaml
step_ca:
  enabled: true  # Change from false to true
  version: "latest"
  port: 9446
```

### Step 1.2: Deploy Infrastructure

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure
```

This will:
- Deploy Step CA container
- Expose port 9446 for ACME server
- Make it accessible at `https://ca.frey` via Traefik

### Step 1.3: Verify Deployment

```bash
ssh frey "docker ps | grep step-ca"
ssh frey "docker logs step-ca"
```

## Phase 2: Initialize Step CA

### Step 2.1: Run Interactive Initialization

```bash
ssh frey
docker exec -it step-ca step ca init
```

**Answer the prompts:**

| Prompt | Answer | Notes |
|--------|--------|-------|
| Deployment Type | `Standalone` | For single-server setup |
| Name | `Frey CA` | Display name for CA |
| DNS names | `ca.frey,step-ca.frey` | Hostnames for CA server |
| Address | `:9446` | Port for ACME server |
| First provisioner | `admin` | Admin provisioner name |
| Password | `<secure password>` | **Save this password!** |

**Example session:**
```
? What deployment type would you like to configure? Standalone
? What would you like to name your new PKI? Frey CA
? What DNS names or IP addresses would you like to add to your new CA? ca.frey,step-ca.frey
? What IP and port will your new CA bind to? :9446
? What would you like to name the CA's first provisioner? admin
? Choose a password for your CA keys (leave empty for no password): <enter secure password>
```

### Step 2.2: Configure ACME Provisioner

After initialization, add ACME provisioner for automatic certificate issuance:

```bash
docker exec -it step-ca step ca provisioner add acme --type ACME
```

### Step 2.3: Restart Step CA

```bash
docker restart step-ca
```

### Step 2.4: Verify ACME Endpoint

```bash
curl -k https://ca.frey:9446/acme/acme/directory
```

Should return JSON with ACME endpoints.

## Phase 3: Configure Traefik for ACME

### Step 3.1: Update Traefik Configuration

Edit `roles/infrastructure/templates/traefik.yml.j2` and add ACME configuration:

```yaml
# After the tls.certificates section, add:

certificatesResolvers:
  step-ca:
    acme:
      email: admin@frey.local
      storage: /acme/acme.json
      caServer: https://ca.frey:9446/acme/acme/directory
      certificatesDuration: 2160  # 90 days
      tlsChallenge: true  # Use TLS-ALPN-01 challenge
```

### Step 3.2: Update Service Labels

For each service in docker-compose templates, add the ACME cert resolver:

**Example for Immich** (`roles/immich/templates/docker-compose-immich.yml.j2`):

```yaml
labels:
  - "traefik.http.routers.immich.tls=true"
  - "traefik.http.routers.immich.tls.certresolver=step-ca"  # Add this line
```

Repeat for all services that use TLS:
- Authentik
- Portainer
- Dockge
- Jellyfin
- Immich
- Audiobookshelf
- Jellyseerr
- Grafana
- Radarr/Sonarr/Prowlarr/etc.

### Step 3.3: Create ACME Storage Directory

```bash
ssh frey
mkdir -p /opt/frey/appdata/traefik/acme
chown 46372:46372 /opt/frey/appdata/traefik/acme  # infrastructure user
chmod 700 /opt/frey/appdata/traefik/acme
```

### Step 3.4: Update Traefik Volume Mount

Edit `roles/infrastructure/templates/docker-compose-infrastructure.yml.j2`:

```yaml
traefik:
  volumes:
    # ... existing volumes ...
    - "{{ storage.appdata_dir }}/traefik/acme:/acme"  # Add this line
```

### Step 3.5: Redeploy Infrastructure

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure
```

### Step 3.6: Monitor Certificate Generation

```bash
ssh frey "docker logs traefik -f"
```

Watch for ACME challenge messages. Traefik will automatically request certificates from Step CA.

## Phase 4: Install CA Certificate on Client Devices

### Step 4.1: Download CA Root Certificate

**From Frey server:**
```bash
# Copy to local machine
scp frey:/opt/frey/appdata/step-ca/certs/root_ca.crt ~/Downloads/frey-root-ca.crt
```

**Or via web browser:**
Navigate to: `https://ca.frey:9446/roots.pem`

### Step 4.2: Install on Each Device

#### Android

1. Transfer `frey-root-ca.crt` to device (via USB, cloud, etc.)
2. **Settings** → **Security** → **Encryption & credentials**
3. **Install a certificate** → **CA certificate**
4. Select the downloaded file
5. Choose **VPN and apps** (NOT Wi-Fi only)
6. Enter PIN/password to confirm

**Verification:**
- Open Chrome and navigate to `https://immich.frey`
- Should show secure padlock, no warnings

#### iOS/iPadOS

1. AirDrop `frey-root-ca.crt` to device
2. Tap the received file → **Install**
3. **Settings** → **General** → **VPN & Device Management**
4. Tap **Frey CA** → **Install** → Enter passcode
5. **Settings** → **General** → **About** → **Certificate Trust Settings**
6. Enable **Frey CA**

**Verification:**
- Open Safari and navigate to `https://immich.frey`
- Should show secure padlock

#### Windows

1. Right-click `frey-root-ca.crt`
2. **Install Certificate**
3. **Store Location:** Local Machine (requires admin) or Current User
4. **Certificate Store:** Place in **Trusted Root Certification Authorities**
5. Click **Next** → **Finish**

**Verification:**
- Open Edge/Chrome and navigate to `https://immich.frey`
- Should show secure padlock

#### macOS

1. Double-click `frey-root-ca.crt`
2. **Add to keychain:** System or login
3. Open **Keychain Access** app
4. Find **Frey CA** certificate
5. Double-click → Expand **Trust**
6. Set **When using this certificate:** to **Always Trust**
7. Close window and enter password

**Verification:**
- Open Safari and navigate to `https://immich.frey`
- Should show secure padlock

#### Linux

##### Ubuntu/Debian

```bash
# Copy certificate to CA directory
sudo cp ~/Downloads/frey-root-ca.crt /usr/local/share/ca-certificates/frey-root-ca.crt

# Update CA certificates
sudo update-ca-certificates

# Verify
curl -v https://immich.frey 2>&1 | grep "SSL certificate verify ok"
```

##### Manjaro/Arch

```bash
# Create directory if it doesn't exist
sudo mkdir -p /usr/local/share/ca-certificates

# Copy certificate to CA directory
sudo cp ~/Downloads/frey-root-ca.crt /usr/local/share/ca-certificates/frey-root-ca.crt

# Add certificate to system trust store
sudo trust anchor --store /usr/local/share/ca-certificates/frey-root-ca.crt

# Verify
curl -v https://immich.frey 2>&1 | grep "SSL certificate verify ok"
```

**Verification:**

- Should output: `SSL certificate verify ok`

#### Firefox (All Platforms)

Firefox uses its own certificate store, separate from the OS:

1. Open **Firefox**
2. **Settings** (or **Preferences** on macOS)
3. **Privacy & Security**
4. Scroll to **Certificates** → **View Certificates**
5. **Authorities** tab → **Import**
6. Select `frey-root-ca.crt`
7. Check **Trust this CA to identify websites**
8. Click **OK**

**Verification:**
- Navigate to `https://immich.frey`
- Should show secure padlock

## Phase 5: Testing and Verification

### Test Certificate Issuance

```bash
# Check Traefik logs for ACME messages
ssh frey "docker logs traefik | grep -i acme"

# View issued certificates
ssh frey "cat /opt/frey/appdata/traefik/acme/acme.json | jq '.step-ca.Certificates'"
```

### Test All Services

Visit each service and verify secure connection:

- https://immich.frey → ✅ Secure
- https://auth.frey → ✅ Secure
- https://portainer.frey → ✅ Secure
- https://jellyfin.frey → ✅ Secure
- https://audiobookshelf.frey → ✅ Secure
- https://grafana.frey → ✅ Secure

**Success criteria:**

- Green padlock in browser
- No certificate warnings
- Certificate issued by "Frey CA"
- Valid for 90 days

### Verify Auto-Renewal

Certificates will auto-renew when they have less than 30 days remaining. Traefik handles this automatically.

**Check renewal logs:**

```bash
ssh frey "docker logs traefik | grep -i renewal"
```

## Troubleshooting

### Issue: ACME Challenge Fails

**Symptom:** Traefik logs show "error getting certificate"

**Solution:**

```bash
# Verify Step CA is running
docker ps | grep step-ca

# Check Step CA logs
docker logs step-ca

# Verify ACME endpoint is accessible
curl -k https://ca.frey:9446/acme/acme/directory

# Restart Traefik
docker restart traefik
```

### Issue: Certificate Not Trusted After Installation

**Symptom:** Browser still shows warnings after CA installation

**Solution:**

1. Verify CA certificate was installed in correct store
2. Restart browser completely (not just close window)
3. Clear browser cache and certificates
4. On mobile, ensure certificate was installed as "VPN and apps" not "Wi-Fi"

### Issue: Step CA Container Won't Start

**Symptom:** `docker logs step-ca` shows initialization errors

**Solution:**

```bash
# Remove existing Step CA data and reinitialize
ssh frey
rm -rf /opt/frey/appdata/step-ca/*
docker restart step-ca
docker exec -it step-ca step ca init  # Run initialization again
```

## Maintenance

### Check Certificate Expiry

```bash
# View certificate details
echo | openssl s_client -servername immich.frey -connect 192.168.0.252:443 2>/dev/null | openssl x509 -noout -dates
```

### Manual Certificate Renewal (if needed)

Traefik handles renewal automatically, but to force renewal:

```bash
# Remove existing certificate
ssh frey "rm /opt/frey/appdata/traefik/acme/acme.json"

# Restart Traefik to trigger new certificate request
ssh frey "docker restart traefik"
```

### Backup CA Keys

**Critical:** Backup Step CA keys regularly:

```bash
# From frey server
tar -czf step-ca-backup-$(date +%Y%m%d).tar.gz /opt/frey/appdata/step-ca/

# Copy to safe location
scp step-ca-backup-*.tar.gz backup-server:/path/to/backups/
```

## Rollback to Self-Signed Certificates

If Step CA causes issues, you can revert:

1. Disable Step CA:

   ```yaml
   # group_vars/all/main.yml
   step_ca:
     enabled: false
   ```

2. Remove ACME configuration from Traefik:

   ```bash
   git checkout roles/infrastructure/templates/traefik.yml.j2
   ```

3. Redeploy:

   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure
   ```

4. Services will fall back to static self-signed certificates

## Benefits Summary

After completing this setup:

- ✅ **No more certificate warnings** on any device
- ✅ **Automatic renewal** - certificates refresh every 90 days
- ✅ **Professional infrastructure** - production-ready PKI
- ✅ **Works everywhere** - iOS, Android, Windows, macOS, Linux, Firefox
- ✅ **Zero ongoing maintenance** - Traefik and Step CA handle everything

## Next Steps

After successful deployment:

1. ✅ Install CA certificate on all your devices
2. ✅ Share `frey-root-ca.crt` with family/friends who use your services
3. ✅ Set up automated backups of Step CA data
4. ✅ Document the CA password in a secure password manager
5. ✅ Monitor certificate renewal logs monthly

## Additional Resources

- [Step CA Documentation](https://smallstep.com/docs/step-ca/)
- [Traefik ACME Documentation](https://doc.traefik.io/traefik/https/acme/)
- [ACME Protocol Specification](https://tools.ietf.org/html/rfc8555)

---

**Note:** Step CA is currently **disabled by default** in the Frey infrastructure. Enable it in `group_vars/all/main.yml` when you're ready to implement ACME-based certificate management.
