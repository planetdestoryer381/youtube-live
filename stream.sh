#!/usr/bin/env bash
set -euo pipefail

# =========================
# 🔑 STREAM CONFIG
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"

# YouTube Shorts Dimensions
export FPS=20
export W=1080
export H=1920

# Physics & Sizes
export BALL_R=25          
export RING_R=350         
export HOLE_DEG=70
export SPIN=0.9
export SPEED=120
export PHYS_MULT=3
export WIN_SCREEN_SECONDS=6

# Flags
export COUNTRIES_PATH="./countries.json"
export FLAG_SIZE=50
export WIN_FLAG_SIZE=150
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

YOUTUBE_URL="rtmps://a.rtmps.youtube.com/live2/${YT_STREAM_KEY}"

# --------------------------------------------------
# 🚩 Download & Process Flags
# --------------------------------------------------
download_flag () {
  local iso="$1"
  local size="$2"
  local out_rgb="$FLAGS_DIR/${iso}_${size}.rgb"
  if [ -s "$out_rgb" ]; then return 0; fi

  local png="$FLAGS_DIR/${iso}.png"
  if [ ! -s "$png" ]; then
    curl -fsSL "https://flagcdn.com/w80/${iso}.png" -o "$png" || return 0
  fi

  ffmpeg -hide_banner -loglevel error -y \
    -i "$png" \
    -vf "scale=${size}:${size}:flags=lanczos" \
    -f rawvideo -pix_fmt rgb24 "$out_rgb" >/dev/null 2>&1 || true
}

echo "--- Preparing Flags ---"
ISO_LIST="$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' "$COUNTRIES_PATH" | sed -E 's/.*"([a-zA-Z]{2})".*/\1/' | tr 'A-Z' 'a-z' | sort -u)"

for iso in $ISO_LIST; do
  download_flag "$iso" "$FLAG_SIZE"
  download_flag "$iso" "$WIN_FLAG_SIZE"
done

# --------------------------------------------------
# 🎮 Game Engine (yt_sim.js)
# --------------------------------------------------
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');

const W = 1080, H = 1920, FPS = 20;
const R = 25, RING_R = 350, HOLE_DEG = 70;
const SPIN = 0.9, SPEED = 120, DT = 3/20;
const CX = W/2, CY = H/2;
const FLAGS_DIR = "/tmp/flags";
const rgb = Buffer.alloc(W * H * 3);

function setPix(x, y, r, g, b) {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const i = (Math.floor(y) * W + Math.floor(x)) * 3;
    rgb[i] = r; rgb[i+1] = g; rgb[i+2] = b;
}

const FONT={'A':[14,17,17,31,17,17,17],'E':[31,16,30,16,16,16,31],'I':[14,4,4,4,4,4,14],'L':[16,16,16,16,16,16,31],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],':':[0,4,0,0,4,0,0]};

function drawText(text, x, y, scale, color) {
    let curX = x;
    for (let char of text.toUpperCase()) {
        const rows = FONT[char] || FONT[' '];
        for (let r = 0; r < 7; r++) {
            for (let c = 0; c < 5; c++) {
                if (rows[r] & (1 << (4 - c))) {
                    for (let sy = 0; sy < scale; sy++)
                        for (let sx = 0; sx < scale; sx++)
                            setPix(curX + c * scale + sx, y + r * scale + sy, ...color);
                }
            }
        }
        curX += 6 * scale;
    }
}

function blitFlag(cx, cy, radius, iso, size) {
    try {
        const buf = fs.readFileSync(`${FLAGS_DIR}/${iso}_${size}.rgb`);
        const x0 = Math.floor(cx - size/2), y0 = Math.floor(cy - size/2);
        for (let sy = 0; sy < size; sy++) {
            for (let sx = 0; sx < size; sx++) {
                const dx = x0 + sx - cx, dy = y0 + sy - cy;
                if (dx*dx + dy*dy > radius*radius) continue;
                const si = (sy * size + sx) * 3;
                setPix(x0 + sx, y0 + sy, buf[si], buf[si+1], buf[si+2]);
            }
        }
    } catch(e) {}
}

let entities = [], lastWinner = "NONE", winnerIso = "un", state = "PLAY", timer = 0;
const countries = JSON.parse(fs.readFileSync("./countries.json", "utf8")).slice(0, 45);

function init() {
    entities = countries.map(c => ({
        name: c.name, iso: c.iso2.toLowerCase(),
        x: CX + (Math.random()-0.5)*150, y: CY + (Math.random()-0.5)*150,
        vx: (Math.random()-0.5)*SPEED, vy: (Math.random()-0.5)*SPEED, alive: true
    }));
    state = "PLAY";
}

function loop() {
    rgb.fill(15); 
    const holeDeg = (Date.now()/1000 * SPIN * 60) % 360;

    if (state === "PLAY") {
        let aliveList = entities.filter(e => e.alive);
        drawText(`ALIVE: ${aliveList.length}/${entities.length}`, CX - 180, CY - RING_R - 120, 3, [255,255,255]);
        drawText(`LAST WINNER: ${lastWinner}`, CX - 180, CY - RING_R - 70, 2, [180,180,180]);

        for (let a = 0; a < 360; a += 0.5) {
            let diff = Math.abs(((a - holeDeg + 180) % 360) - 180);
            if (diff < HOLE_DEG/2) continue;
            const rad = a * Math.PI / 180;
            for(let th=0; th<6; th++) setPix(CX+(RING_R+th)*Math.cos(rad), CY+(RING_R+th)*Math.sin(rad), 240, 240, 240);
        }

        entities.forEach(e => {
            if (!e.alive) return;
            e.x += e.vx * DT; e.y += e.vy * DT;
            const dx = e.x - CX, dy = e.y - CY, dist = Math.sqrt(dx*dx + dy*dy);
            if (dist > RING_R - R) {
                const ang = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360;
                let diff = Math.abs(((ang - holeDeg + 180) % 360) - 180);
                if (diff < HOLE_DEG/2) e.alive = false;
                else {
                    const nx = dx/dist, ny = dy/dist;
                    const dot = e.vx*nx + e.vy*ny;
                    e.vx -= 2*dot*nx; e.vy -= 2*dot*ny;
                    e.x = CX + nx*(RING_R-R); e.y = CY + ny*(RING_R-R);
                }
            }
            blitFlag(e.x, e.y, R, e.iso, 50);
        });

        if (aliveList.length <= 1) {
            lastWinner = aliveList[0] ? aliveList[0].name : "NONE";
            winnerIso = aliveList[0] ? aliveList[0].iso : "un";
            state = "WIN"; timer = 0;
        }
    } else {
        drawText("WINNER", CX - 100, CY - 280, 5, [255, 255, 0]);
        drawText(lastWinner, CX - (lastWinner.length*12), CY + 180, 4, [255, 255, 255]);
        blitFlag(CX, CY, 75, winnerIso, 150); 
        if (++timer > 6 * FPS) init();
    }

    process.stdout.write(`P6\n${W} ${H}\n255\n`);
    process.stdout.write(rgb);
}

init();
setInterval(loop, 1000/FPS);
JS

# --------------------------------------------------
# 🚀 STREAM COMMAND
# --------------------------------------------------
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel info -y \
    -f image2pipe -vcodec ppm -r "$FPS" -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -map 0:v -map 1:a \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -g $((FPS*2)) -b:v 3000k -maxrate 3000k -bufsize 6000k \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$YOUTUBE_URL"
  
  echo "Stream crashed. Restarting..."
  sleep 5
done
