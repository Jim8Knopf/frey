#!/usr/bin/env bash
# Read-only readiness and isolation checks on Frey; status 2 means downloading.
#
# Checks that the served model is running, that its isolation is still what the
# role intends, and that it answers /health. It does not test sign-in, vision,
# or the quality of an answer.
set -euo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_USER="${PI_USER:-ansible}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_ansible}"
MODEL_KEY="${MODEL_KEY:-qwen35-4b}"

ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
  "$PI_USER@$PI_ADDR" MODEL_KEY="$MODEL_KEY" python3 - <<'PY'
import glob
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

key = os.environ.get('MODEL_KEY', 'qwen35-4b')
model_dir = '/opt/frey/appdata/local-ai/models'
marker = f'{model_dir}/.{key}.complete'
# Compose derives the project name from the stack directory, so the private
# network is named after it.
network_name = 'local-ai_ai_private'
container_name = 'frey-local-ai-model'
unit = f'frey-local-ai-download@{key}.service'


def docker(*args):
    return json.loads(subprocess.check_output(['docker', *args], text=True))[0]


# The marker is written only after every artifact has passed its checksum, so
# its absence means the download is still in progress or has failed.
if not os.path.exists(marker):
    partial = sum(os.path.getsize(p) for p in glob.glob(f'{model_dir}/*.part'))
    done = sum(os.path.getsize(p) for p in glob.glob(f'{model_dir}/*.gguf'))
    status = subprocess.run(['systemctl', 'is-active', unit],
                            capture_output=True, text=True).stdout.strip()
    total = 3585  # weights 2912 MB + vision projector 672 MB
    print(f'WAIT Model {key}: {(done + partial) / 1_000_000:.0f} MB of about '
          f'{total} MB downloaded; service {status}.')
    sys.exit(2)

try:
    container = docker('inspect', container_name)
    network = docker('network', 'inspect', network_name)
    config = container['HostConfig']
    networks = container['NetworkSettings']['Networks']
    mounts = container['Mounts']
    if not container['State']['Running']:
        raise ValueError('Model container is not running')
    if not network['Internal'] or set(networks) != {network_name}:
        raise ValueError('Model is not isolated on its private internal network')
    if len(mounts) != 1 or mounts[0]['Source'] != model_dir or mounts[0]['RW']:
        raise ValueError('Model mounts differ from the approved read-only model directory')
    if config.get('PortBindings') or not config.get('ReadonlyRootfs'):
        raise ValueError('Model has published ports or a writable root filesystem')
    if container['Config']['User'] != '65534:65534' or 'ALL' not in (config.get('CapDrop') or []):
        raise ValueError('Model container privileges differ from the intended configuration')
    if 'no-new-privileges:true' not in (config.get('SecurityOpt') or []):
        raise ValueError('Model container does not have no-new-privileges enabled')
    ip = networks[network_name]['IPAddress']
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open('http://' + ip + ':8080/health', timeout=5) as response:
        if json.load(response).get('status') != 'ok':
            raise ValueError('Model health endpoint is not ready')
    print('OK Model is running on its private internal network with the expected isolation.')
    print('OK Model health endpoint reports ready. Authenticated chat, vision and '
          'answer quality need separate testing.')
except (OSError, KeyError, ValueError, subprocess.CalledProcessError, urllib.error.URLError) as exc:
    print('FAIL Local AI readiness:', str(exc), file=sys.stderr)
    sys.exit(1)
PY
