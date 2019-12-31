#!/bin/bash

IFS='' read -r -d '' help <<"EOF"
-------------------------------------------------------------
Random Mp3s from FreeMediaArchive.org
-------------------------------------------------------------
Usage Example: ./get-music.sh --genre "Lo-fi" --number 2

[req]--genre           [str]  - Blues,Classical,Folk,Hip-Hop,Instrumental,
                                International,Jazz,Lo-fi,Old-Time__Historic,
                                Pop,Rock,Soul-RB
     --number          [1-20] - default 1. Number of songs to return. There
                                are 20 mp3s on a page, and after shuffling,
                                will return this many mp3 urls. 

EOF
RETURN_NUMBER=1
while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
  opt="$1";
  shift;
  case "$opt" in
      "--" ) break 2;;
      "--genre" )
         GENRE="$1"; shift;;
      "--number" )
         RETURN_NUMBER="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done


if [ -z "$GENRE" ]; then
  echo "Must specify a genre"
  echo "$help"
  exit 1
fi

TOTAL_IN_GENRE=$(curl -s "https://freemusicarchive.org/genre/${GENRE}" | grep -A1 pagination | grep span | sed -e 's/^.*of <b>//g' | sed -e 's/<\/b>.*//g')
PAGE_SIZE=20
PAGES=$((TOTAL_IN_GENRE / PAGE_SIZE))
RANDOM_PAGE=$(shuf -i 1-${PAGES} -n 1)

curl -s https://freemusicarchive.org/genre/${GENRE}?sort=track_date_published\&d=1\&page=${RANDOM_PAGE} | grep mp3 | grep -v grep | grep href | sed -e 's/<a href="//g' | sed -e 's/" class.*//g' | shuf -n ${RETURN_NUMBER}


