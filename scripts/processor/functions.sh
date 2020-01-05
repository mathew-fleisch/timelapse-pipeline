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
  # These values are likely to have spaces, the base64 encode/decode removes them.
  ARTIST=$(echo $4 | base64 --decode)
  ALBUM=$(echo $5 | base64 --decode)
  GENRE=$(echo $6 | base64 --decode)
  MPTHREE=$(echo $7 | base64 --decode)
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
  sqlite3 $2 "insert into raw (sha, artist, album, genre, mpthree, duration) values (\"$3\", \"$ARTIST\", \"$ALBUM\", \"$GENRE\", \"$MPTHREE\", $8);"

  # Copy the sqlite db back to s3
  aws s3 cp $2 $1 --quiet

}



# Video Sqlite
# create table video (key TEXT PRIMARY KEY, name TEXT, filename TEXT, year INTEGER, month INTEGER, day INTEGER, audio TEXT, created INTEGER, duration INTERGER);
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

  # Copy the sqlite db from s3
  aws s3 cp $1 $2 --quiet

  if ! [ -f "$2" ]; then
    echo "error pulling sqlite db from s3..."
    exit 1
  fi

  # Run query
  sqlite3 $2 "insert into video (key, name, filename, year, month, day, audio, created, duration) values (\"$3\", \"$4\", \"$5\", $6, $7, $8, \"$9\", $10, $11);"

  # Copy the sqlite db back to s3
  aws s3 cp $2 $1 --quiet


}

