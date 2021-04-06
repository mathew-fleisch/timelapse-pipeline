#!/bin/bash
# shellcheck disable=SC2164,SC2086,SC2046

# Default pin: 14 (GPIO14)
target_pin=${1:-14}
# Target temperature in celsius to turn the fan on/off
target_threshold=${2:-50}
# This variable is used to only log changes in temperature
last_temp=0
# This variable is used to only turn the fan on/off once every threshold cross
current_state=0
# Seconds between each reading
sleep_interval=5

# Set initial state of fan
gpio -g mode $target_pin output
gpio -g write $target_pin $current_state

celsius_to_fahrenheit() {
  celsius=$1
  echo "scale=4; $celsius*1.8 + 32" | bc
}
get_temp() {
  temp=$(cat /sys/class/thermal/thermal_zone0/temp)
  echo $((temp/1000)) 
}

# Log target pin/threshold and log each iteration in three columns (timestamp, temperature, fan state)
echo "Fan Control - Pin($target_pin) - Threshold(${target_threshold}°C)"
echo "timestamp               temp            fan"
sleep 2
while true; do
  # Get temp
  temp_c=$(get_temp)
  temp_f=$(celsius_to_fahrenheit $temp_c)
  # Check the current state of the fan and only change it
  # if the threshold is passed in either direction
  if [ $temp_c -gt $target_threshold ]; then
    # Turn ON the fan if the temp is over the threshold
    if [ $current_state -ne 1 ]; then
      gpio -g write $target_pin 1
      current_state=1
    fi
  else
    # Turn OFF the fan if the temp is under the threshold
    if [ $current_state -ne 0 ]; then
      gpio -g write $target_pin 0
      current_state=0
    fi
  fi

  # Only show changes in temp
  if [ $temp_c -ne $last_temp ]; then
	  pretty_state="OFF"
	  if [ $current_state -eq 1 ]; then
		  pretty_state="ON"
	  fi
	  echo "$(date +%F\ %H:%M:%S)	$temp_c°C/$temp_f°F	$pretty_state"
  fi
  last_temp=$temp_c

  sleep $sleep_interval
done
