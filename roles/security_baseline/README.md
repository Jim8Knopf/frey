# security_baseline

Applies the minimum security layer for the modular Frey host:

- UFW default-deny inbound policy.
- DNS, DHCP, HTTP, HTTPS, and SSH allowed on the downstream Frey LAN.
- Routing allowed from downstream LAN to the Wi-Fi uplink.
- Current Ansible SSH path preserved during deployment.
- Fail2ban enabled for SSH.
- Conservative network sysctl hardening.
- SSH rate limits, and a whitelist that exempts this van's own devices from
  every one of them.

The reverse proxy still binds only to `10.20.0.1`, so services are not intentionally exposed on the public Wi-Fi uplink.

## The SSH whitelist

The Pi has no Ethernet port and no console, so SSH is the only way in and a
rate limit that blocks it bricks the van. Two mechanisms have each done that —
`MaxStartups` saturation and OpenSSH 9.8+ `PerSourcePenalties`, both of which
present as "TCP connects, then closes with no banner" while every other
service keeps working.

`frey.trusted_devices` (in `inventory/group_vars/all/main.yml`, shared with
`network_gateway`, which pins each entry to a fixed DHCP address) plus
`security_baseline.trusted` resolve into the list that four separate layers
honour: the sshd `PerSourcePenaltyExemptList`, a `Match Address` block raising
`MaxAuthTries`, the fail2ban `ignoreip`, and a UFW allow rule for port 22 on
any interface.

`tasks/trusted_sources.yml` computes that list and can be included on its own
to inspect or render it without applying the baseline:

```yaml
- ansible.builtin.include_role:
    name: security_baseline
    tasks_from: trusted_sources
```

The sshd task validates the **full** configuration with `sshd -t` after
writing, and on any error restores the previous file and fails *without*
notifying the reload handler, so a bad template can never reach the running
daemon.

Full rationale, recovery steps and verification commands: [`docs/SSH_ACCESS.md`](../../docs/SSH_ACCESS.md).
