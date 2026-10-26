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

**It encrypts rather than blocks.** Anything it can fix, it fixes:

| Situation | What happens |
| --- | --- |
| Staged vault file is plaintext | **encrypted and re-staged**, commit continues |
| …and it also has **unstaged** edits | **the index is encrypted in place**; your working file and its edits are left untouched, so the commit holds only what you staged |
| A vault file is decrypted in the working tree, not staged | **encrypted**, commit continues |
| `ansible-vault` or `.vault_pass` missing | **blocked** — nothing can encrypt |
| A plaintext `vault_*: value` in an *ordinary* vars file | **blocked**, value redacted |

That second row is the subtle one. Encrypting the working copy and re-running
`git add` would sweep your unstaged edits into the commit, so instead the
staged blob is encrypted and written straight into the index with
`git update-index`. The file may then show as modified afterwards — correct,
because the unstaged edit really is still uncommitted.

The last row is **not** auto-fixed on purpose: encrypting a general vars file
would hide its non-secret configuration from everyone reading the repo, and
that file is the wrong home for the secret anyway. Move the value into the
vault file — only a human can decide that.

### What counts as a vault file

1. **It is ciphertext in `HEAD`.** The reliable rule: it only ever re-encrypts
   something that was already encrypted, so it cannot misfire.
2. **Its name says so** — `secrets*.yml` / `vault*.yml`, but **only under
   `group_vars/` or `host_vars/`**, which is where Ansible vault variables
   live. This exists to catch a brand-new vault file on its first commit,
   where there is no `HEAD` version to compare against.

Rule 2 is scoped for a reason. An earlier version matched any path ending in
`secrets.yml` and encrypted `roles/*/tasks/secrets.yml` — ordinary task files
named for what they do. Source code is not a secret, and encrypting it makes
it unreadable and undiffable. There is a regression test for exactly that.

`secrets.yml.example` is excluded; it is documentation.

A value that is purely a Jinja reference is fine, so
`inventory/group_vars/all/media.yml` can point at vault variables like
`"{{ vault_vpn_openvpn_password | default('') }}"` without tripping anything.

### Escape hatches

```bash
FREY_VAULT_NO_AUTOENCRYPT=1 git commit ...   # report problems, change nothing
git commit --no-verify                        # skip the hook entirely
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

A hook that rewrites files needs to be tested somewhere it cannot do harm.
Exercise it in a throwaway repo, never against the real `secrets.yml`, and
checksum the real file before and after to prove the tests never touched it:

```bash
sha256sum inventory/group_vars/all/secrets.yml      # before
tmp=$(mktemp -d) && cd "$tmp" && git init -q .
mkdir -p git-hooks && cp /path/to/frey/git-hooks/pre-commit git-hooks/
git config core.hooksPath git-hooks
# commit an encrypted secrets.yml, then decrypt/stage it and commit again
```

Cases worth covering, all of which have caught a real bug here:

- staged plaintext with **and** without unstaged edits;
- that the committed blob excludes the unstaged edit;
- a role task file named `secrets.yml` is left completely alone;
- a brand-new vault file is encrypted on its first commit;
- a secret in an ordinary vars file is reported with the value redacted, and
  the value never appears in the hook's output;
- missing `.vault_pass` blocks rather than silently passing.
