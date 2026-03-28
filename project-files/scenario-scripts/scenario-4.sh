#!/bin/ash
set -eu

echo $$ >/tmp/p4_ssh_shell.pid

sleep 900 &
echo $! >/tmp/p4_ssh_sleep.pid

printf 'USER=%s\nSSH_SHELL_PID=%s\nSSH_SLEEP_PID=%s\nPORT=%s\n' \
  "$(whoami)" \
  "$(cat /tmp/p4_ssh_shell.pid)" \
  "$(cat /tmp/p4_ssh_sleep.pid)" \
  "22" \
  >/tmp/p4_manifest.txt

wait