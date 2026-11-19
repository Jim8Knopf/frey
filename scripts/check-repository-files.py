#!/usr/bin/env python3
"""Parse active YAML and JSON without opening encrypted vault contents.

Duplicate mapping keys are treated as errors, not warnings. YAML keeps the
LAST of two keys with the same name, so a second definition silently discards
the first, and nothing downstream complains: `yaml.safe_load` accepts it
without a murmur and Ansible at most mutters "Found duplicate mapping key"
somewhere in a log nobody reads. This has cost this repository real time
twice -- once when a second `auth:` block in media_acquisition's defaults
threw away the one with the reasoning in it, and once when a new
`download_cleaner:` was added to a mapping that already had one further down,
which failed a deploy with an undefined sub-key and no hint as to why.
"""
import json
from pathlib import Path
import sys

import yaml


class DuplicateKeyError(yaml.YAMLError):
    """A mapping defines the same key twice."""


class StrictLoader(yaml.SafeLoader):
    """SafeLoader that refuses duplicate keys instead of silently overwriting."""


def _no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise DuplicateKeyError(
                f"duplicate mapping key {key!r} at line "
                f"{key_node.start_mark.line + 1} - YAML keeps the last one, "
                f"so the earlier definition is silently discarded"
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


StrictLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates
)

root = Path(__file__).resolve().parents[1]
errors = []
for name in ("roles", "playbooks", "inventory", ".github"):
    for path in (root / name).rglob("*"):
        if not path.is_file() or path.suffix not in (".yml", ".yaml", ".json"):
            continue
        try:
            raw = path.read_bytes()
            if raw.startswith(b"$ANSIBLE_VAULT;"):
                continue
            if path.suffix == ".json":
                json.loads(raw)
            else:
                # Not safe_load: that accepts duplicate keys.
                yaml.load(raw, Loader=StrictLoader)
        except (OSError, ValueError, yaml.YAMLError) as exc:
            errors.append(f"{path.relative_to(root)}: {exc}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Active YAML and JSON files parse successfully, with no duplicate keys.")
