#!/bin/bash

if [ -z "$1" ]; then
  echo "must define a location to stage images"
  exit 1
fi
STAGEDIR="$1"
LAST=-1
TRIG=0

while [ true ]; do
  PID=$(pidof raspistill)
  # If there is no raspistill pid, start up the timelapse
  if [ -z "${PID}" ]; then
    YEAR=$(date "+%Y")
    raspistill -t 61200000 -tl 1000 -dt -n -e jpg -ex auto -awb auto -md 2 -q 100 -w 1920 -h 1080 -o "$STAGEDIR/${YEAR}_%d.jpg" &
    echo "Timelapse Started!"
  else
    # A raspistill pid exists
    # echo "PID: ${PID}"
    # Count the current number of images in staging directory
    NUM=$(ls ${STAGEDIR}/*.jpg | wc -l)
    if [[ "${LAST}" -eq "${NUM}" ]]; then
      sleep 1
      TRIG=$((TRIG+1))
      echo "Timelapse seems to be stuck... ${TRIG}"
      # If more than 3 seconds go by without an image saved,
      # kill the process. The next iteration of the loop will
      # start it up again.
      if [[ "${TRIG}" -gt 2 ]]; then
        LAST=-1
        TRIG=0
        kill -9 $PID
      fi
    else
      echo "Number of images: ${NUM}"
      LAST="${NUM}"
      TRIG=0
    fi
  fi
  sleep 1
done
