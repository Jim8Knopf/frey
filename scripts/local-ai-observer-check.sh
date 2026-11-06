#!/usr/bin/env bash
# Prove the observer's hard limits by trying to break them.
#
# Per CLAUDE.md, "the container is up" is not evidence the thing works. A limit
# that has never been attempted is not known to hold, so every check here is an
# attempt that must fail. Forbidden paths must report ENOENT rather than
# EACCES: that is the difference between "not mounted" and "mounted but
# permission denied", and only the former is a real boundary.
#
# Exit 0 = every boundary held. Exit 1 = at least one did not.
set -euo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_USER="${PI_USER:-ansible}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_ansible}"

# Results are written to a file on the Pi and then read back, because output
# piped straight out of `docker exec` truncates at around 4 KB, intermittently,
# and looks exactly like a broken service when it does.
ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
  "$PI_USER@$PI_ADDR" 'sudo python3 - > /tmp/frey-observer-check.txt 2>&1; cat /tmp/frey-observer-check.txt' <<'PY'
import json
import subprocess
import sys

CONTAINER = 'frey-local-ai-observer'
failures = []
checks = []


def ok(msg):
    checks.append(('OK', msg))


def fail(msg):
    failures.append(msg)
    checks.append(('FAIL', msg))


def docker_json(*args):
    out = subprocess.check_output(['docker', *args], text=True)
    return json.loads(out)[0]


def in_container(code):
    """Run a short Python snippet inside the observer and return its stdout."""
    return subprocess.run(
        ['docker', 'exec', CONTAINER, 'python3', '-c', code],
        capture_output=True, text=True, timeout=30,
    ).stdout.strip()


try:
    c = docker_json('inspect', CONTAINER)
except Exception as exc:
    print('FAIL cannot inspect observer:', exc)
    sys.exit(1)

cfg = c['HostConfig']
nets = c['NetworkSettings']['Networks']

# --- Container configuration -----------------------------------------------

if c['State']['Running']:
    ok('observer is running')
else:
    fail('observer is not running')

if c['Config']['User'] == '10002:10002':
    ok('runs as its own uid 10002, not SilverBullet s 10001')
else:
    fail(f"unexpected user {c['Config']['User']}")

if cfg.get('ReadonlyRootfs'):
    ok('root filesystem is read-only')
else:
    fail('root filesystem is writable')

if 'ALL' in (cfg.get('CapDrop') or []):
    ok('all capabilities dropped')
else:
    fail('capabilities are not fully dropped')

if 'no-new-privileges:true' in (cfg.get('SecurityOpt') or []):
    ok('no-new-privileges is set')
else:
    fail('no-new-privileges is not set')

if not cfg.get('PortBindings'):
    ok('no published ports')
else:
    fail('observer publishes ports')

# --- Networks must all be internal -----------------------------------------

expected_nets = {'ai_private', 'ai_observe'}
# Compose prefixes networks it defines itself with the project name, while an
# external network keeps its own name.
normalised = set()
for name in nets:
    normalised.add('ai_private' if name.endswith('ai_private') else name)
if normalised == expected_nets:
    ok(f'attached to exactly {sorted(expected_nets)}')
else:
    fail(f'unexpected networks: {sorted(nets)}')

for name in nets:
    try:
        net = docker_json('network', 'inspect', name)
    except Exception:
        fail(f'cannot inspect network {name}')
        continue
    if net.get('Internal'):
        ok(f'network {name} is internal')
    else:
        fail(f'network {name} is NOT internal - observer has egress')

# --- Mounts: exactly one writable, nothing forbidden -----------------------

writable = [m['Destination'] for m in c['Mounts'] if m.get('RW')]
if writable == ['/drafts']:
    ok('exactly one read-write mount: /drafts')
else:
    fail(f'unexpected writable mounts: {writable}')

readonly = sorted(m['Destination'] for m in c['Mounts'] if not m.get('RW'))
if readonly:
    ok(f'read-only mounts: {readonly}')

sources = ' '.join(m['Source'] for m in c['Mounts'])
for forbidden in ('docker.sock', '/opt/frey/pki', '/opt/frey/stacks', 'photo', 'immich'):
    if forbidden in sources:
        fail(f'forbidden path is mounted: {forbidden}')
    else:
        ok(f'not mounted: {forbidden}')

# --- Attempt to reach what must be unreachable -----------------------------

probe = (
    "import os,socket,errno\n"
    "res=[]\n"
    "for p in ['/var/run/docker.sock','/opt/frey/pki','/opt/frey/stacks',"
    "'/host','/notes/../pki']:\n"
    "    try:\n"
    "        os.stat(p); res.append('EXISTS '+p)\n"
    "    except FileNotFoundError: res.append('ENOENT '+p)\n"
    "    except PermissionError: res.append('EACCES '+p)\n"
    "    except OSError as e: res.append('ERR%d %s'%(e.errno,p))\n"
    "try:\n"
    "    s=socket.create_connection(('1.1.1.1',443),timeout=4); s.close()\n"
    "    res.append('EGRESS open')\n"
    "except Exception: res.append('EGRESS blocked')\n"
    "try:\n"
    "    open('/notes/.probe','w'); res.append('NOTES writable')\n"
    "except OSError: res.append('NOTES readonly')\n"
    "try:\n"
    "    n=sum(1 for _ in os.scandir('/notes')); res.append('NOTES readable %d'%n)\n"
    "except OSError as e: res.append('NOTES unreadable %s'%e.errno)\n"
    "try:\n"
    "    open('/drafts/.probe','w').write('x'); os.unlink('/drafts/.probe')\n"
    "    res.append('DRAFTS writable')\n"
    "except OSError: res.append('DRAFTS unwritable')\n"
    "print('|'.join(res))"
)

out = in_container(probe)
if not out:
    fail('could not run the in-container probe')
else:
    for item in out.split('|'):
        if item.startswith('ENOENT'):
            ok(f'absent, not merely denied: {item.split()[1]}')
        elif item.startswith(('EXISTS', 'EACCES', 'ERR')):
            fail(f'reachable or present: {item}')
        elif item == 'EGRESS blocked':
            ok('no internet egress from the observer')
        elif item == 'EGRESS open':
            fail('observer HAS internet egress')
        elif item == 'NOTES readonly':
            ok('notes mount rejects writes')
        elif item == 'NOTES writable':
            fail('notes mount is writable')
        elif item.startswith('NOTES readable'):
            ok(f'notes are readable via ACL ({item.split()[-1]} entries)')
        elif item.startswith('NOTES unreadable'):
            fail(f'notes unreadable - ACL grant did not work ({item})')
        elif item == 'DRAFTS writable':
            ok('drafts directory is writable')
        else:
            fail(f'unexpected probe result: {item}')

for status, msg in checks:
    print(f'{status:4} {msg}')
print()
if failures:
    print(f'{len(failures)} boundary check(s) FAILED')
    sys.exit(1)
print(f'All {len(checks)} boundary checks held.')
PY
