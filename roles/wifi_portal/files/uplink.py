"""Restricted NetworkManager operations for the Frey Wi-Fi portal.

This module deliberately offers no generic nmcli command execution. Callers
must authenticate and authorise users before invoking it.
"""

import subprocess
import uuid


class UplinkError(Exception):
    pass


def run_nmcli(*args):
    try:
        return subprocess.run(
            ["nmcli", "--escape", "no", *args], check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=35,
        ).stdout.strip()
    except (subprocess.SubprocessError, OSError) as exc:
        raise UplinkError("NetworkManager could not complete the request") from exc


def saved_networks(uplink, downstream, run=run_nmcli):
    """Return only infrastructure Wi-Fi profiles explicitly bound to uplink."""
    if not uplink or uplink == downstream:
        raise UplinkError("The uplink and access point must be distinct")
    result = []
    for identifier in run("-g", "UUID", "connection", "show").splitlines():
        try:
            identifier = str(uuid.UUID(identifier))
        except ValueError:
            continue
        def get(key):
            return run("-g", key, "connection", "show", "uuid", identifier)
        try:
            if get("connection.type") not in ("802-11-wireless", "wifi"):
                continue
            if get("connection.interface-name") != uplink:
                continue
            if get("802-11-wireless.mode") not in ("infrastructure", ""):
                continue
            ssid = get("802-11-wireless.ssid")
            if ssid:
                result.append({"uuid": identifier, "ssid": ssid})
        except UplinkError:
            # A profile may disappear while enumerating. Never broaden access.
            continue
    return sorted(result, key=lambda item: (item["ssid"].casefold(), item["uuid"]))


def connect_saved(identifier, uplink, downstream, run=run_nmcli):
    """Activate a currently eligible saved profile, on uplink only."""
    try:
        identifier = str(uuid.UUID(identifier))
    except (ValueError, TypeError, AttributeError) as exc:
        raise UplinkError("Invalid network identifier") from exc
    if identifier not in {p["uuid"] for p in saved_networks(uplink, downstream, run)}:
        raise UplinkError("This network is not a saved uplink profile")
    run("--wait", "30", "connection", "up", "uuid", identifier, "ifname", uplink)
