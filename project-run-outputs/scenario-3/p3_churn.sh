#!/bin/ash
end=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$end" ]; do
  sleep 5 &
  sleep 1
done
wait
