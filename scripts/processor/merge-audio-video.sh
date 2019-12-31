#!/bin/bash

if [ -z "$1" ]; then
  echo "missing audio file"
  exit 1
fi

if [ -z "$2" ]; then
  echo "missing video file"
  exit 1
fi

get_duration_in_seconds() {
  if [ -f "$1" ]; then
    DURATION=$(ffmpeg -i "$1" 2>&1 | grep Duration | awk '{print $2}' | sed -e 's/\..*//g' | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')
    echo "$DURATION"
  else
    echo "File doesn't exist: $1"
    exit 1
  fi
}

MUSIC_LENGTH=$(get_duration_in_seconds $1)
VIDEO_LENGTH=$(get_duration_in_seconds $2)
VIDEO_FADE=$((MUSIC_LENGTH - 2))

echo "Music: $MUSIC_LENGTH | Video: $VIDEO_LENGTH"

PERCENTAGE=$((MUSIC_LENGTH * 100000 / VIDEO_LENGTH))

echo "Speed up footage to match audio length."
FAST=$(echo $2 | sed -e 's/.mp4/_fast.mp4/g')
ffmpeg -i $2 -filter:v "setpts=0.$PERCENTAGE*PTS" $FAST

echo "Add audio: $1"
AUDIO=$(echo $FAST | sed -e 's/_fast/_audio/g')
ffmpeg -i $FAST -i $1 -c copy -map 0:v:0 -map 1:a:0 $AUDIO

echo "Adding fade in/out"
FADE=$(echo $AUDIO | sed -e 's/_audio/_fade/g')
ffmpeg -i $AUDIO -filter:v "fade=in:st=0:d=2, fade=out:st=${VIDEO_FADE}:d=2" $FADE
