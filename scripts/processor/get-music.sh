#!/bin/bash

IFS='' read -r -d '' help <<"EOF"
-------------------------------------------------------------
Random Mp3s from FreeMediaArchive.org
-------------------------------------------------------------
Usage Example: ./get-music.sh --genre "Lo-fi" --page 0 | jq -r '.[0]'

[req]--genre  [str]  - Blues,Classical,Folk,Hip-Hop,Instrumental,
                       International,Jazz,Lo-fi,Old-Time__Historic,
                       Pop,Rock,Soul-RB
     --page   [int]  - (0:default for random) There are 20 songs
                       per page, and this value defines an offset.
EOF
PAGE=0
while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
  opt="$1";
  shift;
  case "$opt" in
      "--" ) break 2;;
      "--genre" )
         GENRE="$1"; shift;;
      "--page" )
         PAGE="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done

if [ -z "$GENRE" ]; then
  echo "Must specify a genre"
  echo "$help"
  exit 1
fi

# Extract the total mp3 count for this genre
TOTAL_IN_GENRE=$(curl -s "https://freemusicarchive.org/genre/${GENRE}" | grep -A1 pagination | grep span | sed -e 's/^.*of <b>//g' | sed -e 's/<\/b>.*//g')
PAGE_SIZE=20
PAGES=$((TOTAL_IN_GENRE / PAGE_SIZE))

if [ "$PAGE" -eq 0 ]; then
  # Random value within page bounds
  THIS_PAGE=$(shuf -i 1-${PAGES} -n 1)
else 
  if [ "$PAGE" -gt "$PAGES" ]; then
    echo "{\"error\":\"pagination overflow\"}"
    exit 1
  fi
  THIS_PAGE="$PAGE"
fi

# This command grabs the html from a webpage,extracts mp3 
# and the previous 10 lines of html. All of the html, except
# the href links are removed, leaving the artist, album, 
# genres and mp3 link. Finally, the relative links are
# converted to absolute links. This leaves the 4 values,
# newline separated, and delimited by a double dash "--"
RESPONSE=$(curl -s https://freemusicarchive.org/genre/${GENRE}?sort=track_date_published\&d=1\&page=${THIS_PAGE} | grep -B10 mp3 | sed -e 's/<\/*span.*>//' | sed -e 's/<\/*div.*>//' | sed -e 's/\ class.*><\/a>/><\/a>/' | sed '/^[[:space:]]*$/d' | sed -e 's/href=\"\//href="https:\/\/freemusicarchive.org\//g')
TRACK=0
ARTIST=""
ALBUM=""
GENRE=""
MPTHREE=""
LIST=""
while IFS= read -r line; do
  if ! [[ "$line" =~ ^-- ]]; then
    let TRACK++
    line=$(echo $line | sed -e 's/\"/\\\"/g')
    case "$TRACK" in
      "1" )
        ARTIST="$line"; shift;;
      "2" )
        ALBUM="$line"; shift;;
      "3" )
        GENRE="$line"; shift;;
      "4" )
        MPTHREE=$(echo $line | sed -e 's/<a\ href=\(.*\)><\/a>/\1/g' | sed -e 's/\\"//g')
        LIST="$LIST,{\"artist\":\"$ARTIST\",\"album\":\"$ALBUM\",\"genre\":\"$GENRE\",\"mpthree\":\"$MPTHREE\"}"
        TRACK=0
        ARTIST=""
        ALBUM=""
        GENRE=""
        MPTHREE=""
        shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
  fi
done <<< "$RESPONSE"

LIST="[$(echo $LIST | sed -e 's/^,//g')]"
echo "$LIST"
