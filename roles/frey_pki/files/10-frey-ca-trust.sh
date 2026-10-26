#!/bin/sh
# ==============================================================================
# Teach this container to trust the Frey CA.
#
# Managed by Ansible role: frey_pki. Do not edit on the Pi.
#
# Runs as root before the service starts, via linuxserver.io's
# /custom-cont-init.d hook. Needed because an app doing OIDC calls
# https://auth.hub.frey directly from inside the container - fetching the
# discovery document, exchanging the code for a token - and those calls are not
# made by a browser, so the device trust store is irrelevant to them.
#
# Exits 0 whatever happens. A container that cannot update its trust store must
# still start: losing SSO on one service is recoverable, a media server that
# refuses to boot while parked off-grid is not.
# ==============================================================================
set -u

CA_SRC=/frey-ca.crt
CA_DST=/usr/local/share/ca-certificates/frey-root-ca.crt

if [ ! -r "$CA_SRC" ]; then
    echo "[frey-ca-trust] $CA_SRC not mounted; leaving trust store alone"
    exit 0
fi

# Only rewrite when the contents actually differ, so a restart is not a
# pointless trust-store rebuild.
if [ -r "$CA_DST" ] && cmp -s "$CA_SRC" "$CA_DST"; then
    echo "[frey-ca-trust] Frey CA already trusted"
    exit 0
fi

mkdir -p /usr/local/share/ca-certificates || exit 0
cp "$CA_SRC" "$CA_DST" || exit 0

if command -v update-ca-certificates >/dev/null 2>&1; then
    update-ca-certificates >/dev/null 2>&1 \
        && echo "[frey-ca-trust] Frey CA installed" \
        || echo "[frey-ca-trust] update-ca-certificates failed; continuing"
else
    echo "[frey-ca-trust] no update-ca-certificates in this image; continuing"
fi

exit 0
