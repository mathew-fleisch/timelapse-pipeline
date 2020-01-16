#!/bin/bash

source ./functions.sh


IFS='' read -r -d '' banner <<"EOF"
-------------------------------------------------------------
___________.__               .__                              
\__    ___/|__| _____   ____ |  | _____  ______  ______ ____  
  |    |   |  |/     \_/ __ \|  | \__  \ \____ \/  ___// __ \ 
  |    |   |  |  Y Y  \  ___/|  |__/ __ \|  |_> >___ \\  ___/ 
  |____|   |__|__|_|  /\___  >____(____  /   __/____  >\___  >
                    \/     \/          \/|__|       \/     \/ 
Remote/CircleCi Trigger
-------------------------------------------------------------
EOF

IFS='' read -r -d '' help <<"EOF"
Functions to trigger various circleci timelapse jobs

*** - Required parameter
Usage: ./remote-timelapse.sh [arguments]

  *** --circle-token   [str]  - Overwrites environment variable TIMELAPSE_CIRCLE_TOKEN
  *** --org-fork       [str]  - github/circleci org/user to run jobs under
  *** --source-name    [str]  - Name of camera (used as key for grouping)
  *** --source-base    [str]  - s3 bucket+path of the source images
  *** --target-date    [str]  - Date to generate timelapse
  *** --target-base    [str]  - s3 bucket+path of where video will end up
  *** --slack-channel  [str]  - Report completion to this slack channel
  *** --slack-user     [str]  - Report status updates to this slack user id
  --overwrite-existing [bool] - If there is already a processed video, overwrite (default:0)
  --use-existing-audio [sha]  - Audio sha from existing download. 


EOF
EXISTING_AUDIO=""
OVERWRITE_EXISTING=0
while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
  opt="$1";
  shift;
  case "$opt" in
      "--" ) break 2;;
      "--circle-token" )
         TIMELAPSE_CIRCLE_TOKEN="$1"; shift;;
      "--org-fork" )
         ORG_FORK="$1"; shift;;
      "--source-name" )
         SOURCE_NAME="$1"; shift;;
      "--source-base" )
         SOURCE_BASE="$1"; shift;;
      "--target-base" )
         TARGET_BASE="$1"; shift;;
      "--target-date" )
         TARGET_DATE="$1"; shift;;
      "--slack-channel" )
         TRIGGERED_CHANNEL_ID="$1"; shift;;
      "--slack-user" )
         TRIGGERED_USER_ID="$1"; shift;;
      "--overwrite-existing" )
         OVERWRITE_EXISTING="$1"; shift;;
      "--use-existing-audio" )
         EXISTING_AUDIO="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done


# Using exit 0 so bashbot passes the error to the user. exit 1 swallows the error.
if [ -z "$TIMELAPSE_CIRCLE_TOKEN" ]; then
  echo "$banner"
  echo "$help"
  echo "Missing cirlceci token..."
  exit 0
fi
if [ -z "$ORG_FORK" ]; then
  echo "$banner"
  echo "$help"
  echo "Missing organization/fork from circleci/github... ORG_FORK"
  exit 0
fi
if [ -z "$SOURCE_NAME" ]; then
  echo "$banner"
  echo "$help"
  echo "Must specify camera name (used as identifier) SOURCE_NAME"
  exit 0
fi
if [ -z "$SOURCE_BASE" ]; then
  echo "$banner"
  echo "$help"
  echo "Must specify an s3 bucket to pull images from SOURCE_BASE"
  exit 0
fi
if [ -z "$TARGET_BASE" ]; then
  echo "$banner"
  echo "$help"
  echo "Must specify a target s3 bucket where the processed videos will end up TARGET_BASE"
  exit 0
fi
if [ -z "$TARGET_DATE" ]; then
  echo "$banner"
  echo "$help"
  echo "Must specify a target date (Format: YYYY/MM/DD) TARGET_DATE"
  exit 0
fi
if [ -z "$TRIGGERED_CHANNEL_ID" ]; then
  echo "$banner"
  echo "$help"
  echo "Missing slack channel id TRIGGERED_CHANNEL_ID"
  exit 0
fi
if [ -z "$TRIGGERED_USER_ID" ]; then
  echo "$banner"
  echo "$help"
  echo "Missing slack channel id TRIGGERED_USER_ID"
  exit 0
fi


BUCKET_PUBLIC_NAME=$(echo $TARGET_BASE | awk -F\/ '{print $3}')
BUCKET_PUBLIC_PATH=$(echo $TARGET_BASE | sed 's/^.*'$BUCKET_PUBLIC_NAME'\///g')
BUCKET_PUBLIC_URL="https://$BUCKET_PUBLIC_NAME.s3.amazonaws.com/$BUCKET_PUBLIC_PATH"


BUILD_URL="https://circleci.com/api/v1.1/project/github/${ORG_FORK}/timelapse-pipeline/tree/master?circle-token=${TIMELAPSE_CIRCLE_TOKEN}"


T_YEAR=$(date '+%Y' -d "${TARGET_DATE}" )
T_MONTH=$(date '+%m' -d "${TARGET_DATE}" )
T_DAY=$(date '+%d' -d "${TARGET_DATE}" )
if [ -z "$T_YEAR" ]; then
  echo "Invalid Date..."
  exit 0
fi

if ! [ -z "$DEBUG" ]; then
  echo "Check to see if video exists:"
  echo "${TARGET_BASE}/${T_YEAR}_${T_MONTH}_${T_DAY}/${SOURCE_NAME}_${T_YEAR}_${T_MONTH}_${T_DAY}.mp4"
fi
PROCESSED_VIDEO_EXISTS=$(aws s3 ls ${TARGET_BASE}/${T_YEAR}_${T_MONTH}_${T_DAY}/${SOURCE_NAME}_${T_YEAR}_${T_MONTH}_${T_DAY}.mp4)
if ! [ -z "$DEBUG" ]; then
  echo "$PROCESSED_VIDEO_EXISTS"
fi

if [ -z "$PROCESSED_VIDEO_EXISTS" ] || [ $OVERWRITE_EXISTING -eq 1 ]; then
  echo "Video not found for $TARGET_DATE. Let's generate one..."
  json=$(jq -c -r -n '{"build_parameters":{
        "CIRCLE_JOB":"make_timelapse",
        "TARGET_DATE":"'$TARGET_DATE'",
        "TARGET_BASE":"'$TARGET_BASE'",
        "SOURCE_NAME":"'$SOURCE_NAME'",
        "SOURCE_BASE":"'$SOURCE_BASE'",
        "TRIGGERED_CHANNEL_ID":"'$TRIGGERED_CHANNEL_ID'",
        "TRIGGERED_USER_ID":"'$TRIGGERED_USER_ID'",
        "SLACK_TOKEN":"'$SLACK_TOKEN'",
        "EXISTING_AUDIO":"'$EXISTING_AUDIO'"
      }}')
  if ! [ -z "$DEBUG" ]; then
    echo $json | jq '.'
  fi
  response=$(curl -s -X POST --data $json --header "Content-Type:application/json" --url "$BUILD_URL")

  echo "https://circleci.com/gh/${ORG_FORK}/timelapse-pipeline/$(echo $response | jq -r -c '.build_num')"
  # Debug full response
  if ! [ -z "$DEBUG" ]; then
    echo $response | jq '.'
  fi
else
  # Video found in s3 bucket. Display link to video
  echo "${BUCKET_PUBLIC_URL}/${T_YEAR}_${T_MONTH}_${T_DAY}/${SOURCE_NAME}_${T_YEAR}_${T_MONTH}_${T_DAY}.mp4"
fi
