#!/usr/bin/env python3
"""Parse active YAML and JSON without opening encrypted vault contents."""
import json
from pathlib import Path
import sys

import yaml

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
                yaml.safe_load(raw)
        except (OSError, ValueError, yaml.YAMLError) as exc:
            errors.append(f"{path.relative_to(root)}: {exc}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Active YAML and JSON files parse successfully.")
