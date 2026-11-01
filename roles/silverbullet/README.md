# SilverBullet

SilverBullet provides a private, linked Markdown knowledge base at
`https://silverbullet.hub.frey`. Dashy shows it to Frey administrators and
members of the separate `notes` group. Its
server image is pinned in `inventory/group_vars/all/images.yml`; persistent
data lives under `/opt/frey/appdata/silverbullet` on the Pi.

Access is restricted to `frey_admins` and `notes` through Authelia over HTTPS. An Authelia
OIDC client is also registered so SilverBullet can use Frey accounts for its
own sign-in and per-space permissions. SilverBullet requires a local recovery
administrator and a one-time provider setup in its UI; keep that recovery
account private. Do not expose a GM space to players without
testing the application's permissions. Services on Docker's shared proxy
network can reach each other directly: forward auth protects the Traefik route,
not traffic from other containers. Only trusted services belong on that network.

SilverBullet requires its static `/service_worker.js` and `/.client/` paths,
both at the root and under the configured space prefix (`/notes` by default),
to bypass the authentication proxy for its offline app. The protected route still
handles space content, APIs and setup. Desktop sync through an external auth
proxy is not supported upstream; test the Android browser PWA separately.

## First use and Android

Trust the Frey CA on the client, join FreyHub, open the URL, sign in to Frey,
and finish SilverBullet's setup with a local recovery administrator and a
private space. Then configure native SSO:

1. In SilverBullet's Dashboard, set the primary server URL to
   `https://silverbullet.hub.frey` under **Admin → Server**.
2. In **Admin → Authentication**, open **Set up SSO** and select OpenID Connect. Use issuer
   `https://auth.hub.frey`, client ID `silverbullet`, and the client secret
   printed by the identity deployment. Check that the callback shown by the
   app is `https://silverbullet.hub.frey/.auth/central/oidc/callback`. If a
   provider draft is already present, its saved client secret can stay blank.
3. Save the provider draft, run its sign-in test with the existing Frey
   account, and enable it only after the test succeeds. SilverBullet requires
   a verified email from Authelia. If the test fails, keep the recovery
   administrator and diagnose the failure before enabling SSO.
4. Enable automatic group synchronization as described below. SilverBullet
   itself does not map Frey groups to accounts or roles.

If the client secret was not retained, an administrator can display it on the
Pi without exposing the other identity secrets:

```sh
sudo python3 -c 'import json; print(json.load(open("/opt/frey/appdata/identity/.identity-keys.json"))["silverbullet_oidc_secret"])'
```

The client secret is sensitive: do not paste it into chat or commit it. The
OIDC setup is not complete until the provider test and SSO login succeed.

## Directory group synchronization

The Frey sync reads `notes` and `frey_admins` from LLDAP, and uses the
SilverBullet admin API to manage SSO accounts. Frey administrators become
SilverBullet administrators; `notes` members get read/write access to the
space named `Notes`. Only this space is shared automatically. Removal from
both groups disables the managed account; a change is normally picked up within
two minutes. The service leaves unrelated accounts, including the local recovery
administrator, untouched. SilverBullet writers can execute scripts within
spaces; grant the `notes` group only to trusted editors.

The service uses the existing local `note_admin` account; it does not create a
second local administrator. The dashboard rejects bearer tokens when a primary
URL is set, so the sync uses the standard local sign-in flow. Add the existing
`note_admin` password to the encrypted `inventory/group_vars/all/secrets.yml`
as `vault_silverbullet_sync_password` using `ansible-vault edit`. Never put it
in chat, an unencrypted file or a command line. The role installs the password
in `/opt/frey/appdata/silverbullet-sync/admin-password` as a root-only file,
and does not reset the SilverBullet account's password. Changing that password
in SilverBullet requires updating the Vault value and redeploying. The account
can administer all SilverBullet accounts and spaces; keep the vault and host
protected. Until the password is supplied, the role leaves the timer inactive.
Deploy the `silverbullet` tag after setting it to enable the timer. Inspect
`systemctl status frey-silverbullet-sync.timer` and the sync service journal,
and test group addition, removal and both roles before relying on it.

The synchronizer refuses to adopt accounts it did not create or silently
change an enrolled identity's email. If a reserved `frey_<username>` account
already exists or a directory email changes, resolve the conflict explicitly
instead of removing its safety checks. It needs a healthy directory and active
OIDC provider; it makes no permission changes when those checks fail. Back up
its `managed-users.json` together with the SilverBullet data.

On Android use the browser's **Install app**
or **Add to home screen** option. Wait for the space to sync before going
offline; verify that it opens and an edit syncs back when reconnected. An
offline copy of the space is stored on the phone: protect the device and only
sync material appropriate for it. Offline access depends on the browser retaining
its site data; it is not a backup.

Create a few test pages such as `Dwarf`, `Borin` and `Saltport`; link them with
`[[Dwarf]]` and inspect linked mentions and the experimental Object Graph. Do
not put actual player information in a test space without consent.

## Deployment and checks

On first deploy include PKI, identity, monitoring and Dashy so the hostname is
in the certificate, access policy, probes and dashboard:

```sh
ansible-playbook playbooks/site.yml --tags pki,identity,silverbullet,dashy,monitoring --check --diff > /tmp/silverbullet-check.log 2>&1
ansible-playbook playbooks/site.yml --tags pki,identity,silverbullet,dashy,monitoring
```

Repeat the deploy and confirm zero changes. Verify an unauthenticated request to
the main page and a space API cannot access content, the two documented static
paths load, and authenticated editing and Android offline sync work. Check
container memory and existing gateway/monitoring behavior under use.
Run `bash scripts/silverbullet-check.sh` for the anonymous routing checks.

## Backups

The data directory includes server configuration, spaces and user data. A
backup of the complete data directory is required, in addition to any exported
Markdown. Stop the container before copying for a consistent snapshot, store
the copy encrypted on a separate device, and restart it promptly. Test restore
to an isolated location before relying on it. Offline phone copies are not
backups. Frey does not yet provide an automated backup module, and no backup is
created by this role.
