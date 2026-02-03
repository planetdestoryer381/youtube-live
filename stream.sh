#!/usr/bin/env bash
set -euo pipefail

# =========================
# 🔑 CONFIG
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"
export FPS=20
export W=1080
export H=1920

# Physics Tuning
export BALL_R=25          
export RING_R=350         
export HOLE_DEG=70
export SPIN=1.1            # Slightly faster spin
export BASE_SPEED=130      # Speed the balls want to maintain
export BOUNCE_BOOST=1.1    # 10% speed gain when hitting a wall
export RESTART_SECONDS=21000

# Flags
export COUNTRIES_PATH="./countries.json"
export FLAG_SIZE=50
export WIN_FLAG_SIZE=150
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

YOUTUBE_URL="rtmps://a.rtmps.youtube.com/live2/${YT_STREAM_KEY}"

# --- Flag Preparation ---
download_flag () {
  local iso="$1"
  local size="$2"
  local out_rgb="$FLAGS_DIR/${iso}_${size}.rgb"
  if [ -s "$out_rgb" ]; then return 0; fi
  local png="$FLAGS_DIR/${iso}.png"
  if [ ! -s "$png" ]; then
    curl -fsSL "https://flagcdn.com/w80/${iso}.png" -o "$png" || return 0
  fi
  ffmpeg -hide_banner -loglevel error -y -i "$png" -vf "scale=${size}:${size}:flags=lanczos" -f rawvideo -pix_fmt rgb24 "$out_rgb" >/dev/null 2>&1 || true
}

echo "--- Preparing Flags ---"
ISO_LIST="$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' "$COUNTRIES_PATH" | sed -E 's/.*"([a-zA-Z]{2})".*/\1/' | tr 'A-Z' 'a-z' | sort -u)"
for iso in $ISO_LIST; do
  download_flag "$iso" "$FLAG_SIZE"
  download_flag "$iso" "$WIN_FLAG_SIZE"
done

# --- Node.js Engine ---
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');

const W = 1080, H = 1920, FPS = 20;
const R = 25, RING_R = 350, HOLE_DEG = 70;
const SPIN = 1.1, DT = 1/FPS;
const CX = W/2, CY = H/2;
const FLAGS_DIR = "/tmp/flags";
const RESTART_TOTAL = +process.env.RESTART_SECONDS || 21000;
const START_TIME = Date.now();

const rgb = Buffer.alloc(W * H * 3);
function setPix(x, y, r, g, b) {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const i = (Math.floor(y) * W + Math.floor(x)) * 3;
    rgb[i] = r; rgb[i+1] = g; rgb[i+2] = b;
}

