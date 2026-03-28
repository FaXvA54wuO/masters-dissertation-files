#!/bin/ash
set -eu

cat >/tmp/p3_churn.sh <<'EOF'
#!/bin/ash
end=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$end" ]; do
  sleep 5 &
  sleep 1
done
wait
EOF

chmod +x /tmp/p3_churn.sh

/tmp/p3_churn.sh &
echo $! >/tmp/p3_churn_driver.pid

printf 'DRIVER_PID=%s\nEXPECTATION=%s\n' \
  "$(cat /tmp/p3_churn_driver.pid)" \
  "hidden_pids_for_ps_command.txt may be empty or contain transient race candidates" \
  >/tmp/p3_manifest.txt