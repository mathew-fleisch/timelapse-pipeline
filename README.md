# Timelapse Pipeline

This project has tools and scripts to set up timelapse pipelines using Raspberry Pi + camera to capture stills, and ffmpeg to generate timelapse videos. The goal of this project is completely automate the process to generate, edit and upload videos. The repository assumes you have a raspberry pi + camera, and an external post-processing computer (linux) to store and process videos daily. 

### Installation

todo (write installation instructions and script)

### Pipeline

***On the Raspberry Pi***

Images are captured at 1fps via the raspistill command line trigger, and saved to a local staging directory. Another script pushes those images to a long term storage solution, like s3, or directly to the post-processing computer.
 - [scripts/pi/start-timelapse.sh](scripts/pi/start-timelapse.sh)
    - raspistill saves one picture every second to a holding directory
 - `[TODO]` scripts/pi/clean-up-save.sh
    - use rsync/awscli/scp to copy all staged images to the long term storage solution
    - Stores images using the following naming convention:<br />
 `[LONG-TERM-STORAGE-URL]/<camera-name>/<yyyy>/<mm>/<dd>/<yyyy_mm_dd_hh>/yyyy_mm_dd_hh_mm_ss.jpg`

***On the post-processing computer***

The Raspberry Pi doesn't have enough processing power to run ffmpeg and takes pictures, so post-processing is expected to be run elsewhere. Images are copied to the post-processing computer, and ffmpeg creates an mp4 after flash frames are removed; occasionally the camera's auto-white-balance will flicker/flash and are removed by an optional flag. 
 - `[TODO]` scripts/processor/stage-images.sh
    - Get images from long term storage solution
 - [scripts/processor/timelapse.sh](scripts/processor/timelapse.sh)
    - Copy the staged images into one directory, and ffmpeg them into an mp4
    - Can optionally remove flashes via gap detection
 - [scripts/processor/get-music.sh](scripts/processor/get-music.sh)
    - Queries/scrapes internet for mp3 files
 - [scripts/processor/merge-audio-video.sh](scripts/processor/merge-audio-video.sh)
    - Speeds up video to length of audio file, then merges them together
 - `[TODO]` scripts/processor/upload-to-youtube.sh
    - Requires api key, oauth tokens, and username/password to authenticate and upload
    - Pipe in metadata about mp3 into description
