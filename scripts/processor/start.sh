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

-------------------------------------------------------------
EOF

IFS='' read -r -d '' help <<"EOF"
Orchestrates scripts to run in sequence, to pull down images,
generate two timelapse videos, download a random mp3 audio file,
speed video to match audio duration, and finally merge them
together, for each camera in the specified long-term storage
solution.

*** - Required parameter
Usage: ./start.sh [arguments]

*** --name              [str] - Name of camera/timelapse
*** --target-date      [date] - Date of timelapse
*** --target-dir       [path] - A directory where images and
                                videos can be stored
*** --source-base      [path] - An s3 bucket, containing timelapse
                                images. 
*** --target-base      [path] - An s3 bucket, to store processed
                                images, audio files and their meta-data
*** --sqlite-db    [filename] - An sqlite db filename found relateive
                                to target-base s3 bucket
--existing-audio        [SHA] - default behavior is to pick a new
                                random audio file.
--genre                 [str] - Blues,Classical,Folk,Hip-Hop,Instrumental,
                                International,Jazz,Lo-fi,Old-Time__Historic,
                                Pop,Rock,Soul-RB (default: Hip-Hop)
--slack-channel  [channel-id] - Optional channel id to report completed timelapse/url
--slack-user        [user-id] - Optional user id to report status updates
--slack-token         [token] --- Required token if --slack-channel is set 

EOF


MIN_IMAGES_THRESHOLD=5000
SHORT_SONG_THRESHOLD=150
LONG_SONG_THRESHOLD=420
DEFAULT_START=0
DEFAULT_END=23
GENRE="Lo-fi"
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
      "--sqlite-db" )
         SQLITE_DB="$1"; shift;;
      "--source-base" )
         SOURCE_BASE="$1"; shift;;
      "--existing-audio" )
         EXISTING_AUDIO="$1"; shift;;
      "--remove-night" )
         DEFAULT_START=4
         DEFAULT_END=21; shift;;
      "--genre" )
         GENRE="$1"; shift;;
      "--slack-channel" )
         SLACK_CHANNEL_ID="$1"; shift;;
      "--slack-user" )
         SLACK_USER_ID="$1"; shift;;
      "--slack-token" )
         SLACK_TOKEN="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done

