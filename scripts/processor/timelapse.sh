#!/bin/bash

IFS='' read -r -d '' help <<"EOF"
-------------------------------------------------------------
___________.__               .__                              
\__    ___/|__| _____   ____ |  | _____  ______  ______ ____  
  |    |   |  |/     \_/ __ \|  | \__  \ \____ \/  ___// __ \ 
  |    |   |  |  Y Y  \  ___/|  |__/ __ \|  |_> >___ \\  ___/ 
  |____|   |__|__|_|  /\___  >____(____  /   __/____  >\___  >
                    \/     \/          \/|__|       \/     \/ 

-------------------------------------------------------------
Creates an mp4 at 1080p/60fps of images specified in stage-dir
Usage: ./timelapse [arguments]

[req]--name           [str]  - Name of camera/timelapse
[req]--target-date    [date] - Date of timelapse
[req]--stage-dir      [path] - Expects directories of images separated
                               by hour. Use absolute path
     --destage-dir    [path] - by default, a directory is created in the
                               stage directory, if none is provided
     --output-dir     [path] - by default, a directory is created in the
                               stage directory, if none is provided
     --dry-run        [bool] - by default [0], runs through what commands
                               would be executed in the stage/remove-flashes
                               sections
     --copy-staged    [bool] - by default [0], files are moved from hour
                               directories into one, for the  whole day
                               Set to 1 to copy files, and preserve
                               source files 
     --remove-flashes [bool] - by default [0], the script will remove
                               the first three frames of any gap larger
                               than six seconds, while auto-white-balance
                               adjusts. Set to 1 enable
EOF
convertsecs() {
  ((h=${1}/3600))
  ((m=(${1}%3600)/60))
  ((s=${1}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}
REMOVE_FLASHES=0
DRY_RUN=0
COPY_STAGED=0
while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
  opt="$1";
  shift;
  case "$opt" in
      "--" ) break 2;;
      "--name" )
         NAME="$1"; shift;;
      "--target-date" )
         TARGET_DATE="$1"; shift;;
      "--stage-dir" )
         STAGE_DIR="$1"; shift;;
      "--destage-dir" )
         DESTAGE_DIR="$1"; shift;;
      "--output-dir" )
         OUTPUT_DIR="$1"; shift;;
      "--copy-staged" )
         COPY_STAGED="$1"; shift;;
      "--remove-flashes" )
         REMOVE_FLASHES="$1"; shift;;
      "--dry-run" )
         DRY_RUN="$1"; shift;;
      *) echo >&2 "Invalid option: $@"; exit 1;;
  esac
done

if [ -z "$TARGET_DATE" ]; then
  echo "Missing target-date value..."
  echo "$help"
  exit 1
fi

if [ -z "$NAME" ]; then
  echo "Missing name..."
  echo "$help"
  exit 1
fi

if [ -z "$STAGE_DIR" ]; then
  echo "Missing stage directory value..."
  echo "$help"
  exit 1
fi

if [ -z "$DESTAGE_DIR" ]; then
  DESTAGE_DIR="$STAGE_DIR/stage"
  mkdir -p $DESTAGE_DIR
fi

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$STAGE_DIR/output"
  mkdir -p $OUTPUT_DIR
fi

YEAR=$(date '+%Y' -d "${TARGET_DATE}" )
MONTH=$(date '+%m' -d "${TARGET_DATE}" )
DAY=$(date '+%d' -d "${TARGET_DATE}" )
TARGET="${YEAR}_${MONTH}_${DAY}"
TOTAL=0

