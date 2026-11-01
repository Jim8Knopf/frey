# Dashy

Dashy is the Frey service landing page at https://dashy.hub.frey. It uses
Authelia OIDC and displays service links according to `identity_services`.
Seerr has its own authentication and is shown to media and admin users;
other services with no groups default to admin visibility. Media and monitoring
switches determine which links are generated. Apply `--tags dashy` after
changing services or permissions. The stack-based sections are configured in
`defaults/main.yml`; new services fall under Other services until assigned.
Dashy configuration is Ansible-managed.

Deploy changes with `ansible-playbook playbooks/site.yml --tags proxy,identity,dashy`.
Devices must trust the Frey CA; see `docs/IDENTITY.md`. Verify sign-in and
tile visibility with accounts in the media and admin groups. Wi-Fi controls
are not provided by this module.

New devices can open http://dashy.hub.frey/setup without signing in to download
the public CA and read installation instructions. The setup page is served over
HTTP for bootstrapping; verify the CA fingerprint through a trusted channel as
described in `docs/IDENTITY.md`. The signed-in dashboard also links to it.
