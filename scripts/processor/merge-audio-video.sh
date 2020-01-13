#!/bin/bash

source ./functions.sh

if [ -z "$1" ]; then
  echo "missing audio file"
  exit 1
fi

if [ -z "$2" ]; then
  echo "missing video file"
  exit 1
fi
MERGE_START=$(date +%s)

MUSIC_LENGTH=$(get_duration_in_seconds $1)
VIDEO_LENGTH=$(get_duration_in_seconds $2)
VIDEO_FADE=$((MUSIC_LENGTH - 2))
echo "*********************************************************"
echo "Music: $MUSIC_LENGTH | Video: $VIDEO_LENGTH"

PERCENTAGE=$((MUSIC_LENGTH * 100000 / VIDEO_LENGTH))
echo "*********************************************************"
echo "Speed up footage to match audio length."
FAST=$(echo $2 | sed -e 's/.mp4/_fast.mp4/g')
ffmpeg -hide_banner -loglevel panic -i $2 -filter:v "setpts=0.$PERCENTAGE*PTS" $FAST
echo "*********************************************************"
echo "Add audio: $1"
AUDIO=$(echo $FAST | sed -e 's/_fast/_audio/g')
ffmpeg -hide_banner -loglevel panic -i $FAST -i $1 -c copy -map 0:v:0 -map 1:a:0 $AUDIO
echo "*********************************************************"
echo "Adding fade in/out"
FADE=$(echo $AUDIO | sed -e 's/_audio/_fade/g')
ffmpeg -hide_banner -loglevel panic -i $AUDIO -filter:v "fade=in:st=0:d=2, fade=out:st=${VIDEO_FADE}:d=2" $FADE
MERGE_ENDED=$(date +%s)
MERGE_FINISHED=$((MERGE_ENDED-MERGE_START))
MERGE_RUNTIME=$(convertsecs $MERGE_FINISHED)
echo "*********************************************************"
echo "Merge Runtime: $MERGE_RUNTIME"
echo "*********************************************************"
