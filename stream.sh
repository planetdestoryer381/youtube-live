#!/usr/bin/env bash
set -euo pipefail

# =========================
# 🔑 YOUR STREAM KEY
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"

# =========================
# 🎬 VERTICAL SHORTS SETTINGS
# =========================
export FPS=20
export W=1080
export H=1920

# Game / physics defaults (tweak later if you want)
export BALL_R=10
export RING_R=200
export HOLE_DEG=70
export SPIN=0.9
export SPEED=100
export PHYS_MULT=3
export WIN_SCREEN_SECONDS=6
export RESTART_SECONDS=21000

export RING_THICKNESS=4
export RING_HOLE_EDGE=1

# Flags
export COUNTRIES_PATH="./countries.json"
export FLAG_SIZE=26
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

YOUTUBE_URL="rtmps://a.rtmps.youtube.com/live2/${YT_STREAM_KEY}"

echo "=== YOUTUBE SHORTS STREAM ==="
echo "Resolution: ${W}x${H}  FPS=${FPS}"
echo "URL: $YOUTUBE_URL"
node -v
ffmpeg -version | head -n 2
echo "============================"

# --------------------------------------------------
# Download flags (same as your original, kept)
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

echo "[flags] preparing from $COUNTRIES_PATH ..."
ISO_LIST="$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' "$COUNTRIES_PATH" \
  | sed -E 's/.*"([a-zA-Z]{2})".*/\1/' \
  | tr 'A-Z' 'a-z' | sort -u)"

COUNT=0
for iso in $ISO_LIST; do
  download_flag "$iso" "$FLAG_SIZE" || true
  COUNT=$((COUNT+1))
done
echo "[flags] prepared (iso2 unique): $COUNT"

# --------------------------------------------------
# WRITE THE GAME ENGINE (CLEAN YOUTUBE ONLY)
# --------------------------------------------------
cat > /tmp/yt_sim.js <<'JS'
'use strict';
const fs = require('fs');

process.stdout.on("error", (e) => {
  if (e && e.code === "EPIPE") {
    console.error("[pipe] ffmpeg closed stdin — exiting");
    process.exit(0);
  }
});

const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 1080;
const H   = +process.env.H   || 1920;

const R        = +process.env.BALL_R || 10;
const RING_R   = +process.env.RING_R || 200;
const HOLE_DEG = +process.env.HOLE_DEG || 70;
const SPIN     = +process.env.SPIN || 0.9;
const SPEED    = +process.env.SPEED || 100;
const PHYS_MULT = +process.env.PHYS_MULT || 3;
const WIN_SECONDS = +process.env.WIN_SCREEN_SECONDS || 6;

const COUNTRIES_PATH = process.env.COUNTRIES_PATH || "./countries.json";
const FLAGS_DIR = process.env.FLAGS_DIR || "/tmp/flags";
const FLAG_SIZE = +process.env.FLAG_SIZE || 26;

const CX = W*0.5, CY = H*0.5;
const dt = PHYS_MULT / FPS;

// framebuffer
const rgb = Buffer.alloc(W*H*3);
function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
}
function fillSolid(r,g,b){
  for(let i=0;i<rgb.length;i+=3){
    rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
  }
}
function clearBG(){ fillSolid(10,14,28); }

// simple text renderer (kept from your original)
const FONT={
  'A':[0b01110,0b10001,0b10001,0b11111,0b10001,0b10001,0b10001],
  'B':[0b11110,0b10001,0b11110,0b10001,0b10001,0b10001,0b11110],
  ' ':[0,0,0,0,0,0,0],
};
function drawChar(ch,x,y,scale,color){
  const rows = FONT[ch] || FONT['A'];
  const [r,g,b]=color;
  for(let rr=0; rr<7; rr++){
    const bits=rows[rr];
    for(let cc=0; cc<5; cc++){
      if(bits & (1<<(4-cc))){
        for(let sy=0; sy<scale; sy++)
          for(let sx=0; sx<scale; sx++)
            setPix(x+cc*scale+sx, y+rr*scale+sy, r,g,b);
      }
    }
  }
}
function drawText(text,x,y,scale,color){
  text=String(text).toUpperCase();
  let cx=x|0;
  for(let i=0;i<text.length;i++){
    drawChar(text[i], cx, y|0, scale, color);
    cx += (5*scale + scale);
  }
}

// load countries
function loadCountries(){
  const raw=fs.readFileSync(COUNTRIES_PATH,"utf8");
  const arr=JSON.parse(raw);
  const seen=new Set();
  const out=[];
  for(const c of arr){
    const name=String(c.name||"").trim();
    const iso2=String(c.iso2||"").trim().toLowerCase();
    if(!name||iso2.length!==2) continue;
    if(seen.has(iso2)) continue;
    seen.add(iso2);
    out.push({name,iso2});
  }
  return out;
}
const COUNTRIES=loadCountries();
console.error(`[countries] loaded ${COUNTRIES.length}`);

function readRGB(path,size){
  try{
    const buf=fs.readFileSync(path);
    if(buf.length===size*size*3) return buf;
  }catch{}
  return null;
}
function flagRGB(iso2){
  return readRGB(`${FLAGS_DIR}/${iso2}_${FLAG_SIZE}.rgb`, FLAG_SIZE);
}

// game state
let entities=[], alive=[], aliveCount=0;
let state="PLAY";
let winner=null;

// init round
function startRound(){
  entities=[];
  alive=[];
  aliveCount=0;

  for(const c of COUNTRIES){
    entities.push({
      name:c.name,
      iso2:c.iso2,
      imageBuf: flagRGB(c.iso2),
      x:CX, y:CY,
      vx:(Math.random()-0.5)*SPEED,
      vy:(Math.random()-0.5)*SPEED
    });
    alive.push(true);
  }
  aliveCount = entities.length;
  state="PLAY";
  console.error("[round] started");
}
startRound();

// draw ball
const mask=[];
for(let y=-R;y<=R;y++)
  for(let x=-R;x<=R;x++)
    if(x*x+y*y<=R*R) mask.push([x,y]);

function drawBall(x,y){
  for(const [dx,dy] of mask){
    setPix(x+dx,y+dy,120,160,255);
  }
}

// draw frame
function render(){
  clearBG();
  drawText("YOUTUBE SHORTS LIVE", 50, 50, 2, [255,255,255]);

  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    drawBall(entities[i].x|0, entities[i].y|0);
  }
}

// physics
function stepPhysics(){
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;

    if(b.x<R || b.x>W-R){ b.vx*=-1; }
    if(b.y<R || b.y>H-R){ b.vy*=-1; }
  }
}

// main loop
const headerBuf=Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf=Buffer.alloc(headerBuf.length + rgb.length);

function writeFrame(){
  headerBuf.copy(frameBuf,0);
  rgb.copy(frameBuf,headerBuf.length);
  process.stdout.write(frameBuf);
}

setInterval(()=>{
  if(state==="PLAY"){
    stepPhysics();
    render();
  }
  writeFrame();
}, Math.round(1000/FPS));

JS

node -c /tmp/yt_sim.js
echo "[sim] syntax OK"

# --------------------------------------------------
# RUN STREAM (YOUTUBE ONLY)
# --------------------------------------------------
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel info -stats \
    -thread_queue_size 1024 \
    -f image2pipe -vcodec ppm -r "$FPS" -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -map 0:v -map 1:a \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -pix_fmt yuv420p \
    -g $((FPS*2)) \
    -b:v 1800k -maxrate 1800k -bufsize 3600k \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$YOUTUBE_URL"

  echo "[youtube] stream stopped — retrying in 3 seconds..."
  sleep 3
done