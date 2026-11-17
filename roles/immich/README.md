# Immich

Immich serves photos at https://immich.hub.frey. Server and machine learning
images are pinned together; Postgres and Valkey follow the upstream compose for
the pinned release. Photos live under `/opt/frey/data/photos`, the database and
model cache under `/opt/frey/appdata/immich`. Back up the database and photo
folder together; see https://docs.immich.app/administration/backup-and-restore/.
The database password is generated once on the host and must be backed up too.
Do not reuse a legacy database without a tested migration and matching password.

Deploy identity first, then Immich and Dashy. The initial local administrator must be created from a trusted device listed in
`frey.trusted_devices` (currently the admin laptop). Sign in with that local account and link it to Frey SSO in User Settings
before signing in with SSO. Immich may otherwise create a separate user when
the local and Frey email addresses differ. Keep the local administrator password
for recovery. Mobile clients
must trust the Frey root CA and use the canonical HTTPS address. Frey SSO
allows `frey_admins` and `immich` group members. Frey administrators become
Immich administrators; members of `immich` receive the standard user role.
The policy is checked at SSO login; removing a group does not revoke existing
Immich sessions or disable a local password. Machine learning downloads its
models on first use and requires internet access at that point. Maps also
require an external tile service.

OAuth is managed in the Immich config file, so Immich disables editing system
settings in its UI. Change settings through the role instead. Run `scripts/immich-check.sh` after deployment to check routing, features and
OAuth discovery. Test the web and mobile OAuth flows, upload and download a photo, and verify smart search and
face processing once models have downloaded. For upgrades consult the Immich
release notes and back up before database migrations.
