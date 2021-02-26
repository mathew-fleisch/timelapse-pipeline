#!/bin/bash
# shellcheck disable=SC2164,SC2086,SC2046
hr="--------------------------------------------------------------"
IFS='' read -r -d '' banner <<"EOF"

___________.__               .__                              
\__    ___/|__| _____   ____ |  | _____  ______  ______ ____  
  |    |   |  |/     \_/ __ \|  | \__  \ \____ \/  ___// __ \ 
  |    |   |  |  Y Y  \  ___/|  |__/ __ \|  |_> >___ \\  ___/ 
  |____|   |__|__|_|  /\___  >____(____  /   __/____  >\___  >
                    \/     \/          \/|__|       \/     \/ 
Usage:   ./timelapse.sh [configuration-file] [staging-directory]
Example: ./timelapse.sh config.json /tmp/timelapse-staging

EOF
echo "$hr$banner$hr"
echo "Starting: $(date +%F\ %H:%M:%S)"
echo "$hr"
timelapse_started=$(date +%s)

convertsecs() {
  ((h=${1}/3600))
  ((m=(${1}%3600)/60))
  ((s=${1}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}
# Check dependencies
expected="curl jq ffmpeg raspistill"
for expect in $expected; do
    if ! command -v $expect > /dev/null; then
    echo "Missing dependency: $expect"
    exit 1
    fi
done


# configuration for timelapse images
if [ -z "$1" ]; then
  echo "must define a config.json"
  exit 1
fi
if ! [ -f "$1" ]; then
  echo "must define a config.json"
  exit 1
fi
config="$(cat $1)"

# Target for timelapse images
if [ -z "$2" ]; then
  echo "must define a location to stage images"
  exit 1
fi
if ! [ -d "$2" ]; then
    mkdir -p "$2"
fi
stage_dir="$(realpath $2)"

# Get current date and tomorrow
today=$(date +%F)
tomorrow=$(date --date="${today} + 1 day" +%F)

# delay between timelapse images
delay=$(echo "$config" | jq -r '.delay')
delay_ms=$((delay*1000))
width=$(echo "$config" | jq -r '.width')
height=$(echo "$config" | jq -r '.height')

# Get sunrise and sunset from api
latitude=$(echo "$config" | jq -r '.latitude')
longitude=$(echo "$config" | jq -r '.longitude')
timezone=$(echo "$config" | jq -r '.timezone')

# Video attributes
framerate=$(echo "$config" | jq -r '.framerate')

# Other attributes
delay_processing=$(echo "$config" | jq -r '.delay_processing')
remote_destination=$(echo "$config" | jq -r '.remote_destination')

echo "Configuration:"
echo "Stage Directory: $stage_dir"
echo "$1"
echo "$config"

echo "$hr"
echo "Getting sunrise and sunset..."
echo "curl -s https://api.sunrise-sunset.org/json?lat=${latitude}\&lng=${longitude}\&date=${today}"
results=$(curl -s https://api.sunrise-sunset.org/json?lat=${latitude}\&lng=${longitude}\&date=${today} | jq -r '.results')
echo "$results"
sunrise_time=$(echo "$results" | jq -r '.nautical_twilight_begin')
sunset_time=$(echo "$results" | jq -r '.nautical_twilight_end')

sunrise=$(date --date="TZ=\"${timezone}\" ${today} ${sunrise_time}" +%s)
sunset=$(date --date="TZ=\"${timezone}\" ${tomorrow} ${sunset_time}" +%s)

sunrise_pretty=$(date --date="TZ=\"${timezone}\" ${today} ${sunrise_time}" +%F\ %H:%M:%S)
sunset_pretty=$(date --date="TZ=\"${timezone}\" ${tomorrow} ${sunset_time}" +%F\ %H:%M:%S)
echo "Timezone Adjusted Sunrise: $sunrise_pretty"
echo "Timezone Adjusted Sunset:  $sunset_pretty"

echo "$hr"

# Track number of images
last=-1
trig=0
while [ $sunrise -ge $(date +%s) ]; do
  now=$(date +%s)
  to_sunrise_diff=$((sunrise-now))
  runtime=$(convertsecs $to_sunrise_diff)
  echo "Waiting for sunrise... ($(date +%F\ %H:%M:%S): $runtime)"
  sleep 60
done
echo "$(date +%F\ %H:%M:%S) Sunrise!!!"
echo "$hr"
sleep 3
while [ $sunset -ge $(date +%s) ]; do
  pid=$(pidof raspistill)
  # If there is no raspistill pid, start up the timelapse
  if [ -z "${pid}" ]; then
    year=$(date "+%Y")
    mkdir -p $stage_dir/$today
    # Start saving images to stage-directory
    raspistill -t 61200000 -tl $delay_ms -dt -n -e jpg -ex auto -awb auto -md 2 -q 100 -w $width -h $height -o "$stage_dir/$today/${year}_%d.jpg" &
    echo "Timelapse Started!"
    echo "raspistill -t 61200000 -tl $delay_ms -dt -n -e jpg -ex auto -awb auto -md 2 -q 100 -w $width -h $height -o \"$stage_dir/$today/${year}_%d.jpg\""
  else
    # A raspistill pid exists
    # echo "pid: ${pid}"
    # Count the current number of images in staging directory
    num=$(find ${stage_dir}/$today/. -name "*.jpg" | wc -l)
    if [[ "${last}" -eq "${num}" ]]; then
      sleep $delay
      trig=$((trig+1))
      echo "Timelapse seems to be stuck... ${trig}"
      # If more than 3 loops go by without an image saved,
      # kill the process. The next iteration of the loop will
      # start it up again.
      if [[ "${trig}" -gt 2 ]]; then
        last=-1
        trig=0
        kill -9 $pid
      fi
    else
      # echo "number of images ($(date +%F\ %H:%M:%S)): ${num}"
      echo "number of images ($(date +%s) > $sunrise): ${num}"
      last="${num}"
      trig=0
    fi
  fi
  sleep $delay
done
kill -9 $(pidof raspistill)
echo "$hr"
echo "$(date +%F\ %H:%M:%S) Sunset!!!"
echo "$hr"
sleep 5
echo "Recording images complete."
# Wait until user configured time to process videos to avoid fan noise from ffmpeg/scp.
delay_processing_epoch=$(date --date "$today $delay_processing" +%s)
current_time=$(date +%s)
delay_processing_diff=$((delay_processing_epoch-current_time))
delay_diff=$(convertsecs $delay_processing_diff)
echo "Delay processing video until: $today $delay_processing"
echo "sleeping for $delay_diff"
sleep $delay_processing_diff
echo "Moving to video processing... $today"
pushd $stage_dir
echo "First make a copy of the images to remote destination"
scp -r $today $remote_destination
pushd $today
echo "ffmpeg -hide_banner -framerate $framerate -pattern_type glob -i '*.jpg' -c:v libx265 -crf 25 \"$stage_dir/TreeCam-$today.mp4\""
ffmpeg -hide_banner -framerate $framerate -pattern_type glob -i '*.jpg' -c:v libx265 -crf 25 "$stage_dir/TreeCam-$today.mp4"
echo "Copying video to remote destination."
scp "$stage_dir/TreeCam-$today.mp4" $remote_destination
popd
popd
echo "$hr"
echo "Timelapse complete for $today: $(date +%F\ %H:%M:%S)"
now=$(date +%s)
runtime_diff=$((now-timelapse_started))
runtime=$(convertsecs $runtime_diff)
echo "Runtime: $runtime"
echo "$hr"