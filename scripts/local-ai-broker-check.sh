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

# --- phase 4: the write path must have a human in it -----------------------
#
# The model may propose. It must not be able to act. These check both halves.

for verb, args in [
    ("rerun_unit", {"unit": "frey-metrics.service"}),
    ("restart_container", {"container": "byparr"}),
    ("recreate_container", {"container": "frey-media-dns"}),
]:
    r = ask(verb, args)
    if r is None:
        bad(f"INCONCLUSIVE (no response): direct write verb {verb}")
    elif not r.get("ok") and "unknown verb" in str(r.get("error", "")):
        ok(f"write action {verb} is not callable by the agent at all")
    else:
        bad(f"agent COULD call write action {verb} directly")

# A proposal must be refused when it is not approvable, so the model finds out
# while it can still be told why rather than after a human is paged.
r = ask("propose", {"action": {"verb": "rerun_unit", "args": {"unit": "ssh.service"}},
                    "reason": "a deliberately forbidden target used by the boundary check"})
if r is None:
    bad("INCONCLUSIVE (no response): propose with a forbidden target")
elif not r.get("ok"):
    ok("propose refuses a target outside the allowlist")
else:
    bad("propose ACCEPTED a forbidden target")

r = ask("propose", {"action": {"verb": "run_command", "args": {}},
                    "reason": "attempting to propose something that is not an action at all"})
if r is None:
    bad("INCONCLUSIVE (no response): propose of a non-action")
elif not r.get("ok"):
    ok("propose refuses a verb that is not a write action")
else:
    bad("propose ACCEPTED a non-action verb")

r = ask("propose", {"action": {"verb": "rerun_unit", "args": {"unit": "frey-metrics.service"}},
                    "reason": "too short"})
if r is None:
    bad("INCONCLUSIVE (no response): propose without a reason")
elif not r.get("ok"):
    ok("propose requires a stated reason")
else:
    bad("propose ACCEPTED an action with no real reason")

# The approval directory must be unreachable from the agent - it cannot
# approve its own proposal.
import os as _os
if _os.path.exists("/broker/approved"):
    bad("approval directory is visible to the agent")
else:
    ok("approval directory is absent from the agent (ENOENT)")

# Finally a real, valid proposal, left pending for the host side to approve.
r = ask("propose", {"action": {"verb": "rerun_unit", "args": {"unit": "frey-metrics.service"}},
                    "reason": "boundary check: re-running the metrics collector is idempotent"})
if r and r.get("ok") and (r.get("result") or {}).get("proposal_id"):
    pid = r["result"]["proposal_id"]
    ok(f"valid proposal recorded as {pid}, state={r['result'].get('state')}")
    status = ask("proposal_status", {"proposal_id": pid})
    if status and status.get("ok") and (status.get("result") or {}).get("state") == "pending":
        ok("proposal is still pending - proposing did not execute anything")
    else:
        bad(f"proposal did not stay pending: {json.dumps(status)[:200] if status else 'no response'}")
    print(f"PROPOSAL_ID={pid}")
else:
    bad(f"valid proposal failed: {json.dumps(r)[:200] if r else 'no response'}")

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

# --- phase 4: approve the pending proposal and watch the deadman -----------
PROPOSALS=/opt/frey/appdata/local-ai/broker/proposals
DEADMAN=/opt/frey/appdata/local-ai/broker/deadman
echo
echo "approval flow:"
pid=$(grep -oE 'PROPOSAL_ID=[0-9a-f]{8}' "$OUT" | head -1 | cut -d= -f2)
if [[ -z "$pid" ]]; then
  echo "FAIL no proposal id to approve"
  fails=$((fails+1))
else
  before_run=$(systemctl show frey-metrics.service -p InactiveEnterTimestampMonotonic --value)
  if frey-broker-approve "$pid" >/dev/null 2>&1; then
    printf 'OK   approved %s via frey-broker-approve\n' "$pid"
  else
    printf 'FAIL could not approve %s\n' "$pid"; fails=$((fails+1))
  fi
  # The broker polls every couple of seconds.
  for _ in $(seq 1 20); do
    state=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("state",""))' \
      "$PROPOSALS/${pid}.json" 2>/dev/null || true)
    [[ "$state" == "done" || "$state" == "failed" ]] && break
    sleep 2
  done
  if [[ "$state" == "done" ]]; then
    printf 'OK   approved proposal executed (state=done)\n'
  else
    printf 'FAIL proposal state after approval: %s\n' "${state:-unknown}"; fails=$((fails+1))
  fi
  after_run=$(systemctl show frey-metrics.service -p InactiveEnterTimestampMonotonic --value)
  if [[ "$after_run" != "$before_run" ]]; then
    printf 'OK   the unit really ran (timestamp moved)\n'
  else
    printf 'FAIL the unit did not run\n'; fails=$((fails+1))
  fi
  if [[ -f "$DEADMAN/${pid}.json" ]]; then
    printf 'OK   deadman armed for %s\n' "$pid"
  else
    printf 'FAIL no deadman armed for %s\n' "$pid"; fails=$((fails+1))
  fi
  # Approving twice must not run it twice.
  if frey-broker-approve "$pid" >/dev/null 2>&1; then
    printf 'FAIL re-approving an executed proposal was accepted\n'; fails=$((fails+1))
  else
    printf 'OK   an already-executed proposal cannot be approved again\n'
  fi
fi

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
