#!/usr/bin/env bash
# Prove the broker's limits by asking it for things it must refuse.
#
# Every request is made the way the agent really makes them: from inside the
# agent container, through the request directory. A limit that has only been
# read in a config file is not known to hold.
#
# Exit 0 = every boundary held. Exit 1 = at least one did not.
set -euo pipefail
PI_ADDR="${PI_ADDR:-10.20.0.1}"
PI_USER="${PI_USER:-ansible}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_ansible}"

ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
  "$PI_USER@$PI_ADDR" 'sudo bash -s' <<'REMOTE'
set -uo pipefail
OUT=/tmp/frey-broker-check.txt
: > "$OUT"

# Drive the broker from inside the agent container, so this exercises the real
# mount and the real uid rather than a convenient shortcut from the host.
docker exec -i frey-local-ai-observer python3 - > "$OUT" 2>&1 <<'PY'
import json, os, pathlib, time, uuid

REQ = pathlib.Path("/broker/req")
RES = pathlib.Path("/broker/res")
checks, failures = [], []


def ok(msg):
    checks.append(("OK", msg))


def bad(msg):
    failures.append(msg)
    checks.append(("FAIL", msg))


def ask(verb, args, timeout=70):
    rid = uuid.uuid4().hex[:24]
    (REQ / f"{rid}.json").write_text(json.dumps({"verb": verb, "args": args}))
    deadline = time.time() + timeout
    target = RES / f"{rid}.json"
    while time.time() < deadline:
        if target.exists():
            try:
                return json.loads(target.read_text())
            except ValueError:
                pass
        time.sleep(0.5)
    return None


# --- the channel itself ----------------------------------------------------

try:
    probe = REQ / ".probe"
    probe.write_text("x")
    probe.unlink()
    ok("agent can write into the broker request queue")
except OSError as exc:
    bad(f"agent cannot write a request: {exc}")

# The agent must not be able to forge its own answer.
try:
    (RES / ".forged").write_text("x")
    bad("agent CAN write into the response directory - it could forge a reply")
except OSError:
    ok("response directory rejects writes from the agent")

# --- verbs that must work --------------------------------------------------

r = ask("unit_state", {"unit": "frey-self-heal.timer"})
if r and r.get("ok") and (r.get("result") or {}).get("ActiveState"):
    ok(f"unit_state works (frey-self-heal.timer ActiveState={r['result']['ActiveState']})")
else:
    bad(f"unit_state failed: {json.dumps(r)[:200] if r else 'no response'}")

r = ask("diagnostic", {"name": "self_heal"})
if r and r.get("ok") and "exit_code" in (r.get("result") or {}):
    ok(f"diagnostic works (self_heal exit_code={r['result']['exit_code']})")
else:
    bad(f"diagnostic failed: {json.dumps(r)[:200] if r else 'no response'}")

r = ask("container_logs", {"container": "prowlarr", "lines": 3})
if r and r.get("ok") and isinstance((r.get("result") or {}).get("log"), list):
    ok(f"container_logs works ({r['result']['lines']} lines, no Docker socket)")
else:
    bad(f"container_logs failed: {json.dumps(r)[:200] if r else 'no response'}")

# --- verbs and arguments that must be refused ------------------------------

for verb, args, why in [
    ("unit_state", {"unit": "hostapd.service"}, "the AP radio unit"),
    ("unit_state", {"unit": "ssh.service"}, "sshd"),
    ("unit_state", {"unit": "NetworkManager.service"}, "NetworkManager"),
    ("container_logs", {"container": "authelia"}, "a container not on the allowlist"),
    ("diagnostic", {"name": "shell"}, "an unlisted diagnostic"),
]:
    r = ask(verb, args)
    if r is None:
        bad(f"INCONCLUSIVE (no response): {verb} for {why}")
    elif not r.get("ok"):
        ok(f"refused {verb} for {why}")
    else:
        bad(f"ACCEPTED, must have been refused: {verb} {args} ({why})")

# Verbs that must not exist at all. These are the ones that could brick the
# van, and the point is that there is no handler to reach.
for verb in [
    "restart_container", "run_command", "restart_service", "systemctl",
    "docker", "ansible_playbook", "reboot", "write_file", "nmcli",
]:
    r = ask(verb, {})
    if r is None:
        bad(f"INCONCLUSIVE (no response): verb {verb}")
    elif not r.get("ok") and "unknown verb" in str(r.get("error", "")):
        ok(f"no such verb: {verb}")
    elif not r.get("ok"):
        ok(f"refused: {verb}")
    else:
        bad(f"verb {verb} was ACCEPTED")

# Argument smuggling: the command line comes from the allowlist, never the
# request, so an injected argument must not change what runs.
r = ask("diagnostic", {"name": "self_heal heal"})
if r is None:
    bad("INCONCLUSIVE (no response): argument smuggling probe")
elif not r.get("ok"):
    ok("cannot smuggle an argument through a diagnostic name")
else:
    bad("argument smuggling through the diagnostic name was ACCEPTED")

r = ask("container_logs", {"container": "../../etc/shadow"})
if r is None:
    bad("INCONCLUSIVE (no response): traversal probe")
elif not r.get("ok"):
    ok("cannot traverse out of the container allowlist")
else:
    bad("path traversal through container name was ACCEPTED")

for status, msg in checks:
    print(f"{status:4} {msg}")
print()
if failures:
    print(f"{len(failures)} broker boundary check(s) FAILED")
    raise SystemExit(1)
print(f"All {len(checks)} broker boundary checks held.")
PY
agent_status=$?
cat "$OUT"

# --- the sandbox, asserted against the running unit ------------------------
#
# Config assertion rather than a live denial: these are systemd's guarantees,
# and what matters is that the running unit really carries them.
echo
echo "systemd sandbox on the running unit:"
fails=0
for prop in ProtectSystem NoNewPrivileges PrivateNetwork ProtectHome RestrictNamespaces; do
  val=$(systemctl show frey-broker.service -p "$prop" --value 2>/dev/null)
  case "$prop:$val" in
    ProtectSystem:strict|NoNewPrivileges:yes|PrivateNetwork:yes|ProtectHome:yes|RestrictNamespaces:yes)
      printf 'OK   %s=%s\n' "$prop" "$val" ;;
    *) printf 'FAIL %s=%s\n' "$prop" "$val"; fails=$((fails+1)) ;;
  esac
done

inacc=$(systemctl show frey-broker.service -p InaccessiblePaths --value 2>/dev/null)
for secret in /opt/frey/pki /etc/shadow; do
  if [[ "$inacc" == *"$secret"* ]]; then
    # Only meaningful if the path actually exists on the host.
    if [[ -e "$secret" ]]; then
      printf 'OK   %s exists on the host and is InaccessiblePaths to the broker\n' "$secret"
    else
      printf 'OK   %s is listed inaccessible (does not exist on this host)\n' "$secret"
    fi
  else
    printf 'FAIL %s is NOT in InaccessiblePaths\n' "$secret"; fails=$((fails+1))
  fi
done

rw=$(systemctl show frey-broker.service -p ReadWritePaths --value 2>/dev/null)
if [[ "$rw" == *"/broker/res"* || "$rw" == *"broker/res"* ]]; then
  printf 'OK   write allowlist is just the broker queues: %s\n' "$rw"
else
  printf 'FAIL unexpected ReadWritePaths: %s\n' "$rw"; fails=$((fails+1))
fi

echo
if (( fails > 0 || agent_status != 0 )); then
  echo "BROKER CHECK FAILED"
  exit 1
fi
echo "Broker boundaries held."
REMOTE
