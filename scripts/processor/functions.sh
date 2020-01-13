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

urlencode() {
  # urlencode <string>
  old_lc_collate=$LC_COLLATE
  LC_COLLATE=C
  
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
    local c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
      *) printf '%%%02X' "'$c" ;;
    esac
  done
  
  LC_COLLATE=$old_lc_collate
}

urldecode() {
  # urldecode <string>

  local url_encoded="${1//+/ }"
  printf '%b' "${url_encoded//%/\\x}"
}

num_files() {
  if [ -d "$1" ]; then
    echo $(find ${1}/ -maxdepth 1 | wc -l)
  else
    echo "Error: Directory does not exist"
  fi
}
slack_message() {
  if [ -z "$1" ]; then
    echo "Must include slack api token"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "Must include a channel id"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "Must include message to send"
    exit 1
  fi
  T_SLACK_TOKEN="$1"
  T_CHANNEL="$2"
  T_MESSAGE="$3"
  # T_MESSAGE=$(echo $3 | sed -e 's/\s/+/g') 
  # T_MESSAGE=$(urlencode $3)
  
  # curl -s -X POST https://slack.com/api/chat.postMessage?token=${T_SLACK_TOKEN}\&channel=${T_CHANNEL}\&text=${T_MESSAGE}

  # curl -X POST -H 'Authorization: Bearer '${T_SLACK_TOKEN} -H 'Content-type: application/json; charset=utf-8' --data '{"channel":"'${T_CHANNEL}'","text":"'${T_MESSAGE}'"}' https://slack.com/api/chat.postMessage
  curl -X POST -H 'Authorization: Bearer '${T_SLACK_TOKEN} -H 'Content-type: application/json; charset=utf-8' --data "{\"channel\":\"${T_CHANNEL}\",\"text\":\"${T_MESSAGE}\"}" https://slack.com/api/chat.postMessage
}
initialize_sqlite_db() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi
  sqlite3 $2 "create table raw (key TEXT PRIMARY KEY, filename TEXT, created INTEGER, duration INTERGER);"
  sqlite3 $2 "create table audio (sha TEXT PRIMARY KEY, artist TEXT, album TEXT, genre TEXT, mpthree TEXT, duration INTERGER);"
  sqlite3 $2 "create table video (key TEXT PRIMARY KEY, name TEXT, filename TEXT, year INTEGER, month INTEGER, day INTEGER, audio TEXT, created INTEGER, duration INTERGER);"
  # Copy the newly created sqlite db to s3
  aws s3 cp $2 $1
}

# Raw Video Sqlite
# create table raw (key TEXT PRIMARY KEY, filename TEXT, created INTEGER, duration INTERGER)
get_raw_keys() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet
  
  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  sqlite3 $2 "select key from raw;"
}
get_raw_video() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "must include a key to query the db by (NAME_YYYY_MM_DD)"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet
  
  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  sqlite3 $2 "select * from raw where key = \"$3\";"
}
put_raw_video() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "must include a key (NAME_YYYY_MM_DD)"
    exit 1
  fi
  if [ -z "$4" ]; then
    echo "must include a filename/path"
    exit 1
  fi
  if [ -z "$5" ]; then
    echo "must include a created epoch timestamp"
    exit 1
  fi
  if [ -z "$6" ]; then
    echo "must include a duration (integer)"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet

  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  # Run query
  sqlite3 $2 "insert into raw (key, filename, created, duration) values (\"$3\", \"$4\", $5, $6)"

  # Copy the sqlite db back to s3
  aws s3 cp $2 $1 --quiet
}








# Audio Sqlite
# create table audio (sha TEXT PRIMARY KEY, artist TEXT, album TEXT, genre TEXT, mpthree TEXT, duration INTERGER);

