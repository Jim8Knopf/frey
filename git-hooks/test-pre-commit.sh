#!/usr/bin/env bash
#
# Test the vault pre-commit hook in a throwaway repository.
#
#   ./git-hooks/test-pre-commit.sh
#
# A hook that rewrites files has to be tested somewhere it cannot do harm, so
# everything happens in a temporary repo with its own vault password. The real
# secrets.yml is checksummed before and after to prove it was never touched.
#
# Every case here has caught a real bug in this hook at some point.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO_ROOT}/git-hooks/pre-commit"
REAL_SECRETS="${REPO_ROOT}/inventory/group_vars/all/secrets.yml"

command -v ansible-vault >/dev/null 2>&1 || { echo "ansible-vault required"; exit 1; }

before=""
[ -f "$REAL_SECRETS" ] && before="$(sha256sum "$REAL_SECRETS" | cut -d' ' -f1)"

T="$(mktemp -d)"
export ANSIBLE_LOCAL_TEMP="${T}/ansible-tmp"
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1

git init -q .
git config user.email test@example.invalid
git config user.name "hook test"
git config commit.gpgsign false
mkdir -p inventory/group_vars/all git-hooks
cp "$HOOK" git-hooks/pre-commit
chmod +x git-hooks/pre-commit
git config core.hooksPath git-hooks
printf 'testpassword\n' > .vault_pass
chmod 600 .vault_pass
printf '.vault_pass\n' > .gitignore

S=inventory/group_vars/all/secrets.yml
VP="--vault-password-file .vault_pass"
pass=0; failed=0

res()  { if [ "$2" = "$3" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1 (expected rc=$2, got $3)"; failed=$((failed+1)); fi; }
yes_() { if [ "$2" = yes ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; failed=$((failed+1)); fi; }
cipher_head() { git show "HEAD:$1" 2>/dev/null | head -c 20 | grep -qF '$ANSIBLE_VAULT' && echo yes || echo no; }
cipher_wt()   { head -c 20 "$1" 2>/dev/null | grep -qF '$ANSIBLE_VAULT' && echo yes || echo no; }

printf 'vault_ap_password: "hunter2"\n' > "$S"
ansible-vault encrypt "$S" $VP >/dev/null 2>&1
git add -A >/dev/null; git commit -qm baseline --no-verify

# 1 ── staged plaintext, no unstaged edits
ansible-vault decrypt "$S" $VP >/dev/null 2>&1
git add "$S"
git commit -qm "plaintext staged" >log1 2>&1; res "staged plaintext auto-encrypts" 0 $?
yes_ "  committed blob is ciphertext" "$(cipher_head "$S")"
yes_ "  working tree is ciphertext"   "$(cipher_wt "$S")"

# 2 ── staged plaintext WITH further unstaged edits
ansible-vault decrypt "$S" $VP >/dev/null 2>&1
printf 'vault_ap_password: "staged-value"\n' > "$S"
git add "$S"
printf 'vault_extra: "unstaged-edit"\n' >> "$S"
git commit -qm "staged + unstaged" >log2 2>&1; res "unstaged-edits case commits" 0 $?
yes_ "  committed blob is ciphertext" "$(cipher_head "$S")"
git show "HEAD:$S" > blob2 2>/dev/null
dec="$(ansible-vault view blob2 $VP 2>/dev/null)"
case "$dec" in *staged-value*) yes_ "  commit has the staged value" yes ;; *) yes_ "  commit has the staged value" no ;; esac
case "$dec" in *unstaged-edit*) yes_ "  commit excludes the unstaged edit" no ;; *) yes_ "  commit excludes the unstaged edit" yes ;; esac
wt="$(ansible-vault view "$S" $VP 2>/dev/null || cat "$S")"
case "$wt" in *unstaged-edit*) yes_ "  working tree keeps the unstaged edit" yes ;; *) yes_ "  working tree keeps the unstaged edit" no ;; esac

