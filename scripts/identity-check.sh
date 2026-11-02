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
#   1. Services listed as `forward_auth` bounce an anonymous request to the
#      login page. A 200 here means forward auth is OFF for that service -
#      most likely a Traefik router was dropped because it named a middleware
#      that did not exist, which 404s or serves openly rather than erroring
#      anywhere you would notice.
#
#   2. Everything else still answers plain HTTP. This is deliberate, not an
#      oversight: a television cannot install a private root certificate and
#      gives you no way to click through, so forcing HTTPS would take Jellyfin
#      away from the TV.
#
#   Which service is which is read out of inventory/group_vars/all/identity.yml
#   at run time, never copied into this file - see the note above PROTECTED.
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
MATRIX="${MATRIX:-inventory/group_vars/all/identity.yml}"

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

# Status code and, if it redirected, where to - so a 302 can be checked for
# pointing at the login page rather than merely being a 302.
code_and_target() { # scheme host path -> "<code> <url>"
    curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 \
        --cacert "$CA" \
        --resolve "${2}:443:${PI_ADDR}" --resolve "${2}:80:${PI_ADDR}" \
        "${1}://${2}${3}" 2>/dev/null
}

# Who is expected to do what is read out of the auth matrix rather than copied
# into this script, because a copy drifts silently and in the dangerous
# direction: when cleanuparr moved from forward_auth to oidc, the copy here
# went on demanding a 302 from it, and the only thing failing in the suite was
# this file. The next person to "fix" that by deleting a name from a list would
# have been one keystroke from relaxing a real expectation by accident.
#
# Two categories, and the split is exactly how Traefik is labelled:
#
#   forward_auth  -> authelia@file in front of it; an anonymous request never
#                    reaches the app, and plain HTTP is upgraded away.
#   oidc / none   -> no middleware; the app does its own login and keeps
#                    answering plain HTTP.
#
# Every hostname a service answers on is checked, aliases included, since each
# one is a separate Traefik router rule that can be got wrong on its own.
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
if [[ ! -r "$MATRIX" ]]; then
    echo "Cannot read the auth matrix at $MATRIX."
    echo "Run this from the repository root, or set MATRIX=<path>."
    exit 1
fi

matrix=$(python3 - "$MATRIX" <<'PYTHON'
import sys

try:
    import yaml
except ImportError:
    sys.exit("python3 yaml module is required (pip install pyyaml)")

services = (yaml.safe_load(open(sys.argv[1])) or {}).get("identity_services") or {}
if not services:
    sys.exit("no identity_services in " + sys.argv[1])

for name, cfg in sorted(services.items()):
    cfg = cfg or {}
    bucket = "protected" if cfg.get("auth") == "forward_auth" else "open"
    for host in cfg.get("hosts") or [name]:
        print(bucket, host)
PYTHON
) || exit 1

mapfile -t PROTECTED < <(awk '$1 == "protected" { print $2 }' <<<"$matrix")
mapfile -t OPEN < <(awk '$1 == "open" { print $2 }' <<<"$matrix")

# A matrix that parsed but yielded nothing protected would make every check
# below vacuously pass, which is worse than failing.
if (( ${#PROTECTED[@]} == 0 )); then
    echo "No forward_auth services found in $MATRIX - refusing to pass vacuously."
    exit 1
fi

echo "Protected services should send an anonymous request to the login page:"
for svc in "${PROTECTED[@]}"; do
    read -r c target <<<"$(code_and_target https "${svc}.${DOMAIN}" /)"
    if [[ "$c" != "302" ]]; then
        fail "${svc}.${DOMAIN}" "expected 302, got ${c:-no answer}"
    elif [[ "$target" != "https://auth.${DOMAIN}/"* ]]; then
        # A 302 somewhere else is the app's own login page answering, which
        # means the request reached the app and forward auth is not in front
        # of it.
        fail "${svc}.${DOMAIN}" "302, but to ${target:-nowhere} - not the login page"
    else
        pass "${svc}.${DOMAIN}" "302 -> login"
    fi
done

echo
echo "Services with their own login should still answer plain HTTP (the TV path):"
for svc in "${OPEN[@]}"; do
    c=$(code http "${svc}.${DOMAIN}" /)
    # 2xx or the app's own redirect are both fine - including an `oidc` app
    # bouncing to Authelia to start its own login flow, which is the whole
    # point of that mode, and a 301 from Dashy or Grafana, whose roles upgrade
    # to HTTPS unconditionally because nothing reads them on a television.
    # Only silence is a failure: no answer on port 80 means the TV has no
    # way in.
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
