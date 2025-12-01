#!/bin/bash
# This script is a simple daemon that runs the captive portal auto-login script
# in a loop.

while true; do
  # Run the main script to check connection and handle portals
  /usr/local/bin/frey-wifi-captive-portal-auto.sh

  # Wait for 10 minutes before the next check.
  # Reduced from 2 minutes to prevent excessive DHCP/network interference.
  # Portal detection still automatic but less aggressive for connection stability.
  sleep 600
done