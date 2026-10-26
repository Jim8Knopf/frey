# Git Hooks

Guards against committing Ansible Vault files as plaintext.

## Install

```bash
git config core.hooksPath git-hooks
chmod +x git-hooks/*
```

A **relative** path on purpose: an absolute one breaks when the repo moves, and
relative resolves correctly from a `git worktree` too.

Hooks are not shared through a clone, so each checkout runs this once. Verify:

```bash
git config core.hooksPath     # -> git-hooks
```

## What `pre-commit` does

The dangerous case is not a new secret file appearing — it is a file that
**used to be ciphertext and is now plaintext**. That happens the ordinary way:
`ansible-vault decrypt` to read something, get distracted, and the next
`git add -A` stages your Wi-Fi passwords in the clear. Git commits it happily,
and once pushed it is in the history for good.

So the hook:

| Situation | What happens |
| --- | --- |
| Staged file is ciphertext in `HEAD` but plaintext now | re-encrypted and re-staged, commit continues |
| …but the file also has **unstaged** edits | **blocked** — encrypting and re-staging would drag those edits into the commit |
| …and `ansible-vault` or `.vault_pass` is missing | **blocked**, with the command to run |
| A staged `.yml` contains a plaintext `vault_*: value` | **blocked**, with the value redacted in the message |
| A vault file is decrypted in the working tree but not staged | **warned**, commit continues |

Files are treated as vault-managed if they are encrypted in `HEAD` — which
catches renames and new locations with no hardcoded list — or if their name is
`secrets.yml` / `vault.yml` / `vault_*.yml`. `secrets.yml.example` is
deliberately excluded; it is documentation.

A value that is purely a Jinja reference is fine, so
`inventory/group_vars/all/media.yml` can point at vault variables like
`"{{ vault_vpn_openvpn_password | default('') }}"` without tripping anything.

To commit anyway, deliberately:

```bash
git commit --no-verify
```

## What `post-commit` does

Says nothing unless a vault file is sitting decrypted, in which case it prints
the command to re-encrypt it.

## Working with the vault

Editing without ever decrypting on disk is the safe habit:

```bash
ansible-vault edit inventory/group_vars/all/secrets.yml --vault-password-file .vault_pass
```

If you did decrypt it:

```bash
ansible-vault encrypt inventory/group_vars/all/secrets.yml --vault-password-file .vault_pass
```

`.vault_pass` is gitignored and must stay `chmod 600`. The encrypted
`secrets.yml` **is** tracked on purpose — committing the ciphertext is what
lets a rebuild from scratch reproduce the FreyHub passphrase and known
networks.

## Testing a change to these hooks

Exercise them in a throwaway repo, never against the real `secrets.yml`:

```bash
tmp=$(mktemp -d) && cd "$tmp" && git init -q .
mkdir -p git-hooks && cp /path/to/frey/git-hooks/pre-commit git-hooks/
git config core.hooksPath git-hooks
# then stage a deliberately-plaintext secrets.yml and try to commit
```
