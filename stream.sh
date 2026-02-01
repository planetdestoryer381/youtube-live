#!/usr/bin/env bash
set -e

OUT_FILE="numbers.txt"
echo "starting..." > "$OUT_FILE"

# Update numbers forever (until GitHub kills the runner)
(
  while true; do
    echo "Random numbers:" > "$OUT_FILE"
    for i in {1..8}; do
      echo "$RANDOM  $RANDOM  $RANDOM" >> "$OUT_FILE"
    done
    echo "UTC: $(date -u +"%Y-%m-%d %H:%M:%S")" >> "$OUT_FILE"
    sleep 0.2
  done
) &

# Stream to Twitch
ffmpeg -hide_banner -loglevel warning \
  -f lavfi -i "color=size=1280x720:rate=30:color=black" \
  -vf "drawtext=textfile=${OUT_FILE}:reload=1:fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2" \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -c:v libx264 -preset veryfast -tune zerolatency \
  -pix_fmt yuv420p -g 60 -b:v 2500k \
  -c:a aac -b:a 128k \
  -f flv "rtmps://live.twitch.tv/app/${STREAM_KEY}"
