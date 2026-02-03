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

# Balls 2.5x bigger (Original 10 -> 25)
export BALL_R=25
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
export FLAG_SIZE=50
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

YOUTUBE_URL="rtmps://a.rtmps.youtube.com/live2/${YT_STREAM_KEY}"

echo "=== YOUTUBE SHORTS STREAM ==="
echo "Resolution: ${W}x${H}  FPS=${FPS}"

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

# Download both normal size and 3x win size
echo "[flags] preparing..."
ISO_LIST="$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' "$COUNTRIES_PATH" | sed -E 's/.*"([a-zA-Z]{2})".*/\1/' | tr 'A-Z' 'a-z' | sort -u)"

for iso in $ISO_LIST; do
  download_flag "$iso" "$FLAG_SIZE" || true
  download_flag "$iso" "150" || true # 3x size for win screen
done

# --------------------------------------------------
# GAME ENGINE
# --------------------------------------------------
cat > /tmp/yt_sim.js <<'JS'
'use strict';
const fs = require('fs');

const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 1080;
const H   = +process.env.H   || 1920;
const R   = +process.env.BALL_R || 25;
const RING_R = +process.env.RING_R || 200;
const HOLE_DEG = +process.env.HOLE_DEG || 70;
const SPIN = +process.env.SPIN || 0.9;
const SPEED = +process.env.SPEED || 100;
const PHYS_MULT = +process.env.PHYS_MULT || 3;
const WIN_SECONDS = +process.env.WIN_SCREEN_SECONDS || 6;
const FLAG_SIZE = +process.env.FLAG_SIZE || 50;
const FLAGS_DIR = process.env.FLAGS_DIR || "/tmp/flags";
const COUNTRIES_PATH = process.env.COUNTRIES_PATH || "./countries.json";

const CX = W * 0.5, CY = H * 0.5;
const dt = PHYS_MULT / FPS;
const rgb = Buffer.alloc(W * H * 3);

function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
}

const FONT={'A':[14,17,17,31,17,17,17],'E':[31,16,30,16,16,16,31],'I':[14,4,4,4,4,4,14],'L':[16,16,16,16,16,16,31],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],':':[0,4,0,0,4,0,0],'.':[0,0,0,0,0,0,4]};
function drawText(text,x,y,scale,color){
  text=String(text).toUpperCase();
  let curX=x;
  for(let i=0;i<text.length;i++){
    const rows=FONT[text[i]]||FONT['A'];
    for(let r=0;r<7;r++){
      for(let c=0;c<5;c++){
        if(rows[r]&(1<<(4-c))){
          for(let sy=0;sy<scale;sy++) for(let sx=0;sx<scale;sx++) setPix(curX+c*scale+sx,y+r*scale+sy,color[0],color[1],color[2]);
        }
      }
    }
    curX+=6*scale;
  }
}
function textWidth(text,scale){ return text.length*6*scale; }

function blitSprite(cx,cy,radius,spriteBuf,spriteSize){
  if(!spriteBuf) return;
  const x0=(cx-spriteSize/2)|0, y0=(cy-spriteSize/2)|0;
  for(let sy=0;sy<spriteSize;sy++){
    for(let sx=0;sx<spriteSize;sx++){
      const dx=x0+sx-cx, dy=y0+sy-cy;
      if(dx*dx+dy*dy > radius*radius) continue;
      const si=(sy*spriteSize+sx)*3;
      setPix(x0+sx,y0+sy,spriteBuf[si],spriteBuf[si+1],spriteBuf[si+2]);
    }
  }
}

function drawUI(aliveCount, total, lastWinner){
  const s = 3; 
  const lineH = 7*s + 15;
  const textY = (CY - RING_R - 180) | 0;
  const labels = [`ALIVE: ${aliveCount}/${total}`, `LAST WIN: ${lastWinner}`, `TYPE ME IN CHAT TO ENTER` ];
  labels.forEach((txt, i) => {
    const w = textWidth(txt, s);
    const x = (CX - w/2) | 0;
    drawText(txt, x+2, textY + i*lineH + 2, s, [0,0,0]);
    drawText(txt, x, textY + i*lineH, s, [255,255,255]);
  });
}

