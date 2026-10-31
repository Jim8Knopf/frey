# Identity And Single Sign-On

One directory of people, one login page, and one place to say who may reach
what.

- **`https://auth.hub.frey`** — the login page (Authelia)
- **`https://users.hub.frey`** — the directory, where you add people (LLDAP)
- **`inventory/group_vars/all/identity.yml`** — the only file you normally edit

## First Time: Install The Root Certificate

Do this before anything else. Single sign-on does not work over plain HTTP —
Authelia marks its session cookie `Secure`, so a cookie set over HTTPS is never
sent back over HTTP, and it refuses plain-HTTP redirect URIs for public OIDC
clients outright. So Frey runs its own certificate authority, and your devices
have to be told to trust it once.

The certificate is fetched back beside the playbook on every deploy:

```bash
ls ca/frey-root-ca.crt
```

| Device | How |
| --- | --- |
| Android | Settings → Security → Encryption & credentials → Install a certificate → **CA certificate**. Verify under Trusted credentials → User. |
| iOS / iPadOS | AirDrop or email it, then Settings → General → VPN & Device Management → Install. **Then** Settings → General → About → Certificate Trust Settings and switch it on. iOS needs both steps. |
| macOS | Double-click → add to Keychain → open it → Trust → Always Trust. |
| Windows | Right-click → Install Certificate → Local Machine → Trusted Root Certification Authorities. |
| Linux — Debian/Ubuntu | `sudo cp ca/frey-root-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates` |
| Linux — **Arch/Manjaro** | `sudo cp ca/frey-root-ca.crt /etc/ca-certificates/trust-source/anchors/ && sudo trust extract-compat` |
| Firefox | Has its own store and ignores the system one: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import. |
| Chrome/Chromium on Linux | Also its own store, separate from Firefox's: `certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "Frey Root CA" -i ca/frey-root-ca.crt` |

**The two Linux paths are not interchangeable.** `/usr/local/share/ca-certificates/`
is Debian's; Arch does not read it at all, so a certificate copied there looks
installed, stays ignored, and every service keeps failing with no clue as to
why. Verify rather than assume:

```bash
curl -I https://auth.hub.frey/     # no --cacert. 200 means trusted.
```

A `curl: (60)` means the system store does not have it. Note that this proves
nothing about Firefox or Chrome, which keep their own.

### Remove the old step-ca roots

If the device ever trusted the archived stack, it is still trusting that CA —
step-ca's root was issued for ten years, so it has until 2035. Those keys live
in an undeployed stack nobody is guarding. Find and remove them:

```bash
# Arch/Manjaro
ls /etc/ca-certificates/trust-source/anchors/ | grep -i frey
# Debian/Ubuntu
ls /usr/local/share/ca-certificates/ | grep -i frey
```

Anything whose subject is **not** `O=Frey, CN=Frey Root CA` is stale. The
legacy ones are recognisable by name — step-ca was initialised as `Frey CA`,
giving `CN=Frey CA Root CA`, and an earlier attempt used `O=Frey Hub`. Delete
the file and re-run `trust extract-compat` or `update-ca-certificates`.

Check Firefox separately — it keeps its own store:

```bash
certutil -L -d sql:$HOME/.mozilla/firefox/<profile> | grep -i frey
```

Trust flags matter there. `C,,` or `CT,,` means trusted as a CA; **`,,` means
the certificate is merely present and will not be trusted for TLS** — which
looks identical to "installed" in the Firefox UI's certificate list.

### What about the TV?

It almost certainly cannot install a private certificate, and unlike a browser
it gives you no way to click through. That is why **Jellyfin, Audiobookshelf and
Seerr still answer plain HTTP** — they are not behind forward auth, so nothing
forces them to HTTPS. The television keeps working.

Admin tools are a different matter: everything behind Authelia is HTTPS-only
and its HTTP router redirects, because it has no choice.

Once every device that matters trusts the CA you can force HTTPS everywhere by
setting `service_proxy.traefik.redirect_http_to_https: true`. It is off by
default on purpose.

## The Hostnames Changed (Nothing Broke)

Services are now at **`<name>.hub.frey`**. `<name>.frey` still resolves, still
has a valid certificate, and 308-redirects to the new name, so bookmarks and
habits keep working.

The extra label is not decoration. Authelia's session cookie has to be scoped
to a domain covering every protected service, and Authelia requires that domain
to *"include at least one domain segment i.e. period"*. Browsers agree: under
the Public Suffix List's default rule an unknown TLD is itself a public suffix,
so `frey` is a bare public suffix and `Set-Cookie` for `Domain=frey` is
refused. That made `sonarr.frey` and `auth.frey` siblings with no shareable
parent — forward auth would have logged you in and then redirect-looped
forever. `hub.frey` has a period, is not a public suffix, and covers
everything. "hub" is FreyHub, the name the network already had.

No DNS change was needed: dnsmasq's `address=/frey/` already answers for the
whole subtree at any depth.

