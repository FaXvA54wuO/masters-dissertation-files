#!/bin/ash
set -eu

GW="$(ip route show default | awk 'NR==1 {print $3}')"
[ -n "$GW" ] || { echo "No default gateway found"; exit 1; }

ping -c 25 "$GW" &
PING_PID=$!

printf 'SCRIPT_PID=%s\nPING_PID=%s\nGATEWAY=%s\n' \
  "$$" \
  "$PING_PID" \
  "$GW" \
  >/tmp/p6_manifest.txt

wait "$PING_PID"