const FONT={'A':[14,17,17,31,17,17,17],'B':[30,17,30,17,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],'E':[31,16,30,16,16,16,31],'F':[31,16,30,16,16,16,16],'G':[14,17,16,23,17,17,14],'H':[17,17,17,31,17,17,17],'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],'M':[17,27,21,17,17,17,17],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'X':[17,17,10,4,10,17,17],'Y':[17,17,10,4,4,4,4],'Z':[31,1,2,4,8,16,31],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],':':[0,4,0,0,4,0,0],'-':[0,0,0,31,0,0,0]};

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

let entities = [], lastWinner = "NONE", winnerIso = "un", state = "PLAY", winTimer = 0;
const countries = JSON.parse(fs.readFileSync("./countries.json", "utf8"));

function init() {
    entities = countries.slice(0, 40).map(c => ({
        name: c.name, iso: c.iso2.toLowerCase(),
        x: CX + (Math.random()-0.5)*100, y: CY + (Math.random()-0.5)*100,
        vx: (Math.random()-0.5)*200, vy: (Math.random()-0.5)*200, alive: true
    }));
    state = "PLAY";
}

function loop() {
    rgb.fill(10); 
    const holeDeg = (Date.now()/1000 * SPIN * 60) % 360;

    if (state === "PLAY") {
        let aliveList = entities.filter(e => e.alive);
        
        // --- 1 & 3: UI Restore ---
        const elapsed = Math.floor((Date.now() - START_TIME) / 1000);
        const remaining = Math.max(0, RESTART_TOTAL - elapsed);
        const h = Math.floor(remaining/3600), m = Math.floor((remaining%3600)/60), s = remaining%60;
        const timeStr = `RESTART IN: ${h}:${m}:${s}`;

        drawText(`ALIVE: ${aliveList.length}/${entities.length}`, CX - 180, CY - RING_R - 180, 3, [255,255,255]);
        drawText(`LAST WIN: ${lastWinner}`, CX - 180, CY - RING_R - 130, 2, [180,180,180]);
        drawText(timeStr, CX - 180, CY - RING_R - 90, 2, [150,255,150]);
        drawText("TYPE ME IN CHAT TO ENTER", CX - 220, CY + RING_R + 50, 2, [255,200,0]);

        // Ring
        for (let a = 0; a < 360; a += 0.5) {
            let diff = Math.abs(((a - holeDeg + 180) % 360) - 180);
            if (diff < HOLE_DEG/2) continue;
            const rad = a * Math.PI / 180;
            for(let th=0; th<8; th++) setPix(CX+(RING_R+th)*Math.cos(rad), CY+(RING_R+th)*Math.sin(rad), 255, 255, 255);
        }

        // --- 2: Collision & Realistic Physics ---
        for (let i = 0; i < entities.length; i++) {
            let a = entities[i];
            if (!a.alive) continue;

            // Ball-to-Ball Collision
            for (let j = i + 1; j < entities.length; j++) {
                let b = entities[j];
                if (!b.alive) continue;
                let dx = b.x - a.x, dy = b.y - a.y;
                let dist = Math.sqrt(dx*dx + dy*dy);
                if (dist < R * 2) {
                    // Collision logic
                    let nx = dx/dist, ny = dy/dist;
                    let p = (a.vx * nx + a.vy * ny - (b.vx * nx + b.vy * ny));
                    a.vx -= p * nx; a.vy -= p * ny;
                    b.vx += p * nx; b.vy += p * ny;
                    // Prevent sticking
                    let overlap = R * 2 - dist;
                    a.x -= nx * overlap / 2; a.y -= ny * overlap / 2;
                    b.x += nx * overlap / 2; b.y += ny * overlap / 2;
                }
            }

            // Wall Bounce + Speed Boost
            a.x += a.vx * DT; a.y += a.vy * DT;
            let dx = a.x - CX, dy = a.y - CY, dist = Math.sqrt(dx*dx + dy*dy);
            if (dist > RING_R - R) {
                const ang = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360;
                let diff = Math.abs(((ang - holeDeg + 180) % 360) - 180);
                if (diff < HOLE_DEG/2) a.alive = false;
                else {
                    const nx = dx/dist, ny = dy/dist;
                    const dot = a.vx*nx + a.vy*ny;
                    a.vx = (a.vx - 2*dot*nx) * 1.05; // Bounce boost
                    a.vy = (a.vy - 2*dot*ny) * 1.05;
                    a.x = CX + nx*(RING_R-R); a.y = CY + ny*(RING_R-R);
                }
            }
            blitFlag(a.x, a.y, R, a.iso, 50);
        }

        if (aliveList.length <= 1) {
            lastWinner = aliveList[0] ? aliveList[0].name : "NONE";
            winnerIso = aliveList[0] ? aliveList[0].iso : "un";
            state = "WIN"; winTimer = 0;
        }
    } else {
        drawText("WE HAVE A WINNER", CX - 250, CY - 250, 4, [255, 255, 0]);
        drawText(lastWinner, CX - (lastWinner.length*12), CY + 180, 4, [255, 255, 255]);
        blitFlag(CX, CY, 75, winnerIso, 150); 
        if (++winTimer > 6 * FPS) init();
    }

    try {
        process.stdout.write(`P6\n${W} ${H}\n255\n`);
        process.stdout.write(rgb);
    } catch (e) { process.exit(0); }
}

init();
setInterval(loop, 1000/FPS);
JS

# --- FFmpeg Execution ---
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel info -y \
    -f image2pipe -vcodec ppm -r "$FPS" -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -g $((FPS*2)) -b:v 3000k -maxrate 3000k -bufsize 6000k \
    -c:a aac -b:a 128k -f flv "$YOUTUBE_URL"
  sleep 5
done
