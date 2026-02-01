#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_URL:?Missing STREAM_URL}"
: "${STREAM_KEY:?Missing STREAM_KEY}"

TEXT_FILE="numbers.txt"
echo "starting..." > "$TEXT_FILE"

# Update the text file with random numbers forever (until the job is killed).
(
  while true; do
    printf "Random: %s %s %s %s %s %s\nTime: %s\n" \
      "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" \
      "$(date -u +"%Y-%m-%d %H:%M:%S UTC")" > "$TEXT_FILE"
    sleep 0.1
  done
) &

# Stream a generated background + the text overlay.
ffmpeg -hide_banner -loglevel warning \
  -f lavfi -i "color=size=1280x720:rate=30:color=black" \
  -vf "drawtext=fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:textfile=${TEXT_FILE}:reload=1" \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -g 60 -b:v 2500k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "${STREAM_URL}/${STREAM_KEY}"
