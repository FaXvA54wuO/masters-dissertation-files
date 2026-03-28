#!/bin/ash
set -eu

nc -l -p 4444 &
echo $! >/tmp/p5_listener.pid

sleep 1

printf 'LISTENER_PID=%s\nPORT=%s\n' \
  "$(cat /tmp/p5_listener.pid)" \
  "4444" \
  >/tmp/p5_manifest.txt