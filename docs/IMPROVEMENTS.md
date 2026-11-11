# Improvement ideas

- Add backups, including consistent dumps of *arr databases and Jellyfin metadata.
- Automate Jellyfin SSO configuration and Audiobookshelf OIDC when their
  configuration interfaces support reliable automation. Seed Seerr's first run
  once its settings schema is pinned.
- Require HTTPS everywhere when all clients trust the Frey CA; consider
  two-factor authentication for acquisition services.
- Consider a base system module, service scaffolding, per-module check-mode
  tests, and a preflight check for missing radios.
- Consider an Ethernet uplink, a captive-portal URL helper, and a gateway
  verification script.
- Add an MQTT broker when external sensors need one. Consider remote access
  through Tailscale if remote dashboards or a second access path become useful.
- Continue the [campaign assistant plan](CAMPAIGN_ASSISTANT_PLAN.md).