# 3 ── decrypted in the working tree, nothing staged
ansible-vault decrypt "$S" $VP >/dev/null 2>&1
echo "# note" > README.md; git add README.md
git commit -qm "unrelated" >log3 2>&1; res "unrelated commit succeeds" 0 $?
yes_ "  decrypted working file was encrypted" "$(cipher_wt "$S")"

# 4 ── a secret in an ordinary vars file: blocked, value redacted
printf 'some_setting: true\nvault_openvpn_password: "actual-secret-here"\n' \
  > inventory/group_vars/all/plain.yml
git add inventory/group_vars/all/plain.yml
git commit -qm "secret in normal file" >log4 2>&1; res "secret in an ordinary vars file blocks" 1 $?
grep -q redacted log4 && yes_ "  redacts the value" yes || yes_ "  redacts the value" no
grep -q actual-secret-here log4 && yes_ "  never prints the secret" no || yes_ "  never prints the secret" yes
git reset -q; rm -f inventory/group_vars/all/plain.yml

# 5 ── Jinja-only references are not secrets
printf 'vault_openvpn_password: "{{ vault_openvpn_password | default(%s) }}"\n' "''" \
  > inventory/group_vars/all/media.yml
git add inventory/group_vars/all/media.yml
git commit -qm "jinja refs" >log5 2>&1; res "Jinja-only vault refs allowed" 0 $?

# 6 ── opt-out reports instead of fixing
ansible-vault decrypt "$S" $VP >/dev/null 2>&1
git add "$S"
FREY_VAULT_NO_AUTOENCRYPT=1 git commit -qm "opt out" >log6 2>&1; res "opt-out blocks instead of encrypting" 1 $?
yes_ "  left the file decrypted" "$([ "$(cipher_wt "$S")" = no ] && echo yes || echo no)"

# 7 ── nothing to encrypt with
ansible-vault encrypt "$S" $VP >/dev/null 2>&1; git add "$S"; git commit -qm reenc --no-verify -q
ansible-vault decrypt "$S" $VP >/dev/null 2>&1; git add "$S"
mv .vault_pass .hidden_pass
git commit -qm "no password file" >log7 2>&1; res "missing .vault_pass blocks" 1 $?
grep -q "not found" log7 && yes_ "  explains why" yes || yes_ "  explains why" no
mv .hidden_pass .vault_pass

# 8 ── REGRESSION: a role task file named secrets.yml is source, not a secret
mkdir -p roles/demo/tasks
printf -- '---\n- name: Resolve secrets\n  ansible.builtin.debug:\n    msg: ordinary task code\n' \
  > roles/demo/tasks/secrets.yml
cp roles/demo/tasks/secrets.yml orig8
git add roles/demo/tasks/secrets.yml
git commit -qm "role task file" >log8 2>&1; res "role task file commits fine" 0 $?
yes_ "  left as plaintext source" "$([ "$(cipher_wt roles/demo/tasks/secrets.yml)" = no ] && echo yes || echo no)"
cmp -s roles/demo/tasks/secrets.yml orig8 && yes_ "  byte-identical" yes || yes_ "  byte-identical" no
yes_ "  committed as plaintext" "$([ "$(cipher_head roles/demo/tasks/secrets.yml)" = no ] && echo yes || echo no)"

# 9 ── a brand-new vault file, with no HEAD version to compare against
mkdir -p inventory/group_vars/media
printf 'vault_new_secret: "brand-new"\n' > inventory/group_vars/media/secrets.yml
git add inventory/group_vars/media/secrets.yml
git commit -qm "new vault file" >log9 2>&1; res "brand-new vault file commits" 0 $?
yes_ "  encrypted on its first commit" "$(cipher_head inventory/group_vars/media/secrets.yml)"

echo
after=""
[ -f "$REAL_SECRETS" ] && after="$(sha256sum "$REAL_SECRETS" | cut -d' ' -f1)"
if [ "$before" = "$after" ]; then
  echo "PASS  real secrets.yml untouched by these tests"
  pass=$((pass+1))
else
  echo "FAIL  real secrets.yml CHANGED during testing"
  failed=$((failed+1))
fi

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
