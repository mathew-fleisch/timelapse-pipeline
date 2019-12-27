# Timelapse Pipeline

This project has tools and scripts to set up timelapse pipelines using Raspberry Pi + camera to capture stills, and ffmpeg to generate timelapse videos. The goal of this project is completely automate the process to generate, edit and upload videos. The repository assumes you have a raspberry pi + camera, and an external processing computer (linux) to store and process videos daily. 

### Installation

todo (write installation instructions and script)

### Flow

raspistill saves one picture every second to a holding directory via scripts/pi/start-timelapse.sh

Another script then renames and moves those files to organize them in folders by date.

Finally, a third script pushes the renamed files to s3 (this script should be easy to use another copy method like ftp, scp or rsync)
