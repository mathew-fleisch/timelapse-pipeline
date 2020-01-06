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
  *** --sqlite-db [filename] - An sqlite db filename found relateive
                               to target-base s3 bucket
     --existing-audio [SHA]  - default behavior is to pick a new
                               random audio file.
    --genre           [str]  - Blues,Classical,Folk,Hip-Hop,Instrumental,
                               International,Jazz,Lo-fi,Old-Time__Historic,
                               Pop,Rock,Soul-RB (default: Hip-Hop)
EOF



SHORT_SONG_THRESHOLD=150
DEFAULT_START=0
DEFAULT_END=23
GENRE="Hip-Hop"
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
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done

if [ -z "$NAME" ]; then
  echo "$help"
  echo "Must include a camera name"
  exit 1
fi
if [ -z "$TARGET_DATE" ] || [ -z "$T_YEAR" ] || [ -z "$T_MONTH" ] || [ -z "$T_DAY" ]; then
  echo "$help"
  echo "Must include a target date"
  exit 1
fi
if [ -z "$TARGET_DIR" ]; then
  echo "$help"
  echo "Must include a directory with write access"
  exit 1
fi
if [ -z "$TARGET_BASE" ]; then
  echo "$help"
  echo "Must include an s3 bucket+path to push images to"
  exit 1
fi
if [ -z "$SQLITE_DB" ]; then
  echo "$help"
  echo "Must include a sqlite db filename to store/retrieve meta-data about audio/video"
  exit 1
fi

