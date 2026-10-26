#!/usr/bin/env python3
"""Emit a qBittorrent WebUI password value for qBittorrent.conf.

qBittorrent stores its WebUI password as

    @ByteArray(<base64 salt>:<base64 PBKDF2-HMAC-SHA512 hash>)

with 100000 iterations and a 64-byte derived key. Seeding that value lets
Ansible log into the WebUI API on the very first run, instead of scraping the
temporary password the container prints to its log once and never again.

The salt is derived from the password rather than drawn at random, on purpose:
a random salt would produce a different file on every single run, so the
config template would never converge and would restart qBittorrent forever.
The tradeoff is acceptable here - this guards a web UI on a private LAN, not
a password database - and the derivation is domain-separated so the salt is
not reusable anywhere else.

The password arrives via the environment, never argv, so it does not show up
in the process list.
"""

import base64
import hashlib
import os
import sys

ITERATIONS = 100_000
DERIVED_KEY_BYTES = 64
SALT_BYTES = 16
SALT_DOMAIN = b"frey-qbittorrent-webui:"


def main() -> int:
    password = os.environ.get("QBT_PASSWORD")
    if not password:
        print("QBT_PASSWORD is not set", file=sys.stderr)
        return 1

    encoded = password.encode("utf-8")
    salt = hashlib.sha256(SALT_DOMAIN + encoded).digest()[:SALT_BYTES]
    derived = hashlib.pbkdf2_hmac("sha512", encoded, salt, ITERATIONS, DERIVED_KEY_BYTES)

    salt_b64 = base64.b64encode(salt).decode("ascii")
    derived_b64 = base64.b64encode(derived).decode("ascii")
    print(f"@ByteArray({salt_b64}:{derived_b64})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