## The Three Things You Will Actually Do

### Add a person

Fastest, no deploy: add them at `https://users.hub.frey`.

Or declare them, so a rebuild from scratch reproduces them:

```yaml
# inventory/group_vars/all/identity.yml
identity_users:
  - username: sam
    name: Sam
    email: sam@frey
    groups: [media]
```

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags identity --vault-password-file .vault_pass
```

The run prints their starting password **once**. After that Ansible stops
managing it — they change it in the directory UI and a later deploy leaves it
alone.

Removing someone from this file does **not** delete their account. A typo
should not be able to destroy a directory. Delete them in the UI.

### Protect a service

```yaml
identity_services:
  newthing:
    auth: forward_auth
    groups: [frey_admins]
    hosts: [newthing]
```

Deploy, and Traefik asks Authelia before the request ever reaches it. The
service needs no plugin, no setting, and no awareness that SSO exists.

### Change who may reach what

Edit `groups` on that service. Nothing else.

## The Three Auth Modes

| Mode | What happens | Use it when |
| --- | --- | --- |
| `forward_auth` | Traefik asks Authelia first. The app never sees an unauthenticated request. | Almost always. Works on anything. |
| `oidc` | The app logs in against Authelia itself, learns who you are, can map groups to its own roles. | The app supports OIDC and you want it to know the user. |
| `none` | The app keeps its own login. | It already authenticates against something else. |

Currently: Jellyfin and Audiobookshelf are `oidc`, Seerr is `none` (it
authenticates against Jellyfin, so it inherits that login), and the other
twelve hostnames are `forward_auth`.

## Machines Still Need To Get In

An API client cannot answer a 302 to a login page. That is not hypothetical
here: the wiring in `roles/media_acquisition/tasks/configure/` connects
Prowlarr to Sonarr to qBittorrent by driving their REST APIs **through
Traefik**, at `http://10.20.0.1` with a `Host:` header, because the Pi does not
necessarily resolve its own `*.frey` names and nothing publishes a port. RSS
readers and any other key-holding client are in the same position.

So on the *arr services — and only those — `/api`, `/feed` and `/ping` skip the
session check. They are authenticated by `X-Api-Key` instead: a different
mechanism, not a missing one.

That is why `media_acquisition.auth.required` is pinned to `Enabled` rather
than Servarr's default of `DisabledForLocalAddresses`. The default waives the
API key for requests from private addresses, and *every* request arriving
through Traefik has one — it comes from Traefik's container on a Docker bridge.
Without the pin, the exemption would be an unauthenticated door into the API
for anyone on FreyHub.

The result, verified:

| Request | Result |
| --- | --- |
| `/api/...` with a valid key | `200` |
| `/api/...` with no key | `401` |
| `/` (the UI), even holding a key | `302` to the login page |

`api_bypass` is opt-in per service in `identity_services`. Maintainerr — which
can delete media and has no authentication of its own — deliberately does not
have it.

## What Is Still Manual, And Why

Three things. Everything else is automatic.

**1. The root certificate** — above. Unavoidable; trust has to be established
out of band.

**2. Audiobookshelf OIDC.** It has no API and no environment variable for OIDC
settings; the web UI is the only way. The deploy prints the exact values. Go to
Settings → Authentication, enable OpenID Connect, paste them in, and set
*Match existing users by* → username.

**3. Jellyfin SSO.** Jellyfin has no built-in OIDC, so it needs a community
plugin, and the plugin is **not templated deliberately**. The original
(`9p4/jellyfin-plugin-sso`) was archived in May 2026; the maintained fork is
tested against Jellyfin 12.0–12.2 and this runs **12.3**, so it is outside its
tested range. Its config XML schema is version-specific and undocumented
outside its own source — templating a guessed schema would give you a plugin
that loads, reports itself configured, and silently authenticates nobody. That
is strictly worse than an obvious manual step, and it is the same lesson
`provision_jellyfin` already records in `roles/media_library/defaults/main.yml`.

Authelia's side is fully configured and waiting. Dashboard → Plugins →
Repositories → add the repository, install, restart, then add a provider.

### Then edit the XML — the UI cannot set what matters

Four settings decide whether this works, and the plugin UI exposes none of
them. Each one fails in a way that does not point at itself. Edit:

```
/opt/frey/appdata/jellyfin/data/plugins/configurations/Jellyfin.Plugin.Sso.xml
```

| Field | Must be | Why it bites |
| --- | --- | --- |
| `<Id>` | `authelia` | **The callback path is built from `Id`, not `Name`.** The UI only sets `Name` and auto-generates a random `Id` (e.g. `xmk42t0g3umvq2c4vi`). Authelia then rejects the callback with `invalid_request` / "redirect_uri does not match". |
| `<Scopes>` | `openid`, `profile`, `email`, `groups` as separate `<string>` items | `Scopes` **replaces** the defaults rather than adding to them. Leave it empty and the plugin sends `openid profile email`; set one value and that becomes the *only* scope sent — dropping even the mandatory `openid`. |
| `<GroupsClaim>` | `groups` | This is the *name of the claim* carrying groups, not a list of permitted groups. |
| `<GroupsFromUserInfo>` | `true` | Required. Frey's `jellyfin` client has `claims_policy: ""`, so groups are deliberately not in the ID token and must be fetched from the userinfo endpoint. |