NOW=$(date +%s)
KEY="${NAME}_${T_YEAR}_${T_MONTH}_${T_DAY}"
FILENAME="${KEY}.mp4"
LOCAL_FILENAME="${TARGET_DIR}/output/${FILENAME}"
TARGET_FILENAME="videos/raw/${T_YEAR}_${T_MONTH}_${T_DAY}/${FILENAME}"
PROCESSED_FILENAME=$(echo $TARGET_FILENAME | sed -e 's/raw/processed/g')
AUDIO_REJECTED_FILENAME="audio/rejected.txt"

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
  echo "Video does not exist..."
  if [ -z "$SOURCE_BASE" ]; then
    echo "A source s3 bucket+path is required to run this section"
    exit 1
  fi
  HAS_IMAGES=$(aws s3 ls ${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_${CURRENT_HOUR})
  if [ -z "$HAS_IMAGES" ]; then
    echo "There are no images in this source bucket:"
    echo "${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_${CURRENT_HOUR}"
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
    echo "Current hour: $CURRENT_HOUR"
    aws s3 cp ${SOURCE_BASE}/${T_YEAR}/${T_MONTH}/${T_DAY}/${T_YEAR}_${T_MONTH}_${T_DAY}_${CURRENT_HOUR} ${TARGET_DIR}/stage/.
  done

  # Pick arbitrary threshold of minimum frames
  # to create a timelapse. avg ~ 60k frames
  ./timelapse.sh --target-date $TARGET_DATE --stage-dir $TARGET_DIR --remove-flashes 1 --name $NAME

  if ! [ -f "$LOCAL_FILENAME" ]; then
    echo "mp4 failed to generate..."
    exit 1
  fi
  DURATION=$(get_duration_in_seconds $LOCAL_FILENAME)
  aws s3 cp $LOCAL_FILENAME ${TARGET_BASE}/${TARGET_FILENAME}
  
  # Save raw video meta-data
  put_raw_video ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db "$KEY" "$TARGET_FILENAME" $NOW $DURATION
else
  # There is a video file described in the raw table, download the processed video
  echo "Download mp4 file..."
  rm -rf ${TARGET_DIR}/output
  mkdir -p ${TARGET_DIR}/output
  aws s3 cp ${TARGET_BASE}/${TARGET_FILENAME} ${TARGET_DIR}/output/.
fi





# Either the mp4 was downloaded, or generated. Add Audio
if [ -z "$EXISTING_AUDIO" ]; then
  FOUND_MUSIC=0
  touch ${TARGET_DIR}/music/new-rejects.txt
  REJECTED=$(aws s3 cp ${TARGET_BASE}/${AUDIO_REJECTED_FILENAME} ${TARGET_DIR}/music/rejected.txt)
  while [ $FOUND_MUSIC -eq 0 ]; do
    MUSIC=$(./get-music.sh --genre $GENRE)
    mkdir -p ${TARGET_DIR}/music
    # There are 20 mp3s per page exported as json
    # Iterate through each one, check to see if already
    # rejected, then check duration to see if greater 
    # than minimum threshold
    for row in $(echo "${MUSIC}" | jq -r '.[] | @base64'); do
      _jq() {
       echo ${row} | base64 --decode | jq -r ${1}
      }
      THIS_ARTIST=$(_jq '.artist')
      THIS_ALBUM=$(_jq '.artist')
      THIS_GENRE=$(_jq '.genre')
      THIS_MPTHREE=$(_jq '.mpthree')
      SONG_SHA=$(echo $THIS_MPTHREE | shasum | awk '{print $1}')
      ALREADY_REJECTED=$(cat ${TARGET_DIR}/music/rejected.txt | grep ${SONG_SHA})
      if [ -z "$ALREADY_REJECTED" ]; then
        echo "$THIS_ARTIST"
        echo "$THIS_MPTHREE"
        echo "${SONG_SHA}.mp3"
        curl -s $THIS_MPTHREE --output ${TARGET_DIR}/music/${SONG_SHA}.mp3
        THIS_DURATION=$(get_duration_in_seconds ${TARGET_DIR}/music/${SONG_SHA}.mp3)
        echo "Duration: $THIS_DURATION ?> $SHORT_SONG_THRESHOLD"
        if [ $THIS_DURATION -gt $SHORT_SONG_THRESHOLD ]; then
          echo "This song should do!"
          let FOUND_MUSIC++
          put_audio ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db "$SONG_SHA" "$THIS_ARTIST" "$THIS_ALBUM" "$THIS_GENRE" "$THIS_MPTHREE" $THIS_DURATION
          aws s3 cp ${TARGET_DIR}/music/${SONG_SHA}.mp3 ${TARGET_BASE}/audio/${SONG_SHA}.mp3
          break
        else
          echo "$SONG_SHA" >> ${TARGET_DIR}/music/new-rejects.txt
        fi
      else
        echo "Already Rejected:"
        echo "$THIS_MPTHREE"
      fi
    done
  done

  # Add new rejected mp3 shas to the full list of rejects
  cat ${TARGET_DIR}/music/new-rejects.txt >> ${TARGET_DIR}/music/rejected.txt

  # Push the new rejected mp3 shas to s3
  aws s3 cp ${TARGET_DIR}/music/rejected.txt ${TARGET_BASE}/${AUDIO_REJECTED_FILENAME}
else
  echo "Use existing mp3: $EXISTING_AUDIO"
  SONG_SHA="$EXISTING_AUDIO"
  aws s3 cp ${TARGET_BASE}/audio/${SONG_SHA}.mp3 ${TARGET_DIR}/music/${SONG_SHA}.mp3
fi



# Merge audio/video
./merge-audio-video.sh ${TARGET_DIR}/music/${SONG_SHA}.mp3 ${TARGET_DIR}/output/${FILENAME}

# Upload to s3
aws s3 cp ${TARGET_DIR}/output/${KEY}_fade.mp4 ${TARGET_BASE}/${PROCESSED_FILENAME}

NEW_DURATION=$(get_duration_in_seconds ${TARGET_DIR}/output/${KEY}_fade.mp4)
# Save meta-data about processed video (key, name, filename, year, month, day, audio, created, duration)
put_video ${TARGET_BASE}/${SQLITE_DB} ${TARGET_DIR}/timelapse.db "$KEY" "$NAME" "$PROCESSED_FILENAME" $T_YEAR $T_MONTH $T_DAY "$SONG_SHA" $NOW $NEW_DURATION

# Upload to youtube (could be separate step... perhaps... with testcafe... wtf)




ENDED=$(date +%s)
FINISHED=$((ENDED-NOW))
runtime=$(convertsecs $FINISHED)
echo "Timelapse Processing Time: $runtime"
