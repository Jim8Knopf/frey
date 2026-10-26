# Step-CA Implementation TODO

## Current Status
- ✅ Self-signed certificates working (Traefik serving *.frey wildcard cert)
- ✅ Step-CA service added to docker-compose (commented out due to port conflict)
- ✅ Infrastructure directories created
- ⏳ Step-CA initialization and ACME integration pending

## Remaining Steps for Step-CA Implementation

### Phase 1: Configure Step-CA Container

1. **Fix port conflict**
   - Step-CA default port 9000 conflicts with Portainer
   - Options:
     - Change Step-CA to port 9446 (HTTPS) - **RECOMMENDED**
     - Change Portainer to different port
   - Update docker-compose-infrastructure.yml.j2 Step-CA service

2. **Uncomment and deploy Step-CA service**
   ```bash
   # Edit roles/infrastructure/templates/docker-compose-infrastructure.yml.j2
   # Uncomment the step-ca service block (lines 180-200)
   # Deploy
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure --vault-password-file .vault_pass
   ```

### Phase 2: Initialize Step-CA

3. **Initialize Step-CA with interactive setup**
   ```bash
   ssh frey
   docker run -it -v /opt/frey/appdata/step-ca:/home/step \
     smallstep/step-ca:latest step ca init
   ```

   **Initialization prompts:**
   - What would you like to name your new PKI? → `Frey CA`
   - What DNS names or IP addresses would you like to add to your new CA? → `step-ca,step-ca.frey,192.168.0.252`
   - What address will your new CA listen at? → `:9446`
   - What would you like to name the first provisioner for your new CA? → `admin`
   - What do you want your password to be? → Generate secure password (save to secrets.yml)

4. **Enable ACME provisioner**
   ```bash
   # Inside step-ca container or on host with step CLI
   docker exec -it step-ca step ca provisioner add acme --type ACME
   ```

5. **Update Step-CA configuration for wildcard support**
   ```bash
   # Edit /opt/frey/appdata/step-ca/config/ca.json
   # Add to ACME provisioner:
   "challenges": ["http-01", "tls-alpn-01"]
   ```

### Phase 3: Configure Traefik for ACME

6. **Update traefik.yml.j2**

   Replace static certificate config with ACME:
   ```yaml
   # Remove these lines:
   tls:
     certificates:
       - certFile: /certificates/frey.crt
         keyFile: /certificates/frey.key

   # Add this:
   certificatesResolvers:
     step-ca:
       acme:
         email: "{{ admin_email }}"
         storage: /certificates/step-ca-acme.json
         caServer: https://step-ca:9446/acme/acme/directory
         certificatesResolvers:
           step-ca:
             acme:
               tlsChallenge: {}
   ```

7. **Update docker-compose-infrastructure.yml.j2 for Traefik**

   Add Step-CA root cert to Traefik:
   ```yaml
   traefik:
     environment:
       - LEGO_CA_CERTIFICATES=/certificates/step-ca-root.crt
     volumes:
       - "{{ storage.appdata_dir }}/step-ca/certs/root_ca.crt:/certificates/step-ca-root.crt:ro"
   ```

8. **Update service labels**

   Change from static cert to ACME resolver:
   ```yaml
   # For all services (Traefik, Portainer, Authentik):
   # REMOVE: tls.certresolver lines
   # ADD:
   - "traefik.http.routers.SERVICE.tls.certresolver=step-ca"
   ```

### Phase 4: Bootstrap and Deploy

9. **Copy Step-CA root cert to Traefik certificates directory**
   ```bash
   ssh frey
   sudo cp /opt/frey/appdata/step-ca/certs/root_ca.crt /opt/frey/appdata/traefik/certificates/step-ca-root.crt
   sudo chmod 644 /opt/frey/appdata/traefik/certificates/step-ca-root.crt
   ```

10. **Deploy infrastructure stack**
    ```bash
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags infrastructure --vault-password-file .vault_pass
    ```

### Phase 5: Verification

11. **Check Step-CA health**
    ```bash
    ssh frey "docker logs step-ca --tail 50"
    ssh frey "curl -k https://localhost:9446/health"
    ```

12. **Check Traefik ACME certificate acquisition**
    ```bash
    ssh frey "docker logs traefik --tail 100 | grep -i 'acme\|certificate'"
    ```

13. **Verify certificate issuer**
    ```bash
    # Should show "Frey CA" as issuer
    echo | openssl s_client -connect auth.frey:443 -servername auth.frey 2>/dev/null | openssl x509 -noout -issuer
    ```

### Phase 6: Update Media Stack

14. **Update media services to use ACME**
    - Edit `roles/media/templates/docker-compose-media.yml.j2`
    - Change entrypoints from `web` to `websecure`
    - Add TLS certresolver labels
    - Deploy media stack

---

## Current Working Solution: Self-Signed Certificates

**Status:** ✅ WORKING - Services accessible via HTTPS with manual CA install

### Client Installation Instructions

#### Linux (Your Laptop)

1. **Install CA certificate system-wide:**
   ```bash
   sudo cp /home/jim/Downloads/frey-ca.crt /usr/local/share/ca-certificates/frey-ca.crt
   sudo update-ca-certificates
   ```

   **Expected output:**
   ```
   Updating certificates in /etc/ssl/certs...
   1 added, 0 removed; done.
   ```

