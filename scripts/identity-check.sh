#!/usr/bin/env bash
#
# Check that single sign-on is actually doing its job.
#
# Run from the repository root, from a machine that can reach the Pi:
#
#     scripts/identity-check.sh
#
# It asserts the four things that matter and are easy to break silently:
#
#   1. Protected services bounce an anonymous request to the login page.
#      A 200 here means forward auth is OFF for that service - most likely a
#      Traefik router was dropped because it named a middleware that did not
#      exist, which 404s or serves openly rather than erroring anywhere you
#      would notice.
#
#   2. Unprotected services still answer plain HTTP. This is deliberate, not an
#      oversight: a television cannot install a private root certificate and
#      gives you no way to click through, so forcing HTTPS would take Jellyfin
#      away from the TV.
#
#   3. Legacy *.frey names redirect to *.hub.frey rather than 404ing.
#
#   4. The certificate is not about to expire, and covers what it should.
#
# Exits non-zero if any assertion fails, so it is usable from a cron job.

set -uo pipefail

PI_ADDR="${PI_ADDR:-10.20.0.1}"
CA="${CA:-ca/frey-root-ca.crt}"
DOMAIN="${DOMAIN:-hub.frey}"
LEGACY="${LEGACY:-frey}"

fails=0
pass() { printf '  \033[32mok\033[0m    %-44s %s\n' "$1" "$2"; }
fail() { printf '  \033[31mFAIL\033[0m  %-44s %s\n' "$1" "$2"; fails=$((fails + 1)); }

if [[ ! -r "$CA" ]]; then
    echo "No root certificate at $CA."
    echo "Run: ansible-playbook -i inventory/hosts.yml playbooks/site.yml \\"
    echo "       --tags pki --vault-password-file .vault_pass"
    exit 1
fi

code() { # scheme host path
    curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
        --cacert "$CA" \
        --resolve "${2}:443:${PI_ADDR}" --resolve "${2}:80:${PI_ADDR}" \
        "${1}://${2}${3}" 2>/dev/null
}

# Services behind the login page. Keep in step with identity_services.
PROTECTED=(sonarr radarr lidarr chaptarr prowlarr bazarr cleanuparr
           qbittorrent maintainerr jellystat audiobookrequest navidrome)
# Services that keep their own login, or none. These must stay on HTTP.
OPEN=(jellyfin audiobookshelf seerr)

echo "Protected services should send an anonymous request to the login page:"
for svc in "${PROTECTED[@]}"; do
    c=$(code https "${svc}.${DOMAIN}" /)
    if [[ "$c" == "302" ]]; then
        pass "${svc}.${DOMAIN}" "302 -> login"
    else
        fail "${svc}.${DOMAIN}" "expected 302, got ${c:-no answer}"
    fi
done

echo
echo "Unprotected services should still answer plain HTTP (the TV path):"
for svc in "${OPEN[@]}"; do
    c=$(code http "${svc}.${DOMAIN}" /)
    # 2xx or an app's own redirect are both fine; a bounce to the auth host is
    # not, and neither is nothing at all.
    if [[ "$c" =~ ^(200|204|30[0-9])$ ]]; then
        pass "${svc}.${DOMAIN}" "$c"
    else
        fail "${svc}.${DOMAIN}" "expected 2xx/3xx, got ${c:-no answer}"
    fi
done

echo
echo "The login page and the directory should be up:"
for svc in auth users; do
    c=$(code https "${svc}.${DOMAIN}" /)
    [[ "$c" == "200" ]] && pass "${svc}.${DOMAIN}" "200" \
        || fail "${svc}.${DOMAIN}" "expected 200, got ${c:-no answer}"
done

echo
echo "OIDC discovery should be served:"
iss=$(curl -sS --max-time 10 --cacert "$CA" \
    --resolve "auth.${DOMAIN}:443:${PI_ADDR}" \
    "https://auth.${DOMAIN}/.well-known/openid-configuration" 2>/dev/null \
    | sed -n 's/.*"issuer":"\([^"]*\)".*/\1/p')
[[ "$iss" == "https://auth.${DOMAIN}" ]] \
    && pass "issuer" "$iss" \
    || fail "issuer" "expected https://auth.${DOMAIN}, got ${iss:-nothing}"

echo
echo "Legacy names should redirect rather than 404:"
for svc in jellyfin sonarr books; do
    c=$(code https "${svc}.${LEGACY}" /)
    [[ "$c" == "301" ]] && pass "${svc}.${LEGACY}" "301 -> ${svc}.${DOMAIN}" \
        || fail "${svc}.${LEGACY}" "expected 301, got ${c:-no answer}"
done

echo
echo "Certificate:"
cert=$(echo | openssl s_client -connect "${PI_ADDR}:443" \
    -servername "auth.${DOMAIN}" -CAfile "$CA" 2>/dev/null \
    | openssl x509 -noout -enddate -ext subjectAltName 2>/dev/null)
end=$(sed -n 's/^notAfter=//p' <<<"$cert")
if [[ -n "$end" ]]; then
    left=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
    if (( left > 30 )); then
        pass "expiry" "$left days left"
    else
        fail "expiry" "$left days left - frey_pki renews inside 30, so run the pki tag"
    fi
    grep -q "DNS:auth.${DOMAIN}" <<<"$cert" \
        && pass "covers auth.${DOMAIN}" "yes" \
        || fail "covers auth.${DOMAIN}" "missing from SANs - run the pki tag"
else
    fail "certificate" "could not read it from ${PI_ADDR}:443"
fi

echo
if (( fails )); then
    echo "${fails} check(s) failed. See docs/IDENTITY.md."
    exit 1
fi
echo "All checks passed."
