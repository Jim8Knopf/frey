#!/bin/bash

# ==============================================================================
# Frey WiFi Roaming Pause/Resume Control
#
# Simple script to pause/resume the WiFi roaming daemon using signals.
#
# Usage:
#   frey-wifi-pause pause    # Pause roaming scanning
#   frey-wifi-pause resume   # Resume roaming scanning
#   frey-wifi-pause status   # Show current status
# ==============================================================================

set -euo pipefail

DAEMON_NAME="frey-wifid"
SERVICE_NAME="frey-wifid.service"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  pause    Pause WiFi roaming scanning
  resume   Resume WiFi roaming scanning
  status   Show current daemon status

Examples:
  $(basename "$0") pause    # Stop scanning for better networks
  $(basename "$0") resume   # Resume automatic network switching
  $(basename "$0") status   # Check if daemon is running/paused

Note: This controls the roaming daemon via signals (SIGUSR1/SIGUSR2).
      The daemon will remain running but skip network scans when paused.
EOF
}

# Get the PID of the roaming daemon
get_daemon_pid() {
    # Try systemctl first (most reliable)
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl show "$SERVICE_NAME" --property=MainPID --value
        return 0
    fi

    # Fallback: search by process name
    pgrep -f "frey-wifi-roaming-daemon" | head -n1 || true
}

# Check if daemon is running
is_daemon_running() {
    local pid
    pid=$(get_daemon_pid)
    [ -n "$pid" ] && [ "$pid" != "0" ]
}

# Send signal to daemon
send_signal() {
    local signal="$1"
    local pid

    pid=$(get_daemon_pid)

    if [ -z "$pid" ] || [ "$pid" = "0" ]; then
        echo -e "${RED}ERROR:${NC} Roaming daemon is not running"
        echo "Start it with: sudo systemctl start $SERVICE_NAME"
        return 1
    fi

    if kill -s "$signal" "$pid"; then
        return 0
    else
        echo -e "${RED}ERROR:${NC} Failed to send signal to daemon (PID: $pid)"
        return 1
    fi
}

# Show daemon status
show_status() {
    if ! is_daemon_running; then
        echo -e "${RED}Status:${NC} Daemon is NOT running"
        echo "Start it with: sudo systemctl start $SERVICE_NAME"
        return 1
    fi

    local pid
    pid=$(get_daemon_pid)

    echo -e "${GREEN}Status:${NC} Daemon is running (PID: $pid)"

    # Check recent logs for pause/resume messages
    local recent_logs
    recent_logs=$(journalctl -u "$SERVICE_NAME" -n 20 --no-pager 2>/dev/null | grep -E "(PAUSED|RESUMED)" | tail -n1 || true)

    if echo "$recent_logs" | grep -q "PAUSED"; then
        echo -e "${YELLOW}State:${NC} PAUSED (scanning disabled)"
        echo "Resume with: $(basename "$0") resume"
    elif echo "$recent_logs" | grep -q "RESUMED"; then
        echo -e "${GREEN}State:${NC} ACTIVE (scanning enabled)"
        echo "Pause with: $(basename "$0") pause"
    else
        echo -e "${BLUE}State:${NC} ACTIVE (assumed - no recent pause/resume logs)"
        echo "Pause with: $(basename "$0") pause"
    fi

    echo ""
    echo "Recent activity:"
    journalctl -u "$SERVICE_NAME" -n 5 --no-pager 2>/dev/null | tail -n 5 || echo "  (logs not available)"
}

# Pause scanning
do_pause() {
    echo "Pausing WiFi roaming scanning..."

    if send_signal SIGUSR1; then
        echo -e "${GREEN}✓${NC} Sent pause signal (SIGUSR1)"
        echo ""
        echo "The daemon will skip network scans but remain running."
        echo "Resume with: $(basename "$0") resume"
        return 0
    else
        return 1
    fi
}

# Resume scanning
do_resume() {
    echo "Resuming WiFi roaming scanning..."

    if send_signal SIGUSR2; then
        echo -e "${GREEN}✓${NC} Sent resume signal (SIGUSR2)"
        echo ""
        echo "The daemon will now actively scan for better networks."
        echo "Pause with: $(basename "$0") pause"
        return 0
    else
        return 1
    fi
}

# Main command handler
main() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    case "$1" in
        pause)
            do_pause
            ;;
        resume)
            do_resume
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo -e "${RED}ERROR:${NC} Unknown command: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
