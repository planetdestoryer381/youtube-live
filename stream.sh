#!/usr/bin/env bash
set -euo pipefail

# =========================
# REQUIRED
# =========================
: "${STREAM_KEY:?STREAM_KEY is missing}"

# =========================
# DEBUG INFO
# =========================
echo "========== DEBUG START =========="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "PWD: $(pwd)"
echo "STREAM_KEY length: ${#STREAM_KEY}"
echo "Node version:"
node -v
echo "FFmpeg version:"
ffmpeg -version | head -n 3
echo "================================="

# =========================
# SETTINGS (SAFE DEBUG)
# =========================
export FPS=15
export W=640
export H=360
export BALLS=120
export RING_R=130
export HOLE_DEG=80
export SPIN=1.0

# =========================
# SIMPLE FRAME GENERATOR
# (NO PHYSICS YET — ISOLATION)
# =========================
cat > /tmp/sim.js <<'JS'
const W = parseInt(process.env.W);
const H = parseInt(process.env.H);
let frame = 0;

function writeFrame() {
  const buf = Buffer.alloc(W * H * 3, 255); // white frame
  const t = frame % W;

  // draw a moving black vertical bar
  for (let y = 0; y < H; y++) {
    const idx = (y * W + t) * 3;
    buf[idx] = 0;
    buf[idx+1] = 0;
    buf[idx+2] = 0;
  }

  process.stdout.write(`P6\n${W} ${H}\n255\n`);
  process.stdout.write(buf);
  frame++;
}

setInterval(writeFrame, 1000 / parseInt(process.env.FPS));
JS

echo "=== DEBUG: Starting Node frame generator ==="

# =========================
# PIPE → FFMPEG → TWITCH
# =========================
set -x

node /tmp/sim.js | ffmpeg -loglevel info \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -g 60 -b:v 2000k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmps://live.twitch.tv/app/${STREAM_KEY}"