2. **For Firefox (uses own cert store):**
   ```bash
   # Firefox → Settings → Privacy & Security → Certificates → View Certificates
   # → Authorities tab → Import → Select frey-ca.crt
   # → Check "Trust this CA to identify websites"
   ```

3. **Verify installation:**
   ```bash
   # Test connection (should show no SSL errors)
   curl https://auth.frey

   # Check certificate in browser
   # Navigate to https://auth.frey
   # Click padlock → Connection is secure → Certificate is valid
   ```

#### Android Phone

1. **Transfer CA certificate to phone:**
   - Option 1: Email frey-ca.crt to yourself
   - Option 2: Upload to Google Drive/Dropbox
   - Option 3: ADB push:
     ```bash
     adb push /home/jim/Downloads/frey-ca.crt /sdcard/Download/
     ```

2. **Install certificate on Android:**
   - Open **Settings**
   - Navigate to **Security** (or **Biometrics and security**)
   - Tap **Install from storage** (or **Install a certificate**)
   - Tap **CA certificate**
   - Warning popup: Tap **Install anyway**
   - Browse to Downloads folder
   - Tap `frey-ca.crt`
   - Enter your screen lock PIN/pattern/password
   - Give it a name: `Frey Root CA`
   - Tap **OK**

3. **Verify installation:**
   - Settings → Security → Trusted credentials → User tab
   - Should see "Frey Root CA" listed
   - Open Chrome and navigate to `https://auth.frey`
   - Should show green padlock, no warnings

#### Windows (if needed)

```powershell
# Run as Administrator
certutil -addstore -f "ROOT" "C:\path\to\frey-ca.crt"
```

Or via GUI:
1. Double-click `frey-ca.crt`
2. Click "Install Certificate"
3. Choose "Local Machine"
4. Select "Place all certificates in the following store"
5. Browse → "Trusted Root Certification Authorities"
6. Finish

#### macOS (if needed)

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain frey-ca.crt
```

Or via GUI:
1. Double-click `frey-ca.crt`
2. Keychain Access opens
3. Select "System" keychain
4. Find "Frey Root CA"
5. Double-click → Trust → "Always Trust"
6. Close and enter admin password

---

## Testing Checklist

### Current Self-Signed Setup
- [ ] Linux laptop: CA cert installed, no browser warnings
- [ ] Android phone: CA cert installed, no browser warnings
- [ ] Services accessible:
  - [ ] https://auth.frey (Authentik)
  - [ ] https://portainer.frey
  - [ ] https://traefik.frey
  - [ ] https://jellyfin.frey (if media uses HTTPS)
  - [ ] https://audiobookshelf.frey
  - [ ] https://immich.frey
  - [ ] https://cookbook.frey (Mealie)

### After Step-CA Implementation (Future)
- [ ] Step-CA container running and healthy
- [ ] ACME provisioner enabled
- [ ] Traefik successfully requests certs from Step-CA
- [ ] Certificates auto-renew (check after 60 days)
- [ ] New services automatically get certificates

---

## Estimated Time

- **Self-signed cert installation (current):** 10-15 minutes total
  - Linux: 2 minutes
  - Android: 5 minutes
  - Testing: 5 minutes

- **Step-CA full implementation (future):** 2-4 hours
  - Configuration: 1 hour
  - Troubleshooting: 1-2 hours
  - Testing: 30 minutes
  - Learning curve: varies

---

## Recommendation

**For Personal Homelab:** Self-signed certificates (current solution) are **perfectly adequate**.

**Benefits of current approach:**
- ✅ Works immediately after one-time client install
- ✅ 10-year validity (no renewal needed)
- ✅ Simple, no moving parts
- ✅ Zero maintenance

**When to implement Step-CA:**
- You have 20+ services requiring certificates
- You want to learn production PKI practices
- You're paranoid about 10-year cert expiry
- You enjoy infrastructure projects

**Reality check:** For a homelab with local-only access, the automation benefits of Step-CA vs self-signed are minimal. The current solution works perfectly.

---

## Files Modified (Current State)

```
roles/infrastructure/templates/
├── traefik.yml.j2                          # Uses static certificates
├── docker-compose-infrastructure.yml.j2     # Step-CA service commented out
└── authentik-blueprints/
    └── 14-oidc-mealie.yaml.j2              # Mealie OIDC working

roles/infrastructure/tasks/main.yml          # step-ca folder added

group_vars/all/
├── main.yml                                 # admin_email added
└── secrets.yml                              # mealie_oidc_client_secret added

/opt/frey/appdata/traefik/certificates/      # On frey server
├── frey-ca.crt                              # Root CA (10 years)
├── frey-ca.key                              # Root CA private key
├── frey.crt                                 # Wildcard cert (10 years)
└── frey.key                                 # Wildcard private key

/home/jim/Downloads/frey-ca.crt              # Local copy for installation
```

---

## Support

If SSL warnings persist after installing CA cert:
1. Restart browser completely
2. Clear browser cache and SSL state
3. Verify cert is in system trust store
4. Check DNS resolves `*.frey` to correct IP
5. Verify services are accessible via HTTPS

For Step-CA implementation help:
- Official docs: https://smallstep.com/docs/step-ca
- Traefik integration: https://doc.traefik.io/traefik/https/acme/#step-ca