# Staged images are expected to be saved in folders
# by hour. This section copies the images from those
# directories into a "destaged" directory
if [ $DRY_RUN -eq 1 ] || [ $COPY_STAGED -eq 1 ]; then
  echo "Stage ALL files from this date: ${TARGET}"
  for x in {0..23}; do
    if [[ "${x}" -lt 10 ]]; then
      HOUR="0$x"
    else
      HOUR=$x
    fi
    if [ -d "${STAGE_DIR}/${TARGET}_${HOUR}" ]; then
      FILE_THIS_HOUR=$(ls ${STAGE_DIR}/${TARGET}_${HOUR}/*.jpg | wc -l)
      echo "Copying $FILE_THIS_HOUR files: ${TARGET}_${HOUR}"
      TOTAL=$((FILE_THIS_HOUR + TOTAL))
      if [ $COPY_STAGED -eq 1 ]; then
        cp ${STAGE_DIR}/${TARGET}_${HOUR}/*.jpg ${DESTAGE_DIR}/.
      else
        echo "skipping copy stage step..."
      fi
    else
      echo "directory does NOT exist: ${TARGET}_${HOUR}"
    fi
  done
else
  echo "Skipping copy stage step."
fi

TOTAL_STAGED=$(find ${DESTAGE_DIR}/ -maxdepth 1 | wc -l)
TOTAL_STAGED=$((TOTAL_STAGED - 1))
# echo "Does the copied images count [$TOTAL] == staged images count [$TOTAL_STAGED]"

# When the camera first starts, or restarts the auto-white-balance feature
# causes a flash on the screen. This section will remove those frames, whenever
# a gap of more than five seconds is detected. A jump cut is preferable to a jump
# cut and a flash. 
LAST=0
DELETE=6
TRACK=0
MASTER_TRACK=0
TRACK_PERCENTAGE=-1

if [ $DRY_RUN -eq 1 ] || [ $REMOVE_FLASHES -eq 1 ]; then
  for filename in ${DESTAGE_DIR}/*.jpg; do
    let MASTER_TRACK++
    # echo $filename
    PERCENT_COMPLETE=$(awk "BEGIN { pc=100*${MASTER_TRACK}/${TOTAL_STAGED}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
    if [ "$PERCENT_COMPLETE" -ne "$TRACK_PERCENTAGE" ]; then
      echo "Percent complete: ${PERCENT_COMPLETE}%"
    fi
    TRACK_PERCENTAGE="$PERCENT_COMPLETE"
    str=$(echo $filename | sed -e 's/\.jpg//g' | sed -e 's/^.*\///g')
    delimiter="_"
    s=$str$delimiter
    dateSplit=();
    while [[ $s ]]; do
      dateSplit+=( "${s%%"$delimiter"*}" );
      s=${s#*"$delimiter"};
    done;
    dateLength="${#dateSplit[@]}"
    if [ "${dateLength}" -eq 6 ]; then
      YEAR=${dateSplit[0]}
      MONTH=${dateSplit[1]}
      DAY=${dateSplit[2]}
      HOUR=${dateSplit[3]}
      MINUTE=${dateSplit[4]}
      SECOND=${dateSplit[5]}
      THIS_TIMESTAMP=$(date '+%s' -d "${YEAR}/${MONTH}/${DAY} ${HOUR}:${MINUTE}:${SECOND}")
      # echo "Unix: ${THIS_TIMESTAMP}"
      let "DIFF=$THIS_TIMESTAMP-$LAST"
      # echo "Diff: ${DIFF}"
      if [ "${DIFF}" -gt 3 ]; then
        let TRACK++
      fi
      if [ "${TRACK}" -gt 0 ]; then
        if [ "${TRACK}" -lt "${DELETE}" ]; then
          DELETE_THIS="rm -rf $filename"
          echo "DELETE THIS... ${DELETE_THIS}"
          if [ $REMOVE_FLASHES -eq 1 ]; then
            echo $($DELETE_THIS)
          else
            echo "skipping flash removal"
          fi
          let TRACK++
        else
          TRACK=0
        fi
      fi
      LAST="${THIS_TIMESTAMP}"
    fi
  done
else
  echo "skipping flash removal."
fi



TOTAL_STAGED_DEFLASHED=$(find ${DESTAGE_DIR}/ -maxdepth 1 | wc -l)
TOTAL_STAGED_DEFLASHED=$((TOTAL_STAGED_DEFLASHED - 1))
echo "Raw footage seconds: $TOTAL_STAGED"
echo "Raw footage: $(convertsecs $TOTAL_STAGED)"
if [ $REMOVE_FLASHES -eq 1 ]; then
  echo "DeFlashed footage seconds: $TOTAL_STAGED_DEFLASHED"
  echo "DeFlashed footage: $(convertsecs $TOTAL_STAGED_DEFLASHED)"
fi


if [ -f "$OUTPUT_DIR/${NAME}_${TARGET}.mp4" ]; then
  echo "Target output file already exists..."
  echo "$OUTPUT_DIR/${NAME}_${TARGET}.mp4"
  exit 1
fi

cd $DESTAGE_DIR
ffmpeg -framerate 60 -pattern_type glob -i '*.jpg' -c:v libx265 -crf 25 "$OUTPUT_DIR/${NAME}_${TARGET}.mp4"

echo "Timelapse Created: $OUTPUT_DIR/${NAME}_${TARGET}.mp4"

