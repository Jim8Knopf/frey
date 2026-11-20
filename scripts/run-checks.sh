#!/usr/bin/env bash
# =============================================================================
# run-checks.sh - every check that does not need the Pi
# =============================================================================
#
# This is the single definition of "the offline half of the test suite".
# .github/workflows/checks.yml installs the dependencies and then runs this
# file, so what CI does and what you can run locally cannot drift apart:
#
#   scripts/run-checks.sh
#
# What it does NOT cover is anything that needs to reach the van. Those are
# the scripts that decide whether a change actually worked, and they live
# separately on purpose:
#
#   scripts/monitoring-check.sh   scripts/identity-check.sh
#   scripts/immich-check.sh       scripts/silverbullet-check.sh
#   scripts/local-ai-check.sh     scripts/check-updates.py   (needs internet)
#
# Exit code is the number of failed sections, so a CI step fails on any one.
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

failed=0
section() {
  printf '\n\033[1m==> %s\033[0m\n' "$1"
}
ok() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad() {
  printf '  \033[31mFAIL\033[0m  %s\n' "$1"
  failed=$((failed + 1))
}

# -----------------------------------------------------------------------------
section "Playbook syntax"
# Globbed, not listed. Naming the playbooks here left
# playbooks/rebind_container_limits.yml - 153 live, documented lines - never
# syntax-checked at all, which is the same mistake the test discovery below
# already had to fix once.
vault_args=()
if [ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ] && [ ! -r .vault_pass ]; then
  # No vault password available (a fresh CI runner, or a worktree, where
  # .vault_pass is gitignored and therefore absent). Parsing the playbooks
  # does not need the real one.
  placeholder="$(mktemp)"
  trap 'rm -f "$placeholder"' EXIT
  printf '%s\n' ci-placeholder > "$placeholder"
  vault_args=(--vault-password-file "$placeholder")
fi
if ! command -v ansible-playbook > /dev/null; then
  bad "ansible-playbook is not installed"
else
  for playbook in playbooks/*.yml; do
    if ansible-playbook "$playbook" --syntax-check "${vault_args[@]}" \
      > /dev/null 2>&1; then
      ok "$playbook"
    else
      bad "$playbook"
      ansible-playbook "$playbook" --syntax-check "${vault_args[@]}" 2>&1 \
        | tail -20
    fi
  done
fi

# -----------------------------------------------------------------------------
section "YAML and JSON"
if python3 scripts/check-repository-files.py; then
  ok "no duplicate mapping keys"
else
  bad "scripts/check-repository-files.py"
fi

# -----------------------------------------------------------------------------
section "Shell scripts"
shell_files=(git-hooks/pre-commit git-hooks/post-commit git-hooks/test-pre-commit.sh)
for file in scripts/*.sh; do
  [ -e "$file" ] && shell_files+=("$file")
done
for file in "${shell_files[@]}"; do
  if bash -n "$file" 2> /dev/null; then
    ok "bash -n $file"
  else
    bad "bash -n $file"
  fi
done
if command -v shellcheck > /dev/null; then
  if shellcheck --severity=warning "${shell_files[@]}"; then
    ok "shellcheck"
  else
    bad "shellcheck"
  fi
else
  printf '  \033[33mskip\033[0m  shellcheck is not installed\n'
fi

# -----------------------------------------------------------------------------
section "Python tests"
# A tests directory holding no Python tests is not a failure, and must be
# skipped rather than discovered: since Python 3.12 `unittest discover` exits
# 5 when it finds nothing, so globbing the directories turned the FIRST such
# directory into a red run. roles/media_library/tests is exactly that - four
# JavaScript tests and no Python.
for dir in tests roles/*/tests; do
  [ -d "$dir" ] || continue
  if compgen -G "$dir/test_*.py" > /dev/null; then
    if python3 -m unittest discover -s "$dir" -p 'test_*.py' > /dev/null 2>&1; then
      ok "$dir"
    else
      bad "$dir"
      python3 -m unittest discover -s "$dir" -p 'test_*.py' 2>&1 | tail -30
    fi
  fi
done

# -----------------------------------------------------------------------------
section "JavaScript tests"
if command -v node > /dev/null; then
  for file in tests/test_*.js roles/*/tests/test_*.js; do
    [ -e "$file" ] || continue
    if node "$file" > /dev/null 2>&1; then
      ok "$file"
    else
      bad "$file"
      node "$file" 2>&1 | tail -20
    fi
  done
else
  printf '  \033[33mskip\033[0m  node is not installed\n'
fi

# -----------------------------------------------------------------------------
section "Offline test scripts"
for script in scripts/test-portal-logic.py scripts/test-media-dns-upstream.py; do
  if python3 "$script" > /dev/null 2>&1; then
    ok "$script"
  else
    bad "$script"
    python3 "$script" 2>&1 | tail -20
  fi
done
if git-hooks/test-pre-commit.sh > /dev/null 2>&1; then
  ok "git-hooks/test-pre-commit.sh"
else
  bad "git-hooks/test-pre-commit.sh"
  printf '        (needs ansible-vault and .vault_pass; absent in a worktree)\n'
fi

# -----------------------------------------------------------------------------
printf '\n'
if (( failed > 0 )); then
  printf '\033[31m%d section(s) failed.\033[0m\n\n' "$failed"
  exit "$failed"
fi
printf '\033[32mAll offline checks passed.\033[0m\n'
printf 'What this cannot do is reach the van - run the check scripts for that.\n\n'
