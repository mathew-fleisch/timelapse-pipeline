# Timelapse Pipeline

This project allows you to set up a timelapse using the Raspberry Pi + camera to capture stills, and ffmpeg to generate timelapse videos. Clone the repository, modify the configuration file to match your location, and set up a cron to execute the script every day before the sun rises. An api call to [https://sunrise-sunset.org/api](https://sunrise-sunset.org/api) will get the exact sunrise and sunset for the configured latitude and longitude to determine when to save pictures via raspistill. Once the sun sets, the script will automatically compile the stills into a video using ffmpeg.

### Prerequisites

 - curl
 - ffmpeg
 - jq
 - raspistill

```
sudo apt update && sudo apt install -y curl ffmpeg jq
```

### Installation

```
# Clone Repository
git clone https://github.com/mathew-fleisch/timelapse-pipeline.git
cd timelapse-pipeline

# Customize config.json to your timezone and location
cp config.sample.json config.json

# Note timelapse-pipline location: [SCRIPT-LOCATION]
pwd

# Run/Debug script manually (normal use is intended to be executed via cron. see below)
./timelapse.sh config.json /tmp/timelapse-stage

# Set up cron
crontab -e
0 4 * * * [SCRIPT-LOCATION]/timelapse.sh /tmp/timelapse-stage >> /tmp/timelapse-stage/log.txt 2>&1
```


### Fan Control (optional)

The fan noise can be annoying but it is helpful when processing video. To that end, I have used a transistor and a gpio pin to turn the fan on/off electronically. It will turn on when the on-board temperature is over the target threshold and turn off when it is under that threshold.

```
# Usage: ./fan-control.sh [gpio-pin] [threshold-temperature-celsius]
./fan-control.sh 14 45
Fan Control - Pin(21) - Threshold(45°C)
timestamp               temp    fan
2021-02-07 21:23:56 	55°C	ON
2021-02-07 21:24:06 	53°C	ON
2021-02-07 21:24:11 	52°C	ON
2021-02-07 21:24:16 	51°C	ON
2021-02-07 21:24:21 	52°C	ON
2021-02-07 21:24:26 	51°C	ON
2021-02-07 21:24:31 	50°C	ON
2021-02-07 21:24:41 	49°C	ON
2021-02-07 21:24:46 	48°C	ON
2021-02-07 21:24:56 	47°C	ON
2021-02-07 21:25:16 	46°C	ON
2021-02-07 21:25:26 	45°C	OFF
```

