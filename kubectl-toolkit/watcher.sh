#!/bin/bash

set -e

IDLE_TIMEOUT="${IDLE_TIMEOUT:-3600}" # 1 hour

echo "Starting container idle watcher. Do nothing $IDLE_TIMEOUT seconds."

while true
do
  sleep 30
  # Note: stat on alpine and ubuntu has different options
  atime=$(stat -c "%X" /dev/pts/ptmx)
  current_time=$(date +"%s")
  time_difference=$(($current_time-$atime))

  if [ $time_difference -gt $IDLE_TIMEOUT ]; then
    echo "idle time is up"
    exit 0
  fi
done