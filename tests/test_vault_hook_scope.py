#!/usr/bin/env python3
"""The two git hooks must agree on what a vault file is.

`pre-commit` encrypts what it believes is a vault file, and `post-commit`
warns about what it believes is a decrypted one. Both decide with the same
regex, written out twice because each hook has to work as the only file
copied somewhere - git-hooks/test-pre-commit.sh copies exactly one.

Duplicating it is defensible. Letting the copies disagree is not, and they
did: post-commit carried the broad early version that matched any path ending
in secrets.yml, so it flagged the four ordinary task files named
roles/*/tasks/secrets.yml on every single commit. pre-commit had already
found that bug - its own comment explains that encrypting source code "makes
it unreadable and undiffable for everyone" - and the fix was never copied
across.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Paths that must NEVER be treated as vault files: ordinary Ansible task files
# that happen to be named for what they do.
TASK_FILES = [
    'roles/identity/tasks/secrets.yml',
    'roles/media_acquisition/tasks/secrets.yml',
    'roles/media_library/tasks/secrets.yml',
    'roles/monitoring/tasks/secrets.yml',
]

# Paths that must always be treated as vault files.
VAULT_FILES = [
    'inventory/group_vars/all/secrets.yml',
    'inventory/host_vars/frey/vault.yml',
    'group_vars/all/secrets.yaml',
]

# Documentation, not a secret.
NOT_VAULT = [
    'inventory/group_vars/all/secrets.yml.example',
    'roles/identity/defaults/main.yml',
]


def hook_regex(name):
    """Pull VAULT_NAME_RE out of a hook, so the test reads the real thing."""
    text = (ROOT / 'git-hooks' / name).read_text()
    found = re.findall(r"^VAULT_NAME_RE='([^']+)'", text, re.MULTILINE)
    if len(found) != 1:
        raise AssertionError(
            f'expected exactly one VAULT_NAME_RE in git-hooks/{name}, '
            f'found {len(found)}')
    return found[0]


class VaultHookScopeTest(unittest.TestCase):
    def test_both_hooks_use_the_same_definition(self):
        self.assertEqual(
            hook_regex('pre-commit'), hook_regex('post-commit'),
            'git-hooks/pre-commit and git-hooks/post-commit disagree about '
            'what a vault file is. They are duplicated on purpose but must '
            'stay identical - pre-commit is the canonical one.')

    def test_task_files_named_secrets_are_not_vault_files(self):
        for name in ('pre-commit', 'post-commit'):
            pattern = re.compile(hook_regex(name))
            for path in TASK_FILES:
                with self.subTest(hook=name, path=path):
                    self.assertIsNone(
                        pattern.search(path),
                        f'git-hooks/{name} treats {path} as a vault file. '
                        'It is an ordinary task file; encrypting it would '
                        'make source code unreadable and undiffable.')

    def test_real_vault_files_are_matched(self):
        for name in ('pre-commit', 'post-commit'):
            pattern = re.compile(hook_regex(name))
            for path in VAULT_FILES:
                with self.subTest(hook=name, path=path):
                    self.assertIsNotNone(
                        pattern.search(path),
                        f'git-hooks/{name} would not protect {path}')

    def test_examples_and_ordinary_vars_are_not_matched(self):
        for name in ('pre-commit', 'post-commit'):
            pattern = re.compile(hook_regex(name))
            for path in NOT_VAULT:
                with self.subTest(hook=name, path=path):
                    self.assertIsNone(pattern.search(path))

    def test_the_task_files_this_guards_still_exist(self):
        """If they are renamed, this test is guarding nothing."""
        missing = [p for p in TASK_FILES if not (ROOT / p).is_file()]
        self.assertEqual(
            [], missing,
            'these files moved; update TASK_FILES or drop them: '
            + ', '.join(missing))


if __name__ == '__main__':
    unittest.main()
