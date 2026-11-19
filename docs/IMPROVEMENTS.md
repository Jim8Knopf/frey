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
- The read-only observer was retired on 2026-11-19
  ([LOCAL_AI_RIGHTSIZING.md](LOCAL_AI_RIGHTSIZING.md)): it was the only caller
  of the model, wrote 302 reports nobody read, and evicted the prompt cache so
  every human turn was a cold one. Its designed replacement — a gated
  escalation hung off the relay, which Alertmanager already webhooks, asking
  the model once and only when `frey-self-heal` has no recipe or its repair did
  not hold — is deliberately **unbuilt**:
  [LOCAL_AI_AGENT_PLAN.md §7a](LOCAL_AI_AGENT_PLAN.md). It re-creates an
  autonomous consumer of the single model slot, so build it when something
  concrete asks for it rather than on principle.
