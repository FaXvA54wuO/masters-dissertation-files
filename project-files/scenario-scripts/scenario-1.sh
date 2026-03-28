#!/bin/ash
set -eu

cat >/tmp/p1_tree.sh <<'EOF'
#!/bin/ash
exec 3>/tmp/p1-open-handle.log
echo "P1 marker" >&3
sleep 900 &
echo $! >/tmp/p1_child.pid
wait
EOF

chmod +x /tmp/p1_tree.sh

/bin/ash /tmp/p1_tree.sh --marker P1_TREE --case alpha &
echo $! >/tmp/p1_parent.pid

while [ ! -s /tmp/p1_child.pid ]; do
  sleep 1
  done

  printf 'PARENT_PID=%s\nCHILD_PID=%s\nMARKER=%s\nOPEN_FILE=%s\n' \
    "$(cat /tmp/p1_parent.pid)" \
      "$(cat /tmp/p1_child.pid)" \
        "P1_TREE" \
          "/tmp/p1-open-handle.log" \
            >/tmp/p1_manifest.txt