function drawRing(holeCenterDeg){
  for(let deg=0; deg<360; deg+=0.4){
    let d=(deg-holeCenterDeg+180)%360-180;
    if(Math.abs(d) <= HOLE_DEG/2) continue;
    const a=deg*Math.PI/180;
    for(let r=RING_R-4; r<=RING_R+4; r++){
      setPix((CX+Math.cos(a)*r)|0, (CY+Math.sin(a)*r)|0, 240,240,240);
    }
  }
}

let entities=[], alive=[], state="PLAY", t=0, winner=null, lastWinner="NONE";
const countries=JSON.parse(fs.readFileSync(COUNTRIES_PATH,"utf8"));

function startRound(){
  entities = countries.map(c => ({
    name: c.name,
    iso2: c.iso2.toLowerCase(),
    x: CX + (Math.random()-0.5)*100,
    y: CY + (Math.random()-0.5)*100,
    vx: (Math.random()-0.5)*SPEED*2,
    vy: (Math.random()-0.5)*SPEED*2,
    img: (() => { try{return fs.readFileSync(`${FLAGS_DIR}/${c.iso2.toLowerCase()}_${FLAG_SIZE}.rgb`)}catch{return null}})()
  }));
  alive = entities.map(()=>true);
  state="PLAY"; t=0;
}
startRound();

function tick(){
  for(let i=0;i<rgb.length;i++) rgb[i]=15; 
  
  if(state==="PLAY"){
    t += dt;
    const holeDeg = (t*SPIN*180/Math.PI)%360;
    entities.forEach((b, i) => {
      if(!alive[i]) return;
      b.x += b.vx*dt; b.y += b.vy*dt;
      const dx=b.x-CX, dy=b.y-CY, dist=Math.sqrt(dx*dx+dy*dy);
      if(dist > RING_R - R){
        const ang = (Math.atan2(dy,dx)*180/Math.PI+360)%360;
        let d=(ang-holeDeg+180)%360-180;
        if(Math.abs(d) <= HOLE_DEG/2) alive[i]=false;
        else {
          const nx=dx/dist, ny=dy/dist;
          const dot = b.vx*nx + b.vy*ny;
          b.vx -= 2*dot*nx; b.vy -= 2*dot*ny;
          b.x = CX + nx*(RING_R-R); b.y = CY + ny*(RING_R-R);
        }
      }
      blitSprite(b.x|0, b.y|0, R, b.img, FLAG_SIZE);
    });
    drawRing(holeDeg);
    drawUI(alive.filter(v=>v).length, entities.length, lastWinner);
    if(alive.filter(v=>v).length <= 1){
      winner = entities[alive.indexOf(true)];
      lastWinner = winner ? winner.name : "NONE";
      state="WIN"; t=0;
    }
  } else {
    t += 1/FPS;
    const winR = R * 3;
    const winFlag = (() => { try{return fs.readFileSync(`${FLAGS_DIR}/${winner.iso2}_150.rgb`)}catch{return null}})();
    const winText = "WE HAVE A WINNER!";
    drawText(winText, (CX-textWidth(winText,4)/2)|0, (CY-300)|0, 4, [255,255,255]);
    if(winner) {
       blitSprite(CX|0, CY|0, winR, winFlag, 150);
       drawText(winner.name, (CX-textWidth(winner.name,3)/2)|0, (CY+winR+40)|0, 3, [255,255,255]);
    }
    if(t > WIN_SECONDS) startRound();
  }
  process.stdout.write(`P6\n${W} ${H}\n255\n`);
  process.stdout.write(rgb);
}
setInterval(tick, 1000/FPS);
JS

# --------------------------------------------------
# RUN STREAM (FIXED FFmpeg Syntax for GitHub)
# --------------------------------------------------
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel info -y \
    -f image2pipe -vcodec ppm -r "$FPS" -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -pix_fmt yuv420p -g $((FPS*2)) -b:v 2500k \
    -c:a aac -b:a 128k \
    -f flv "$YOUTUBE_URL"
  echo "Stream stopped, retrying..."
  sleep 3
done
