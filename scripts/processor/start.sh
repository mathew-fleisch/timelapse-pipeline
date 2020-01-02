#!/bin/bash

source ./functions.sh

IFS='' read -r -d '' help <<"EOF"
-------------------------------------------------------------
___________.__               .__                              
\__    ___/|__| _____   ____ |  | _____  ______  ______ ____  
  |    |   |  |/     \_/ __ \|  | \__  \ \____ \/  ___// __ \ 
  |    |   |  |  Y Y  \  ___/|  |__/ __ \|  |_> >___ \\  ___/ 
  |____|   |__|__|_|  /\___  >____(____  /   __/____  >\___  >
                    \/     \/          \/|__|       \/     \/ 

-------------------------------------------------------------
Orchestrates scripts to run in sequence, to pull down images,
generate two timelapse videos, download a random mp3 audio file,
speed video to match audio duration, and finally merge them
together, for each camera in the specified long-term storage
solution.

*** - Required parameter
Usage: ./start.sh [arguments]

    *** --name        [str]  - Name of camera/timelapse
    *** --target-date [date] - Date of timelapse
    *** --target-dir  [path] - A directory where images and
                               videos can be stored
    *** --source-base [path] - An s3 bucket, containing timelapse
                               images. 
    *** --target-base [path] - An s3 bucket, to store processed
                               images, audio files and their meta-data
    --overwrite-audio [bool] - default(1) behavior is to pick a new
                               random audio file, if one exists. Set
                               to 0 to use existing audio file.
EOF
OVERWRITE_AUDIO=1
while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
  opt="$1";
  shift;
  case "$opt" in
      "--" ) break 2;;
      "--name" )
         NAME="$1"; shift;;
      "--target-date" )
         TARGET_DATE="$1"
         T_YEAR=$(date '+%Y' -d "${TARGET_DATE}" )
         T_MONTH=$(date '+%m' -d "${TARGET_DATE}" )
         T_DAY=$(date '+%d' -d "${TARGET_DATE}" )
         shift;;
      "--target-dir" )
         TARGET_DIR="$1"; shift;;
      "--target-base" )
         TARGET_BASE="$1"; shift;;
      "--source-base" )
         SOURCE_BASE="$1"; shift;;
      "--overwrite-audio" )
         OVERWRITE_AUDIO="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done

if [ -z "$NAME" ]; then
  echo "Must include a camera name"
  exit 1
fi
if [ -z "$TARGET_DATE" ] || [ -z "$T_YEAR" ] || [ -z "$T_MONTH" ] || [ -z "$T_DAY" ]; then
  echo "Must include a target date"
  exit 1
fi
if [ -z "$TARGET_DIR" ]; then
  echo "Must include a directory with write access"
  exit 1
fi
# source-base is not necessary if the raw video already exists
# if [ -z "$SOURCE_BASE" ]; then
#   echo "Must include an s3 bucket+path to pull images from"
#   exit 1
# fi
if [ -z "$TARGET_BASE" ]; then
  echo "Must include an s3 bucket+path to push images to"
  exit 1
fi

NOW=$(date +%s)
# Check to see if there is a processed timelapse
# video already in the target-base s3 bucket. If
# it exists, download it, otherwise download the
# images, and build the timelapse using ffmpeg.
PROCESS_LOG_EXISTS=$(aws s3 ls ${TARGET_BASE}/${T_YEAR}_${T_MONTH}_${T_DAY}/data.json)
if [ -z "$PROCESS_LOG_EXISTS" ]; then
  if [ -z "$SOURCE_BASE" ]; then
    echo "A source s3 bucket+path is required to run this section"
    exit 1
  fi

  # Download images into target directory
  aws s3 cp ${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY} $TARGET_DIR --recursive

  # Pick arbitrary threshold of minimum frames
  # to create a timelapse. avg ~ 60k frames
  ./timelapse.sh --target-date $TARGET_DATE --stage-dir $TARGET_DIR --name $CAMERA_NAME

  INITIAL_FILENAME="${TARGET_DIR}/output/${CAMERA_NAME}_${T_YEAR}_${T_MONTH}_${T_DAY}.mp4"
  DURATION=$(get_duration_in_seconds $INITIAL_FILENAME)
  TARGET_FILENAME="${T_YEAR}_${T_MONTH}_${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_raw.mp4"
  aws s3 cp $INITIAL_FILENAME ${TARGET_BASE}/${TARGET_FILENAME}

  # Save json file
  echo "{\"filename\":\"${TARGET_FILENAME}\",\"created\":${NOW},\"duration\":${DURATION}}" > ${TARGET_DIR}/data.json
  aws s3 cp ${TARGET_DIR}/data.json ${TARGET_BASE}/${T_YEAR}_${T_MONTH}_${T_DAY}/data.json
else
  # There is a data.json file, download the processed video

fi


# Get audio method (script, file)
#
# [by script] Get acceptable audio file
# ./get-music.sh --genre "Hip-Hop" --page 0 | jq -r '.'
# cycle through array, curl each mp3 url until there is
# a duration longer than 150 seconds
# Use get_duration_in_se  conds function from functions.sh
# to get duration in secconds 
# 
# [by file] 


# Merge audio/video
# ./merge-audio-video.sh [/path/to/local/file.mp3] [/path/to/local/timelapse.mp4]

# Upload to s3

# Save information to a repo [date, camera(s), initial frames, song details, final duration, processed at]

# Upload to youtube (could be separate step... perhaps... with testcafe... wtf)