get_audio_keys() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet
  
  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  sqlite3 $2 "select sha from audio;"
}
get_audio() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "must include a key to query"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet
  
  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  sqlite3 $2 "select * from audio where sha = \"$3\";"
}
put_audio() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "must include a sha"
    exit 1
  fi
  if [ -z "$4" ]; then
    echo "must include an artist string/link"
    exit 1
  fi
  if [ -z "$5" ]; then
    echo "must include an album string/link"
    exit 1
  fi
  if [ -z "$6" ]; then
    echo "must include a genre string"
    exit 1
  fi
  if [ -z "$7" ]; then
    echo "must include an mp3 link"
    exit 1
  fi
  if [ -z "$8" ]; then
    echo "must include a duration integer"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  SHA=$(urlencode "$3")
  ARTIST=$(urlencode "$4")
  ALBUM=$(urlencode "$5")
  GENRE=$(urlencode "$6")
  MPTHREE=$(urlencode "$7")

  if ! [ -z "$DEBUG" ]; then
    echo "Remote: \"$1\""
    echo "Local: \"$2\""
    echo "Audio Sha: \"$SHA\""
    echo "Artist: \"$ARTIST\""
    echo "Album: \"$ALBUM\""
    echo "Genre: \"$GENRE\""
    echo "Mp3: \"$MPTHREE\""
    echo "Duration: $8"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet

  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  # Run query
  QUERY="insert into audio (sha, artist, album, genre, mpthree, duration) values (\"$SHA\", \"$ARTIST\", \"$ALBUM\", \"$GENRE\", \"$MPTHREE\", $8);"
  echo "$QUERY"
  sqlite3 $2 "$QUERY"

  # Copy the sqlite db back to s3
  aws s3 cp $2 $1 --quiet

}



# Video Sqlite
# create table video (key TEXT PRIMARY KEY, name TEXT, filename TEXT, year INTEGER, month INTEGER, day INTEGER, audio TEXT, created INTEGER, duration INTERGER);

get_processed_keys() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet
  
  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  sqlite3 $2 "select key from video;"
}
get_processed_video() {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "must include a key to query the db by (NAME_YYYY_MM_DD)"
    exit 1
  fi
  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet
  
  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  sqlite3 $2 "select * from video where key = \"$3\";"
}
put_video()  {
  if [ -z "$1" ]; then
    echo "must include s3 bucket+path+filename to store the db"
    exit 1
  fi
  if [ -z "$2" ]; then
    echo "must include local file to store the db"
    exit 1
  fi
  if [ -z "$3" ]; then
    echo "must include a key (NAME_YYYY_MM_DD)"
    exit 1
  fi
  if [ -z "$4" ]; then
    echo "must include a camera name"
    exit 1
  fi
  if [ -z "$5" ]; then
    echo "must include a filename"
    exit 1
  fi
  if [ -z "$6" ]; then
    echo "must include a year (integer)"
    exit 1
  fi
  if [ -z "$7" ]; then
    echo "must include a month (integer)"
    exit 1
  fi
  if [ -z "$8" ]; then
    echo "must include a day of the month (integer)"
    exit 1
  fi
  if [ -z "$9" ]; then
    echo "must include a audio file sha (of mp3 link)"
    exit 1
  fi
  if [ -z "$10" ]; then
    echo "must include a created epoch timestamp"
    exit 1
  fi
  if [ -z "$11" ]; then
    echo "must include a duration (integer)"
    exit 1
  fi

  # Delete any local dbs that may already exist
  if [ -f "$2" ]; then
    rm -rf "$2"
  fi

  if ! [ -z "$DEBUG" ]; then
    echo "Remote: \"$1\""
    echo "Local: \"$2\""
    echo "Key: \"$3\""
    echo "Name: \"$4\""
    echo "Filename: \"$5\""
    echo "year: \"$6\""
    echo "month: \"$7\""
    echo "day: \"$8\""
    echo "Audio Sha: \"$9\""
    echo "Created Timestamp: ${10}"
    echo "Duration: ${11}"
  fi


  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet

  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  # Run query
  sqlite3 $2 "insert into video (key, name, filename, year, month, day, audio, created, duration) values (\"$3\", \"$4\", \"$5\", $6, $7, $8, \"$9\", ${10}, ${11});"

  # Copy the sqlite db back to s3
  aws s3 cp $2 $1 --quiet


}

