#!/usr/bin/env bash
# Read-only readiness and isolation checks on Frey; status 2 means downloading.
set -euo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_USER="${PI_USER:-ansible}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_ansible}"

ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
  "$PI_USER@$PI_ADDR" python3 - <<'PY'
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

model_dir = '/opt/frey/appdata/campaign-ai/models'
model_file = model_dir + '/Qwen3-1.7B-Q4_K_M.gguf'
part = model_file + '.part'

def docker(*args):
    return json.loads(subprocess.check_output(['docker', *args], text=True))[0]

if not os.path.isfile(model_file):
    size = os.path.getsize(part) if os.path.exists(part) else 0
    status = subprocess.run(['systemctl', 'is-active', 'frey-campaign-ai-download.service'],
                            capture_output=True, text=True).stdout.strip()
    print(f'WAIT Model download: {size / 1_000_000:.0f} MB of approximately 1282 MB; service {status}.')
    sys.exit(2)

try:
    container = docker('inspect', 'frey-campaign-ai-model')
    network = docker('network', 'inspect', 'campaign-ai_ai_private')
    config = container['HostConfig']
    networks = container['NetworkSettings']['Networks']
    mounts = container['Mounts']
    if not container['State']['Running']:
        raise ValueError('Model container is not running')
    if not network['Internal'] or set(networks) != {'campaign-ai_ai_private'}:
        raise ValueError('Model is not isolated on its private internal network')
    if len(mounts) != 1 or mounts[0]['Source'] != model_dir or mounts[0]['RW']:
        raise ValueError('Model mounts differ from the approved read-only model directory')
    if config.get('PortBindings') or not config.get('ReadonlyRootfs'):
        raise ValueError('Model has published ports or a writable root filesystem')
    if container['Config']['User'] != '65534:65534' or 'ALL' not in (config.get('CapDrop') or []):
        raise ValueError('Model container privileges differ from the intended configuration')
    if 'no-new-privileges:true' not in (config.get('SecurityOpt') or []):
        raise ValueError('Model container does not have no-new-privileges enabled')
    ip = networks['campaign-ai_ai_private']['IPAddress']
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open('http://' + ip + ':8080/health', timeout=5) as response:
        if json.load(response).get('status') != 'ok':
            raise ValueError('Model health endpoint is not ready')
    print('OK Model is running on its private internal network with the expected isolation.')
    print('OK Model health endpoint reports ready. Authenticated chat and answers need separate testing.')
except (OSError, KeyError, ValueError, subprocess.CalledProcessError, urllib.error.URLError) as exc:
    print('FAIL Assistant readiness:', str(exc), file=sys.stderr)
    sys.exit(1)
PY
