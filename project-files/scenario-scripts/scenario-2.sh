#!/bin/ash
set -eu

cp /bin/busybox /tmp/busybox

/tmp/busybox sleep 900 &
echo $! >/tmp/p2_deleted.pid

sleep 1

rm -f /tmp/busybox

printf 'PID=%s\nEXPECTED_EXE_PREFIX=%s\n' \
  "$(cat /tmp/p2_deleted.pid)" \
  "/tmp/busybox" \
  >/tmp/p2_manifest.txt