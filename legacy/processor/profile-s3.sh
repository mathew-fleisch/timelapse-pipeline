  #!/bin/bash

  # if [ -z "$1" ]; then
  #   echo "Missing s3 bucket+path to profile"
  #   exit 1
  # fi
  # BUCKET="$1"

  # if [ -z "$2" ]; then
  #   echo "Missing s3 bucket+path to check for raw videos"
  #   exit 1
  # fi
  # TARGET="$2"
    
  if [ -z "$1" ]; then
    echo "Missing camera name"
    exit 1
  fi
  CAMERA_NAME="$1"

  TARGET="s3://eaze-timelapse/pipeline"
  if [ "$CAMERA_NAME" == "ferry" ]; then
    BUCKET="s3://eaze-timelapse/raw"
  else
    BUCKET="s3://eaze-timelapse/${CAMERA_NAME}"
  fi

  if [ -z "$TIMELAPSE_CIRCLE_TOKEN" ]; then
    echo "Missing circleci token... cannot kick off jobs."
    exit 1
  fi
  cd /usr/timelapse/scripts/processor
  if ! [ -f "./remote-timelapse.sh" ]; then
    echo "Missing remote-timelapse script!"
    exit 1
  fi

  for YEAR in $(seq 2019 2020); do
    for MONTH in $(seq 1 12); do
      if [[ $MONTH -lt 10 ]]; then
        MONTH="0$MONTH"
      fi

      for DAY in $(aws s3 ls "${BUCKET}/${YEAR}/${MONTH}/" | awk '{print $2}' | head -n -1 | sed -e 's/\/$//g'); do
        RAW_VIDEO_PATH="${TARGET}/videos/raw/${YEAR}_${MONTH}_${DAY}/${CAMERA_NAME}_${YEAR}_${MONTH}_${DAY}.mp4"
        # echo "Raw Video Path: $RAW_VIDEO_PATH"
        RAW_EXISTS=$(aws s3 ls $RAW_VIDEO_PATH)
        # echo "Raw Exists: $RAW_EXISTS"
        TARGET_DATE="${YEAR}/${MONTH}/${DAY}"
        if [ -z "$RAW_EXISTS" ]; then
          echo "${BUCKET}/${YEAR}/${MONTH}/${DAY} - Raw Missing"
          ./remote-timelapse.sh \
              --circle-token ${TIMELAPSE_CIRCLE_TOKEN} \
              --source-name ${CAMERA_NAME} \
              --source-base ${BUCKET} \
              --target-base ${TARGET} \
              --org-fork eaze \
              --target-date ${TARGET_DATE} \
              --slack-channel GJJ59K1M0 \
              --slack-user U9RLE97T2
          echo "Delay: 15min"
          for min in $(seq 1 15); do
            echo "${min}:00"
            for sec in $(seq 1 60); do
              if ! ((sec % 10)); then
                echo "."
              fi
              sleep 1
            done
            echo ""
          done
        else
          echo "${BUCKET}/${YEAR}/${MONTH}/${DAY} - Raw Exists"
        fi

      done
    done
  done