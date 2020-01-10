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
DB
-------------------------------------------------------------
EOF

IFS='' read -r -d '' help <<"EOF"
Functions to interact with the sqlite db. Every action will pull a 
fresh copy of the sqlite db from s3 first. On insert/update actions
the db will be pulled from s3 first, then pushed back up after the
query.

*** - Required parameter
Usage: ./db.sh [arguments]

  *** --sqlite-bucket [s3-endpoint] - An sqlite db filename+path in
                                      an s3 bucket (example: s3://bucket/timelapse.db)
  *** --sqlite-local  [filename]    - A local path to store sqlite
                                      db while queries are being run
  *** --action        [str]         - [get-raw-keys,get-processed-keys,get-audio-keys,
                                       get-raw-video-by-key,get-processed-video-by-key,
                                       get-audio-by-key]
EOF


while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
  opt="$1";
  shift;
  case "$opt" in
      "--" ) break 2;;
      "--sqlite-bucket" )
         SQLITE_BUCKET="$1"; shift;;
      "--sqlite-local" )
         SQLITE_LOCAL="$1"; shift;;
      "--action" )
         DB_ACTION="$1"; shift;;
      "--key" )
         DB_KEY="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done

if [ -z "$SQLITE_BUCKET" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include an s3 bucket to store/retrieve sqlite db"
  exit 1
fi

if [ -z "$SQLITE_LOCAL" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include a local directory store/retrieve sqlite db"
  exit 1
fi

if [ -z "$DB_ACTION" ]; then
  echo "$banner"
  echo "$help"
  echo "Must include an action to take... whatcha doin' mang?"
  exit 1
fi

# ****************** Get Keys ***************** #

if [ "$DB_ACTION" == "get-raw-keys" ]; then
  get_raw_keys $SQLITE_BUCKET $SQLITE_LOCAL
  exit 0
fi


if [ "$DB_ACTION" == "get-processed-keys" ]; then
  get_processed_keys $SQLITE_BUCKET $SQLITE_LOCAL
  exit 0
fi


if [ "$DB_ACTION" == "get-audio-keys" ]; then
  get_audio_keys $SQLITE_BUCKET $SQLITE_LOCAL
  exit 0
fi




# ****************** Get Single ***************** #

if [ "$DB_ACTION" == "get-raw-video-by-key" ]; then
  if [ -z "$DB_KEY" ]; then
    echo "Must provide key to get raw video"
    exit 1
  fi
  get_raw_video $SQLITE_BUCKET $SQLITE_LOCAL $DB_KEY | sed -e 's/|/ /g' | awk '{print "{\"" $1 "\":{\"file\":\"" $2 "\", \"created\":\"" $3 "\", \"duration\":\"" $4 "\"}}"}'
  exit 0
fi

if [ "$DB_ACTION" == "get-processed-video-by-key" ]; then
  if [ -z "$DB_KEY" ]; then
    echo "Must provide key to get processed video"
    exit 1
  fi
  ENCODED=$(get_processed_video $SQLITE_BUCKET $SQLITE_LOCAL $DB_KEY)
  NAME=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $2}') | sed -e 's/"/\\"/g')
  FILE=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $3}') | sed -e 's/"/\\"/g')
  YEAR=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $4}') | sed -e 's/"/\\"/g')
  MONTH=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $5}') | sed -e 's/"/\\"/g')
  DAY=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $6}') | sed -e 's/"/\\"/g')
  SHA=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $7}') | sed -e 's/"/\\"/g')
  CREATED=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $8}') | sed -e 's/"/\\"/g')
  DURATION=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $9}') | sed -e 's/"/\\"/g')
  if [ $MONTH -lt 10 ]; then MONTH="0$MONTH"; fi
  if [ $DAY -lt 10 ]; then DAY="0$DAY"; fi
  # print json with key
  echo "{\"$DB_KEY\":{\"name\":\"$NAME\",\"file\":\"$FILE\",\"date\":\"$YEAR/$MONTH/$DAY\",\"audio\":\"$SHA\",\"created\":$CREATED,\"duration\":$DURATION}}"
  # print json withOUT key
  # echo "{\"name\":\"$NAME\",\"file\":\"$FILE\",\"date\":\"$YEAR/$MONTH/$DAY\",\"audio\":\"$SHA\",\"created\":$CREATED,\"duration\":$DURATION}"
  exit 0
fi

if [ "$DB_ACTION" == "get-audio-by-key" ]; then
  if [ -z "$DB_KEY" ]; then
    echo "Must provide key to get raw video"
    exit 1
  fi
  ENCODED=$(get_audio $SQLITE_BUCKET $SQLITE_LOCAL $DB_KEY) 
  ARTIST=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $2}') | sed -e 's/"/\\"/g')
  ALBUM=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $3}') | sed -e 's/"/\\"/g')
  GENRE=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $4}') | sed -e 's/"/\\"/g')
  MPTHREE=$(urldecode $(echo $ENCODED | sed -e 's/|/ /g' | awk '{print $5}') | sed -e 's/"/\\"/g')
  # print json with key
  echo "{\"$DB_KEY\":{\"artist\":\"$ARTIST\",\"album\":\"$ALBUM\",\"genre\":\"$GENRE\",\"mp3\":\"$MPTHREE\"}}"
  # print json withOUT key
  # echo "{\"artist\":\"$ARTIST\",\"album\":\"$ALBUM\",\"genre\":\"$GENRE\",\"mp3\":\"$MPTHREE\"}"
  exit 0
fi





# If you get this far... action not found
echo "Action not found ¯\_(ツ)_/¯"
exit 1

