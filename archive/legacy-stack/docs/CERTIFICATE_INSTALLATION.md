# Frey Root CA Installation

The Frey deployment issues TLS certificates from a private Step-CA authority. Install the Frey Root CA on every device before accessing `https://frey` or any `https://<service>.frey` endpoint. The landing page at `https://frey` always exposes the latest CA download plus OS-specific quick instructions.

## Download the certificate

- Visit `https://frey` (or `https://landing.frey`) after authentication.
- Click **Download Frey Root CA** to grab `frey-root-ca.crt`.
- Verify integrity if desired: `openssl sha256 frey-root-ca.crt`

## Android 14/15

1. Transfer `frey-root-ca.crt` to the device (Downloads folder is fine).
2. Open **Settings → Security & privacy → More security settings → Encryption & credentials**.
3. Tap **Install certificate → CA certificate**, approve the warning, and select the Frey file.
4. Reboot the phone/tablet so Chrome, Firefox, and self-hosted apps trust `*.frey`.
5. Verify under **Trusted credentials → User tab** that “Frey Root CA” is listed.

## Manjaro / Arch Linux

1. Copy the certificate into the system trust store:
   ```bash
   sudo install -m 644 frey-root-ca.crt /usr/local/share/ca-certificates/frey-root-ca.crt
   ```
2. Refresh trust anchors:
   ```bash
   sudo update-ca-trust  # or sudo trust extract-compat
   ```
3. Restart browsers or services that maintain their own trust cache.
4. Confirm with `trust list | grep "Frey Root"` to ensure the CA is active.

## Troubleshooting

- Android requires the device to have a PIN/biometric lock before adding user CA certificates.
- Some desktop apps (e.g., Firefox) maintain their own trust store; import the CRT in their settings if warnings continue.
- If a service still shows certificate warnings, confirm you are resolving the `.frey` hostname locally (AdGuard/dnsmasq) and that the landing page serves the newest CA file.
