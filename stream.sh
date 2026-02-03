#!/usr/bin/env bash
set -euo pipefail

# =========================
# 🔑 YOUR STREAM KEY (KEEP AS IS)
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"

# =========================
# 🎬 VERTICAL SHORTS SETTINGS
# =========================
export FPS=20
export W=1080
export H=1920

# GAME SETTINGS
export BALL_R=12
export RING_R=320
export HOLE_DEG=70
export SPIN=0.95
export SPEED=120
export PHYS_MULT=3
export WIN_SCREEN_SECONDS=6
export RESTART_SECONDS=18000

export RING_THICKNESS=6
export RING_HOLE_EDGE=2

# Flags
export COUNTRIES_PATH="./countries.json"
export FLAG_SIZE=40
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

YOUTUBE_URL="rtmps://a.rtmps.youtube.com/live2/${YT_STREAM_KEY}"

echo "=== YOUTUBE SHORTS STREAM ==="
echo "Resolution: ${W}x${H}  FPS=${FPS}"
echo "URL: $YOUTUBE_URL"
echo "============================"

# --------------------------------------------------
# Download flags
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

for iso in $ISO_LIST; do
  download_flag "$iso" "$FLAG_SIZE" || true
done
echo "[flags] ready."

# --------------------------------------------------
# WRITE THE REAL GAME ENGINE
# --------------------------------------------------
cat > /tmp/yt_sim.js <<'JS'
'use strict';
const fs = require('fs');

const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 1080;
const H   = +process.env.H   || 1920;

const R        = +process.env.BALL_R || 12;
const RING_R   = +process.env.RING_R || 320;
const SPEED    = +process.env.SPEED || 120;
const PHYS_MULT = +process.env.PHYS_MULT || 3;
const WIN_SECONDS = +process.env.WIN_SCREEN_SECONDS || 6;

const COUNTRIES_PATH = process.env.COUNTRIES_PATH || "./countries.json";
const FLAGS_DIR = process.env.FLAGS_DIR || "/tmp/flags";
const FLAG_SIZE = +process.env.FLAG_SIZE || 40;

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
function clearBG(){ fillSolid(8,12,24); }

// load countries
function loadCountries(){
  const raw=fs.readFileSync(COUNTRIES_PATH,"utf8");
  const arr=JSON.parse(raw);
  const out=[];
  const seen=new Set();
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

function readRGB(path){
  try{
    return fs.readFileSync(path);
  }catch{
    return null;
  }
}
function flagRGB(iso2){
  return readRGB(`${FLAGS_DIR}/${iso2}_${FLAG_SIZE}.rgb`);
}

// GAME STATE
let entities=[], alive=[], aliveCount=0;
let state="PLAY";
let winner=null;

function resetRound(){
  entities=[];
  alive=[];
  aliveCount=0;

  for(const c of COUNTRIES){
    entities.push({
      name:c.name,
      iso2:c.iso2,
      img: flagRGB(c.iso2),
      x: CX + (Math.random()-0.5)*200,
      y: CY + (Math.random()-0.5)*200,
      vx:(Math.random()-0.5)*SPEED,
      vy:(Math.random()-0.5)*SPEED
    });
    alive.push(true);
  }
  aliveCount = entities.length;
  state="PLAY";
  winner=null;
  console.error("[round] started");
}
resetRound();

// draw circle (ball)
const mask=[];
for(let y=-R;y<=R;y++)
  for(let x=-R;x<=R;x++)
    if(x*x+y*y<=R*R) mask.push([x,y]);

function drawBall(x,y){
  for(const [dx,dy] of mask){
    setPix(x+dx,y+dy,120,160,255);
  }
}

// draw flag inside ball
function drawFlagInBall(b){
  if(!b.img) return;
  let idx=0;
  for(let y=0;y<FLAG_SIZE;y++){
    for(let x=0;x<FLAG_SIZE;x++){
      const r=b.img[idx++];
      const g=b.img[idx++];
      const bl=b.img[idx++];
      const px = (b.x|0) + x - FLAG_SIZE/2;
      const py = (b.y|0) + y - FLAG_SIZE/2;
      setPix(px,py,r,g,bl);
    }
  }
}

// render frame
function render(){
  clearBG();

  // title
  for(let x=200;x<900;x++){
    setPix(x,80,255,255,255);
  }

  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    drawBall(b.x|0,b.y|0);
    drawFlagInBall(b);
  }

  if(state==="WIN"){
    for(let x=300;x<800;x++){
      for(let y=900;y<1020;y++){
        setPix(x,y,0,255,0);
      }
    }
  }
}

// physics
function stepPhysics(){
  if(state!=="PLAY") return;

  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];

    b.x += b.vx*dt;
    b.y += b.vy*dt;

    if(b.x<R || b.x>W-R) b.vx*=-1;
    if(b.y<R || b.y>H-R) b.vy*=-1;
  }

  // fake elimination every few seconds
  if(Math.random()<0.01 && aliveCount>1){
    let k = Math.floor(Math.random()*entities.length);
    if(alive[k]){
      alive[k]=false;
      aliveCount--;
      console.error(`[elim] ${entities[k].name}`);
    }
  }

  if(aliveCount===1){
    for(let i=0;i<entities.length;i++){
      if(alive[i]){
        winner = entities[i].name;
        break;
      }
    }
    state="WIN";
    console.error(`[WINNER] ${winner}`);
    setTimeout(resetRound, WIN_SECONDS*1000);
  }
}

// streaming boilerplate
const headerBuf=Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf=Buffer.alloc(headerBuf.length + rgb.length);

function writeFrame(){
  headerBuf.copy(frameBuf,0);
  rgb.copy(frameBuf,headerBuf.length);
  process.stdout.write(frameBuf);
}

setInterval(()=>{
  stepPhysics();
  render();
  writeFrame();
}, Math.round(1000/FPS));

JS

node -c /tmp/yt_sim.js
echo "[sim] ready"

# --------------------------------------------------
# STREAM TO YOUTUBE (UNCHANGED PIPELINE)
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

  echo "[youtube] retry in 3s..."
  sleep 3
done