if [ -z "$NAME" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include a camera name"
  exit 1
fi
if [ -z "$TARGET_DATE" ] || [ -z "$T_YEAR" ] || [ -z "$T_MONTH" ] || [ -z "$T_DAY" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include a target date"
  exit 1
fi
if [ -z "$TARGET_DIR" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include a directory with write access"
  exit 1
fi
if [ -z "$TARGET_BASE" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include an s3 bucket+path to push images to"
  exit 1
fi
if [ -z "$SQLITE_DB" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include a sqlite db filename to store/retrieve meta-data about audio/video"
  exit 1
fi

BUCKET_PUBLIC_NAME=$(echo $TARGET_BASE | awk -F\/ '{print $3}')
BUCKET_PUBLIC_PATH=$(echo $TARGET_BASE | sed 's/^.*'$BUCKET_PUBLIC_NAME'\///g')
BUCKET_PUBLIC_URL="https://$BUCKET_PUBLIC_NAME.s3.amazonaws.com/$BUCKET_PUBLIC_PATH"

NOW=$(date +%s)
KEY="${NAME}_${T_YEAR}_${T_MONTH}_${T_DAY}"
FILENAME="${KEY}.mp4"
LOCAL_FILENAME="${TARGET_DIR}/output/${FILENAME}"
TARGET_FILENAME="videos/raw/${T_YEAR}_${T_MONTH}_${T_DAY}/${FILENAME}"
PROCESSED_FILENAME=$(echo $TARGET_FILENAME | sed -e 's/raw/processed/g')
AUDIO_REJECTED_FILENAME="audio/rejected.txt"

##########################################################################
echo "$banner"
echo "Started:   $NOW"
echo "Filename:  $FILENAME"
echo "Source:    $SOURCE_BASE"
echo "Target:    $TARGET_BASE"
echo "Sqlite:    $SQLITE_DB"
if [ -z "$EXISTING_AUDIO" ]; then
  echo "Genre:     $GENRE"
else
  echo "Existing Audio: $EXISTING_AUDIO.mp3"
fi
if ! [ -z "$SLACK_CHANNEL_ID" ]; then
  echo "Channel:   $SLACK_CHANNEL_ID"
fi
if ! [ -z "$SLACK_USER_ID" ]; then
  echo "User:      $SLACK_USER_ID"
fi
##########################################################################


# Check to see if video already has been processed
PROCESSED_VIDEO_EXISTS=$(aws s3 ls ${TARGET_BASE}/${PROCESSED_FILENAME})
if ! [ -z "$PROCESSED_VIDEO_EXISTS" ]; then
  # Delete video from database
  echo "Video already processed. Audio must suck. try again. Backup video. delete audio from db. add sha to rejected list. delete processed video from db"
  
  # Copy processed video locally
  mkdir -p ${TARGET_DIR}/tmp
  aws s3 cp ${TARGET_BASE}/${PROCESSED_FILENAME} ${TARGET_DIR}/tmp/${FILENAME}

  # Get meta-data about existing file
  
fi



SQLITE_EXISTS=$(aws s3 ls ${TARGET_BASE}/${SQLITE_DB})
if [ -z "$SQLITE_EXISTS" ]; then
  echo "DB does NOT exist. Initialize it."
  initialize_sqlite_db ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db
fi
# key=NAME_YYYY_MM_DD
RAW_VIDEO_EXISTS=$(get_raw_video ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db ${KEY})

# Check to see if there is a processed timelapse
# video already in the target-base s3 bucket. If
# it exists, download it, otherwise download the
# images, and build the timelapse using ffmpeg.
if [ -z "$RAW_VIDEO_EXISTS" ]; then
  ##########################################################################
  echo "-------------------------------------------------------------"
  echo "Video does not exist, Pull images down from s3, and generate it"
  echo "-------------------------------------------------------------"
  ##########################################################################
  if [ -z "$SOURCE_BASE" ]; then
    echo "A source s3 bucket+path is required to run this section"
    exit 1
  fi
  if ! [ -z "$SLACK_CHANNEL_ID" ]; then
    if ! [ -z "$SLACK_TOKEN" ]; then
      if ! [ -z "$SLACK_USER_ID" ]; then
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message_ephemeral $SLACK_TOKEN $SLACK_CHANNEL_ID $SLACK_USER_ID "\`\`\`${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Pulling images down from s3\`\`\`"
      fi
    fi
  fi
  echo "Checking to see if source images exist..."
  TOTAL_IMAGES_FOR_DAY=0
  for (( x="$DEFAULT_START"; x<="$DEFAULT_END"; x++ )); do
    if [[ "${x}" -lt 10 ]]; then
      CURRENT_HOUR="0$x"
    else
      CURRENT_HOUR=$x
    fi
      NUM_IMAGES=$(aws s3 ls ${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_${CURRENT_HOUR}/ | wc -l)
      if [ $NUM_IMAGES -eq 0 ]; then
      echo "There are no images in this source bucket+path:"
      tmp=$(urlencode "${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_${CURRENT_HOUR}")
      echo "$tmp"
    fi
    echo "$CURRENT_HOUR:00 - $NUM_IMAGES"
    TOTAL_IMAGES_FOR_DAY=$((TOTAL_IMAGES_FOR_DAY + NUM_IMAGES))
  done
  if [ $TOTAL_IMAGES_FOR_DAY -lt $MIN_IMAGES_THRESHOLD ]; then
    echo "Error: Staged Images under threshold ($MIN_IMAGES_THRESHOLD)"

    if ! [ -z "$SLACK_CHANNEL_ID" ]; then
      if [ -z "$SLACK_TOKEN" ]; then
        echo "Slack Token is required to run this action."
      else
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message $SLACK_TOKEN $SLACK_CHANNEL_ID "\`\`\`[ERROR]${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Staged Images under threshold ($MIN_IMAGES_THRESHOLD)\`\`\`"
      fi
    fi

    exit 1
  fi
  rm -rf ${TARGET_DIR}/stage
  mkdir -p ${TARGET_DIR}/stage

  # for x in {"$DEFAULT_START".."$DEFAULT_END"}
  for (( x="$DEFAULT_START"; x<="$DEFAULT_END"; x++ ))
  do
    if [[ "${x}" -lt 10 ]]; then
      CURRENT_HOUR="0$x"
    else
      CURRENT_HOUR=$x
    fi
    echo "Getting images for the hour: $CURRENT_HOUR:00"
    aws s3 cp ${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_${CURRENT_HOUR} ${TARGET_DIR}/stage/. --recursive --quiet
  done

  NUM_STAGED=$(num_files ${TARGET_DIR}/stage)
  ##########################################################################
  echo "-------------------------------------------------------------"
  echo "Render Images to Video: $NUM_STAGED (This process will take a while)"
  echo "-------------------------------------------------------------"
  ##########################################################################
  if [ $NUM_STAGED -lt $MIN_IMAGES_THRESHOLD ]; then
    echo "Error: Staged Images under threshold ($MIN_IMAGES_THRESHOLD)"

    if ! [ -z "$SLACK_CHANNEL_ID" ]; then
      if [ -z "$SLACK_TOKEN" ]; then
        echo "Slack Token is required to run this action."
      else
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message $SLACK_TOKEN $SLACK_CHANNEL_ID "\`\`\`[ERROR]${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Staged Images under threshold ($MIN_IMAGES_THRESHOLD)\`\`\`"
      fi
    fi

    exit 1
  fi

  if ! [ -z "$SLACK_CHANNEL_ID" ]; then
    if ! [ -z "$SLACK_TOKEN" ]; then
      if ! [ -z "$SLACK_USER_ID" ]; then
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message_ephemeral $SLACK_TOKEN $SLACK_CHANNEL_ID $SLACK_USER_ID "\`\`\`${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Starting ffmpeg\`\`\`"
      fi
    fi
  fi
  # Pick arbitrary threshold of minimum frames
  # to create a timelapse. avg ~ 60k frames
  ./timelapse.sh --target-date $TARGET_DATE --stage-dir $TARGET_DIR --remove-flashes 1 --name $NAME

  if ! [ -f "$LOCAL_FILENAME" ]; then
    echo "mp4 failed to generate..."

    if ! [ -z "$SLACK_CHANNEL_ID" ]; then
      if [ -z "$SLACK_TOKEN" ]; then
        echo "Slack Token is required to run this action."
      else
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message $SLACK_TOKEN $SLACK_CHANNEL_ID "\`\`\`[ERROR]${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: mp4 failed to generate\`\`\`"
      fi
    fi

    exit 1
  fi
  DURATION=$(get_duration_in_seconds $LOCAL_FILENAME)
  aws s3 cp $LOCAL_FILENAME ${TARGET_BASE}/${TARGET_FILENAME}
  
  # Save raw video meta-data
  put_raw_video ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db "$KEY" "$TARGET_FILENAME" $NOW $DURATION
else
  # There is a video file described in the raw table, download the processed video
  ##########################################################################
  echo "-------------------------------------------------------------"
  echo "Video already exists in s3. Pull generated video from s3"
  echo "-------------------------------------------------------------"
  ##########################################################################
  rm -rf ${TARGET_DIR}/output
  mkdir -p ${TARGET_DIR}/output
  aws s3 cp ${TARGET_BASE}/${TARGET_FILENAME} ${TARGET_DIR}/output/.
fi


if ! [ -f "${TARGET_DIR}/output/${FILENAME}" ]; then
  echo "Error: mp4 failed to generate/download"

  if ! [ -z "$SLACK_CHANNEL_ID" ]; then
    if [ -z "$SLACK_TOKEN" ]; then
      echo "Slack Token is required to run this action."
    else
      PROGRESS_CHECK=$(date +%s)
      PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
      PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
      slack_message $SLACK_TOKEN $SLACK_CHANNEL_ID "\`\`\`[ERROR]${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: mp4 failed to generate or download existing\`\`\`"
    fi
  fi

  exit 1
fi

# Either the mp4 was downloaded, or generated. Add Audio
if [ -z "$EXISTING_AUDIO" ]; then
  ##########################################################################
  echo "-------------------------------------------------------------"

  if ! [ -z "$SLACK_CHANNEL_ID" ]; then
    if ! [ -z "$SLACK_TOKEN" ]; then
      if ! [ -z "$SLACK_USER_ID" ]; then
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message_ephemeral $SLACK_TOKEN $SLACK_CHANNEL_ID $SLACK_USER_ID "\`\`\`${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Get music\`\`\`"
      fi
    fi
  fi
  echo "Get random mp3 from FreeMediaArchive.org"
  FOUND_MUSIC=0
  mkdir -p ${TARGET_DIR}/music
  touch ${TARGET_DIR}/music/new-rejects.txt
  REJECTED=$(aws s3 cp ${TARGET_BASE}/${AUDIO_REJECTED_FILENAME} ${TARGET_DIR}/music/rejected.txt)
  while [ $FOUND_MUSIC -eq 0 ]; do
    echo "**************************************************************"

    MUSIC=$(./get-music.sh --genre $GENRE)
    mkdir -p ${TARGET_DIR}/music

    # Get list of the used shas (don't keep local copy of db)
    get_audio_keys $TARGET_BASE/timelapse.db ${TARGET_DIR}/music/timelapse.db > ${TARGET_DIR}/music/previously_used_shas.txt
    rm -rf ${TARGET_DIR}/music/timelapse.db

    echo "Parse Response: ./get-music.sh --genre $GENRE"
    # There are 20 mp3s per page exported as json. Iterate through each one,
    # check to see if already rejected, or already used, then check duration to
    # see if greater than minimum threshold and less than maximum threshold.
    for row in $(echo "${MUSIC}" | jq -r '.[] | @base64'); do
      echo "-------------------------------------------------------------"
      _jq() {
       echo ${row} | base64 --decode | jq -r ${1}
      }
      THIS_ARTIST=$(_jq '.artist')
      THIS_ALBUM=$(_jq '.artist')
      THIS_GENRE=$(_jq '.genre')
      THIS_MPTHREE=$(_jq '.mpthree')
      SONG_SHA=$(echo $THIS_MPTHREE | shasum | awk '{print $1}')
      ALREADY_REJECTED=$(cat ${TARGET_DIR}/music/rejected.txt | grep ${SONG_SHA})
      PREVIOUSLY_USED=$(cat ${TARGET_DIR}/music/previously_used_shas.txt | grep ${SONG_SHA})
      if [ -z "$ALREADY_REJECTED" ] && [ -z "$PREVIOUSLY_USED" ]; then
        echo "Artist: $THIS_ARTIST"
        echo "MP3:    $THIS_MPTHREE"
        echo "SHA:    ${SONG_SHA}.mp3"
        echo "Backup: ${BUCKET_PUBLIC_URL}/audio/${SONG_SHA}.mp3" 
        curl -s $THIS_MPTHREE --output ${TARGET_DIR}/music/${SONG_SHA}.mp3
        THIS_DURATION=$(get_duration_in_seconds ${TARGET_DIR}/music/${SONG_SHA}.mp3)
        echo "Duration: $THIS_DURATION ?> $SHORT_SONG_THRESHOLD"
        if [ $THIS_DURATION -gt $SHORT_SONG_THRESHOLD ] && [ $THIS_DURATION -lt $LONG_SONG_THRESHOLD ]; then
          echo " *********> This song should do! <********* "
          let FOUND_MUSIC++
          put_audio ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db "$SONG_SHA" "$THIS_ARTIST" "$THIS_ALBUM" "$THIS_GENRE" "$THIS_MPTHREE" $THIS_DURATION
          aws s3 cp ${TARGET_DIR}/music/${SONG_SHA}.mp3 ${TARGET_BASE}/audio/${SONG_SHA}.mp3
          break
        else
          echo "Duration Rejected [${THIS_DURATION}]: $SONG_SHA"
          echo "$SONG_SHA" >> ${TARGET_DIR}/music/new-rejects.txt
        fi
      else
        echo "Rejected:"
        echo "$THIS_MPTHREE"
        if ! [ -z "$ALREADY_REJECTED" ]; then
          echo "Already rejected."
        fi
        if ! [ -z "$PREVIOUSLY_USED" ]; then
          echo "This track has already been used."
        fi
      fi
    done
  done

  echo "Add new rejected mp3 files to list in s3"
  # Add new rejected mp3 shas to the full list of rejects
  cat ${TARGET_DIR}/music/new-rejects.txt >> ${TARGET_DIR}/music/rejected.txt

  # Push the new rejected mp3 shas to s3
  aws s3 cp ${TARGET_DIR}/music/rejected.txt ${TARGET_BASE}/${AUDIO_REJECTED_FILENAME}
else
  ##########################################################################
  echo "-------------------------------------------------------------"
  echo "Use existing mp3: $EXISTING_AUDIO"
  echo "-------------------------------------------------------------"
  ##########################################################################
  SONG_SHA="$EXISTING_AUDIO"
  aws s3 cp ${TARGET_BASE}/audio/${SONG_SHA}.mp3 ${TARGET_DIR}/music/${SONG_SHA}.mp3
fi


  if ! [ -z "$SLACK_CHANNEL_ID" ]; then
    if ! [ -z "$SLACK_TOKEN" ]; then
      if ! [ -z "$SLACK_USER_ID" ]; then
        PROGRESS_CHECK=$(date +%s)
        PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
        PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
        slack_message_ephemeral $SLACK_TOKEN $SLACK_CHANNEL_ID $SLACK_USER_ID "\`\`\`${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Merging with timelapse\n${BUCKET_PUBLIC_URL}/audio/${SONG_SHA}.mp3\n${BUCKET_PUBLIC_URL}/${TARGET_FILENAME}\`\`\`"
      fi
  fi
fi
##########################################################################
echo "-------------------------------------------------------------"
echo "Merge Audio & Video (This process will take a while)"
echo "-------------------------------------------------------------"
##########################################################################


# Merge audio/video
./merge-audio-video.sh ${TARGET_DIR}/music/${SONG_SHA}.mp3 ${TARGET_DIR}/output/${FILENAME}


if ! [ -z "$SLACK_CHANNEL_ID" ]; then
  if ! [ -z "$SLACK_TOKEN" ]; then
    if ! [ -z "$SLACK_USER_ID" ]; then
      PROGRESS_CHECK=$(date +%s)
      PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
      PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
      slack_message_ephemeral $SLACK_TOKEN $SLACK_CHANNEL_ID $SLACK_USER_ID "\`\`\`${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Audio/Video merged. Add fade in/out\`\`\`"
    fi
fi

NEW_DURATION=$(get_duration_in_seconds ${TARGET_DIR}/output/${KEY}_fade.mp4)
##########################################################################
echo "-------------------------------------------------------------"
echo "Upload processed video to s3: $(convertsecs $NEW_DURATION)"
echo "-------------------------------------------------------------"
##########################################################################

if ! [ -z "$SLACK_CHANNEL_ID" ]; then
  if ! [ -z "$SLACK_TOKEN" ]; then
    if ! [ -z "$SLACK_USER_ID" ]; then
      PROGRESS_CHECK=$(date +%s)
      PROG_CHECK_SEC=$((PROGRESS_CHECK-NOW))
      PROG_CHECK_RTM=$(convertsecs $PROG_CHECK_SEC)
      slack_message_ephemeral $SLACK_TOKEN $SLACK_CHANNEL_ID $SLACK_USER_ID "\`\`\`${T_YEAR}/${T_MONTH}/${T_DAY}-log[${PROG_CHECK_RTM}]: Save final video to s3 and meta-data in database\`\`\`"
    fi
fi

# Upload to s3
aws s3 cp ${TARGET_DIR}/output/${KEY}_fade.mp4 ${TARGET_BASE}/${PROCESSED_FILENAME}


##########################################################################
echo "-------------------------------------------------------------"
echo "Save meta-data to sqlite and upload db to s3"
echo "-------------------------------------------------------------"
##########################################################################

# Save meta-data about processed video (key, name, filename, year, month, day, audio, created, duration)
put_video ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db "$KEY" "$NAME" "$PROCESSED_FILENAME" $T_YEAR $T_MONTH $T_DAY "$SONG_SHA" $NOW $NEW_DURATION

# Upload to youtube (could be separate step... perhaps... with testcafe... wtf)




ENDED=$(date +%s)
FINISHED=$((ENDED-NOW))
runtime=$(convertsecs $FINISHED)
##########################################################################
echo "-------------------------------------------------------------"
echo "Processing Complete!!!"
echo "Timelapse Processing Time: $runtime"
echo "Video: ${BUCKET_PUBLIC_URL}/${PROCESSED_FILENAME}" 
echo "-------------------------------------------------------------"
##########################################################################


if ! [ -z "$SLACK_CHANNEL_ID" ]; then
  if [ -z "$SLACK_TOKEN" ]; then
    echo "Slack Token is required to run this action."
    exit 0
  else
    ARTIST_NAME=$(echo $THIS_ARTIST | s -e 's/^.*">//g' | sed -e 's/<\/a>.*$//g')
    ARTIST_LINK=$(echo $THIS_ARTIST | s -e 's/.*a href="(.*)">.*/\1/g')
    TMP_ARTIST=$(echo $THIS_ARTIST | sed -e 's/"/\\\"/g')
    MSG_RUNTIME="Timelapse Complete:\n${runtime}\n"
    MSG_DATE="Date/Camera:\n${T_YEAR}/${T_MONTH}/${T_DAY} - ${NAME}\n"
    MSG_PROCURL="Processed Url:\n${BUCKET_PUBLIC_URL}/${PROCESSED_FILENAME}\n"
    MSG_ARTIST="Artist:\n${ARTIST_NAME} - ${ARTIST_LINK}\n"
    MSG_MP3="mp3:\n${THIS_MPTHREE}\n"
    MSG_CACHED_MP3="Cached mp3:\n${BUCKET_PUBLIC_URL}/audio/${SONG_SHA}.mp3"
    slack_message $SLACK_TOKEN $SLACK_CHANNEL_ID "\`\`\`${MSG_DATE}\n${MSG_RUNTIME}\n${MSG_PROCURL}\n${MSG_ARTIST}\nTMP_ARTIST:\n${TMP_ARTIST}\n${MSG_MP3}\n${MSG_CACHED_MP3}\`\`\`"
  fi
fi