Restart Jellyfin afterwards. **Recreating the provider in the UI regenerates
the `Id` and breaks SSO again** — if SSO stops working after you touched the
plugin screen, check `Id` first.

Library access and admin come from `<GroupMappings>`, which the plugin
re-applies on *every* login, and it ships
`<PreserveAdminPermissions>false</PreserveAdminPermissions>`. So permissions
you edit by hand on Jellyfin's user screen are wiped the next time that person
signs in. Change the mapping, never the user.

**When it fails, read Authelia's log before touching any config** — it names
the exact `redirect_uri` it rejected, which tells you immediately whether the
fault is in Jellyfin or in Authelia:

```bash
docker logs authelia --tail 50
```

**Jellyfin's local accounts keep working throughout.** If the plugin misbehaves
on 12.3, that is your way back in — do not delete the local administrator.

## Verifying

```bash
scripts/identity-check.sh
```

Asserts the four things that break silently: protected services really do
bounce an anonymous request to the login page, unprotected ones really do still
answer plain HTTP, legacy names redirect rather than 404, and the certificate
is neither expiring nor missing a name. Exits non-zero on any failure, so it
works from cron.

A `200` where a `302` is expected is the one to take seriously — it usually
means Traefik dropped a router because it named a middleware that did not
exist, which fails open rather than anywhere you would notice.

By hand:

```bash
# From a device on FreyHub
curl -I https://auth.hub.frey
curl -I https://jellyfin.frey        # 308 -> jellyfin.hub.frey

# OIDC is really up
curl -s https://auth.hub.frey/.well-known/openid-configuration | jq .issuer

# On the Pi
docker ps --filter name=authelia --filter name=lldap
docker logs authelia --tail 50
sudo openssl x509 -in /opt/frey/pki/ca.crt -noout -dates
```

Password-reset and 2FA-enrolment links go to a file rather than email, because
nothing in a van can reach an SMTP relay while parked off-grid:

```bash
sudo cat /opt/frey/appdata/identity/authelia/notification.txt
```

## When It Goes Wrong

**Redirect loop on a protected service.** The session cookie is not coming
back. Check you are on `https://<name>.hub.frey` and not an HTTP or `.frey`
URL, and that the browser trusts the CA.

**"Invalid Credentials" in the Authelia log at startup.** Authelia binds to
LLDAP before serving, and the account it binds with is created by the LLDAP
bootstrap. On a first deploy the role starts LLDAP, seeds it, and only then
starts Authelia. If you see this, LLDAP is unhealthy — look there first.

**Authelia will not start after a version bump.** Its config schema moves
between minor releases. The role runs `authelia validate-config` before
restarting anything, so this should fail the deploy with a precise error rather
than take the login page down. Read that error; it names the option.

**Locked out entirely.** The admin account in LLDAP is independent of Authelia:

```bash
sudo python3 -c "import json;print(json.load(open('/opt/frey/appdata/identity/.identity-keys.json'))['lldap_admin_password'])"
```

Log in at `https://users.hub.frey` as `admin` with that, and fix the account
from there. If Authelia itself is the problem, `docker stop authelia` leaves
every unprotected service — Jellyfin included — working normally.

## Why Not Authentik

The old stack ran Authentik, and the reason it was replaced is maintenance, not
features.

Authentik's only infrastructure-as-code path is blueprints, and blueprints were
what failed. `archive/legacy-stack/roles/infrastructure/tasks/main.yml` runs to
947 lines, much of it machinery to force blueprints to re-apply — including SQL
against Authentik's own Postgres to find and delete rows in the
`blueprintinstance` table — plus five Django ORM scripts under
`authentik-ensure/` for the things blueprints could not express at all.
Jellyfin's LDAP auth never worked; see
`archive/legacy-stack/LDAP_SSO_ISSUES.md`, still open, root cause being that an
Authentik service account cannot do a password bind. Audiobookshelf and Immich
needed manual clicking anyway. Secrets had to be hand-generated before the
first deploy.

Authelia's entire state is one YAML file. There is no API to call, no database
to reconcile, nothing to re-apply: render, validate, restart. LLDAP's users and
groups come from JSON files through its own idempotent bootstrap script. Both
are things `--check --diff` can show you before they happen, which was never
true of the old stack. A second run reports zero changes.

It is also four containers lighter — no Postgres, no Redis, no worker — and up
in seconds rather than ninety. In a van that power-cycles, how long the login
page takes to come back is not a footnote: nothing else is reachable until it
does.
