#!/bin/ash
exec 3>/tmp/p1-open-handle.log
echo "P1 marker" >&3
sleep 900 &
echo $! >/tmp/p1_child.pid
wait
