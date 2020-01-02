#!/bin/bash

get_duration_in_seconds() {
  if [ -f "$1" ]; then
    DURATION=$(ffmpeg -i "$1" 2>&1 | grep Duration | awk '{print $2}' | sed -e 's/\..*//g' | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
    echo "$DURATION"
  else
    echo "File doesn't exist: $1"
    exit 1
  fi
}

convertsecs() {
  ((h=${1}/3600))
  ((m=(${1}%3600)/60))
  ((s=${1}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}