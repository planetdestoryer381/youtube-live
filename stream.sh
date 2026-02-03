#!/usr/bin/env bash
set -euo pipefail

# =========================
# 🔑 YOUR STREAM KEY
# =========================
: "${YT_STREAM_KEY:?Missing YT_STREAM_KEY}"
# example:
# export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"

# =========================
# 🎬 VERTICAL SHORTS SETTINGS
# =========================
export FPS="${FPS:-20}"
export W="${W:-1080}"
export H="${H:-1920}"

# Game / physics
export BALL_R="${BALL_R:-10}"
export RING_R="${RING_R:-200}"
export HOLE_DEG="${HOLE_DEG:-70}"
export SPIN="${SPIN:-0.9}"
export SPEED="${SPEED:-100}"
export PHYS_MULT="${PHYS_MULT:-3}"
export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-6}"
export RESTART_SECONDS="${RESTART_SECONDS:-21000}"

export RING_THICKNESS="${RING_THICKNESS:-4}"
export RING_HOLE_EDGE="${RING_HOLE_EDGE:-1}"

# Flags
export COUNTRIES_PATH="${COUNTRIES_PATH:-./countries.json}"
export FLAG_SIZE="${FLAG_SIZE:-26}"
export FLAGS_DIR="${FLAGS_DIR:-/tmp/flags}"
mkdir -p "$FLAGS_DIR"

YOUTUBE_URL="rtmps://a.rtmps.youtube.com/live2/${YT_STREAM_KEY}"

echo "=== YOUTUBE SHORTS STREAM (RING GAME) ==="
echo "Resolution: ${W}x${H}  FPS=${FPS}"
echo "URL: $YOUTUBE_URL"
node -v
ffmpeg -version | head -n 2
echo "========================================="

# --------------------------------------------------
# Download flags (same as your working example)
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
# WRITE THE GAME ENGINE (YOUTUBE ONLY)
# --------------------------------------------------
cat > /tmp/yt_ring_game.js <<'JS'
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
const RESTART_SECONDS = +process.env.RESTART_SECONDS || 21000;
const startMs = Date.now();

const RING_THICKNESS = +process.env.RING_THICKNESS || 4;
const RING_HOLE_EDGE = (+process.env.RING_HOLE_EDGE || 0) ? 1 : 0;

const COUNTRIES_PATH = process.env.COUNTRIES_PATH || "./countries.json";
const FLAGS_DIR = process.env.FLAGS_DIR || "/tmp/flags";
const FLAG_SIZE = +process.env.FLAG_SIZE || 26;

const CX = W * 0.5, CY = H * 0.5;
const dt = (PHYS_MULT) / FPS;

// framebuffer
const rgb = Buffer.alloc(W * H * 3);
function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
}
function fillSolid(r,g,b){
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b; }
}
function clearBG(){ fillSolid(10,14,28); }

// tiny font (same vibe as your original; expanded enough for UI)
const FONT={
'A':[0b01110,0b10001,0b10001,0b11111,0b10001,0b10001,0b10001],
'B':[0b11110,0b10001,0b11110,0b10001,0b10001,0b10001,0b11110],
'C':[0b01110,0b10001,0b10000,0b10000,0b10000,0b10001,0b01110],
'D':[0b11110,0b10001,0b10001,0b10001,0b10001,0b10001,0b11110],
'E':[0b11111,0b10000,0b11110,0b10000,0b10000,0b10000,0b11111],
'F':[0b11111,0b10000,0b11110,0b10000,0b10000,0b10000,0b10000],
'G':[0b01110,0b10001,0b10000,0b10111,0b10001,0b10001,0b01110],
'H':[0b10001,0b10001,0b11111,0b10001,0b10001,0b10001,0b10001],
'I':[0b01110,0b00100,0b00100,0b00100,0b00100,0b00100,0b01110],
'J':[0b00111,0b00010,0b00010,0b00010,0b10010,0b10010,0b01100],
'K':[0b10001,0b10010,0b11100,0b10010,0b10001,0b10001,0b10001],
'L':[0b10000,0b10000,0b10000,0b10000,0b10000,0b10000,0b11111],
'M':[0b10001,0b11011,0b10101,0b10101,0b10001,0b10001,0b10001],
'N':[0b10001,0b11001,0b10101,0b10011,0b10001,0b10001,0b10001],
'O':[0b01110,0b10001,0b10001,0b10001,0b10001,0b10001,0b01110],
'P':[0b11110,0b10001,0b10001,0b11110,0b10000,0b10000,0b10000],
'Q':[0b01110,0b10001,0b10001,0b10001,0b10101,0b10010,0b01101],
'R':[0b11110,0b10001,0b10001,0b11110,0b10010,0b10001,0b10001],
'S':[0b01111,0b10000,0b01110,0b00001,0b00001,0b10001,0b01110],
'T':[0b11111,0b00100,0b00100,0b00100,0b00100,0b00100,0b00100],
'U':[0b10001,0b10001,0b10001,0b10001,0b10001,0b10001,0b01110],
'V':[0b10001,0b10001,0b10001,0b10001,0b10001,0b01010,0b00100],
'W':[0b10001,0b10001,0b10001,0b10101,0b10101,0b11011,0b10001],
'X':[0b10001,0b01010,0b00100,0b00100,0b00100,0b01010,0b10001],
'Y':[0b10001,0b01010,0b00100,0b00100,0b00100,0b00100,0b00100],
'Z':[0b11111,0b00010,0b00100,0b01000,0b10000,0b10000,0b11111],
'0':[0b01110,0b10001,0b10011,0b10101,0b11001,0b10001,0b01110],
'1':[0b00100,0b01100,0b00100,0b00100,0b00100,0b00100,0b01110],
'2':[0b01110,0b10001,0b00001,0b00110,0b01000,0b10000,0b11111],
'3':[0b11110,0b00001,0b00001,0b01110,0b00001,0b00001,0b11110],
'4':[0b00010,0b00110,0b01010,0b10010,0b11111,0b00010,0b00010],
'5':[0b11111,0b10000,0b11110,0b00001,0b00001,0b10001,0b01110],
'6':[0b00110,0b01000,0b10000,0b11110,0b10001,0b10001,0b01110],
'7':[0b11111,0b00001,0b00010,0b00100,0b01000,0b01000,0b01000],
'8':[0b01110,0b10001,0b10001,0b01110,0b10001,0b10001,0b01110],
'9':[0b01110,0b10001,0b10001,0b01111,0b00001,0b00010,0b01100],
' ':[0,0,0,0,0,0,0],
':':[0,0b00100,0,0,0b00100,0,0],
'-':[0,0,0b11111,0,0,0,0],
'_':[0,0,0,0,0,0,0b11111],
'.':[0,0,0,0,0,0,0b00100],
};
function drawChar(ch,x,y,scale,color){
  const rows = FONT[ch] || FONT['?'] || FONT['A'];
  const [r,g,b]=color;
  for(let rr=0; rr<7; rr++){
    const bits=rows[rr] || 0;
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
function textWidth(text,scale){ return String(text).length*(5*scale+scale) - scale; }
function drawTextShadow(text,x,y,scale){
  drawText(text, x+1, y+1, scale, [0,0,0]);
  drawText(text, x, y, scale, [255,255,255]);
}

// sprites
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
function blitSpriteInCircle(centerX, centerY, radius, spriteBuf, spriteSize){
  if(!spriteBuf) return;
  const half=(spriteSize/2)|0;
  const x0=(centerX-half)|0;
  const y0=(centerY-half)|0;
  const r2=(radius-1)*(radius-1);
  for(let sy=0; sy<spriteSize; sy++){
    for(let sx=0; sx<spriteSize; sx++){
      const px=x0+sx, py=y0+sy;
      const dx=px-centerX, dy=py-centerY;
      if(dx*dx+dy*dy>r2) continue;
      const si=(sy*spriteSize+sx)*3;
      setPix(px,py,spriteBuf[si],spriteBuf[si+1],spriteBuf[si+2]);
    }
  }
}

// helpers
function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}
function normalizeSpeed(b, target){
  const v = Math.hypot(b.vx, b.vy);
  if(v < 1e-6){
    const a = Math.random()*Math.PI*2;
    b.vx = Math.cos(a)*target;
    b.vy = Math.sin(a)*target;
    return;
  }
  const s = target / v;
  b.vx *= s; b.vy *= s;
}

// countries
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
console.error(`[countries] loaded ${COUNTRIES.length} unique countries from ${COUNTRIES_PATH}`);

function fmtCountdown(sec){
  sec = Math.max(0, sec|0);
  const h = (sec/3600)|0;
  const m = ((sec%3600)/60)|0;
  const s = (sec%60)|0;
  return `RESTART IN ${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
}

// game state
let entities=[], alive=[], aliveCount=0;
let state="PLAY";
let t=0;
let winFrames=0;
let winner=null;
let lastWinner="none";

// masks for ball
const mask=[];
for(let y=-R;y<=R;y++) for(let x=-R;x<=R;x++) if(x*x+y*y<=R*R) mask.push([x,y]);

function drawBallBase(cx,cy,col){
  const x0=cx|0, y0=cy|0;
  const [r,g,b]=col;
  for(const [dx,dy] of mask) setPix(x0+dx,y0+dy,r,g,b);
}
function drawNameUnderBall(x,y,name){
  const label=String(name).toUpperCase().replace(/[^A-Z0-9_ .:-]/g,' ').trim().slice(0,16);
  const w=textWidth(label,1);
  drawTextShadow(label, (x-w/2)|0, (y+R+6)|0, 1);
}

// ring drawing (fast + clean)
function drawRing(holeCenterDeg){
  const thickness = Math.max(2, RING_THICKNESS);
  const inner = RING_R - thickness;
  const outer = RING_R + thickness;

  for(let deg=0; deg<360; deg+=0.35){
    if(inHole(deg, holeCenterDeg)) continue;
    const a = deg*Math.PI/180;
    const ca=Math.cos(a), sa=Math.sin(a);

    for(let rr=inner; rr<=outer; rr+=1){
      const x = (CX + ca*rr)|0;
      const y = (CY + sa*rr)|0;
      setPix(x,y,230,230,235);
    }
  }

  if(RING_HOLE_EDGE){
    const edgeA = holeCenterDeg - HOLE_DEG/2;
    const edgeB = holeCenterDeg + HOLE_DEG/2;
    for(const edge of [edgeA, edgeB]){
      const a=edge*Math.PI/180;
      const ca=Math.cos(a), sa=Math.sin(a);
      for(let rr=inner-6; rr<=outer+6; rr+=1){
        const x = (CX + ca*rr)|0;
        const y = (CY + sa*rr)|0;
        setPix(x,y,255,180,80);
      }
    }
  }
}

// UI
function drawTopUI(){
  const s = 2;
  const y = 12;
  const lineH = 7*s + 10;

  const aliveTxt = `ALIVE: ${aliveCount}/${entities.length}`;
  const lastTxt  = `LAST WIN: ${String(lastWinner).toUpperCase().slice(0,18)}`;
  drawTextShadow(aliveTxt, 14, y, s);
  drawTextShadow(lastTxt, 14, y + lineH, s);

  const elapsed = ((Date.now() - startMs)/1000)|0;
  const left = Math.max(0, RESTART_SECONDS - elapsed);
  drawTextShadow(fmtCountdown(left), 14, y + lineH*2, 2);
  drawTextShadow("TYPE ME IN CHAT TO ENTER", 14, y + lineH*3, 2);
}

// render
function clearAndUI(){
  clearBG();
  drawTopUI();
}
function drawEntity(e){
  const x=e.x|0, y=e.y|0;
  drawBallBase(x,y,[50,70,120]);
  if(e.imageBuf) blitSpriteInCircle(x,y,R,e.imageBuf,e.imageSize);
  drawNameUnderBall(x,y,e.name);
}
function renderPlay(holeCenterDeg){
  clearAndUI();
  drawRing(holeCenterDeg);
  for(let i=0;i<entities.length;i++){
    if(alive[i]) drawEntity(entities[i]);
  }
}
function renderWin(){
  fillSolid(8,10,18);
  const title = "WE HAVE A WINNER";
  drawTextShadow(title,(W/2-textWidth(title,4)/2)|0,(H/2-100)|0,4);

  if(winner){
    const iconX = (W/2)|0;
    const iconY = (H/2 - 10)|0;
    drawBallBase(iconX, iconY, [50,70,120]);
    if(winner.iso2){
      const buf = flagRGB(winner.iso2);
      if(buf) blitSpriteInCircle(iconX, iconY, R, buf, FLAG_SIZE);
    }
    const name = String(winner.name).toUpperCase().slice(0,20);
    drawTextShadow(name, (W/2 - (textWidth(name,2)/2))|0, (H/2 + 40)|0, 2);
  }
}

// init round
function startRound(){
  entities=[];
  alive=[];
  aliveCount=0;

  const innerR = Math.max(35, RING_R - R - 35);

  for(const c of COUNTRIES){
    const a=Math.random()*Math.PI*2;
    const rr=Math.random()*innerR;
    const dir=Math.random()*Math.PI*2;
    entities.push({
      type:"country",
      name:c.name,
      iso2:c.iso2,
      imageBuf: flagRGB(c.iso2),
      imageSize: FLAG_SIZE,
      x: CX + Math.cos(a)*rr,
      y: CY + Math.sin(a)*rr,
      vx: Math.cos(dir)*SPEED,
      vy: Math.sin(dir)*SPEED,
    });
    alive.push(true);
    aliveCount++;
  }

  winner=null;
  state="PLAY";
  t=0;
  winFrames=0;
  console.error(`[round] new round started (entities=${entities.length})`);
}
startRound();

function getWinnerIndex(){
  for(let i=0;i<entities.length;i++) if(alive[i]) return i;
  return -1;
}

function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;

  // move
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
  }

  // collisions
  const minD = 2*R;
  const minD2 = minD*minD;
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const A=entities[i];
    for(let j=i+1;j<entities.length;j++){
      if(!alive[j]) continue;
      const B=entities[j];
      const dx=B.x-A.x, dy=B.y-A.y;
      const d2=dx*dx+dy*dy;
      if(d2>0 && d2<minD2){
        const d=Math.sqrt(d2);
        const nx=dx/d, ny=dy/d;
        const overlap=minD-d;

        A.x -= nx*overlap*0.5; A.y -= ny*overlap*0.5;
        B.x += nx*overlap*0.5; B.y += ny*overlap*0.5;

        const van=A.vx*nx + A.vy*ny;
        const vbn=B.vx*nx + B.vy*ny;
        A.vx += (vbn-van)*nx; A.vy += (vbn-van)*ny;
        B.vx += (van-vbn)*nx; B.vy += (van-vbn)*ny;
      }
    }
  }

  // ring wall + hole
  const wallR = RING_R - R - 3;
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    const dx=b.x-CX, dy=b.y-CY;
    const dist=Math.sqrt(dx*dx+dy*dy) || 0.0001;
    const angDeg=(Math.atan2(dy,dx)*180/Math.PI+360)%360;

    if(dist>wallR){
      if(inHole(angDeg, holeCenterDeg)){
        alive[i]=false; aliveCount--;
        continue;
      }
      const nx=dx/dist, ny=dy/dist;
      b.x = CX + nx*wallR;
      b.y = CY + ny*wallR;

      const vn=b.vx*nx + b.vy*ny;
      b.vx -= 2*vn*nx;
      b.vy -= 2*vn*ny;
    }
  }

  // normalize speed
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    normalizeSpeed(entities[i], SPEED);
  }

  return holeCenterDeg;
}

function tick(){
  if(state==="PLAY"){
    const holeCenterDeg = stepPhysics();

    if(aliveCount<=1){
      const wi=getWinnerIndex();
      const e=wi>=0?entities[wi]:null;
      winner = e ? { name: e.name, iso2: e.iso2 || null } : null;
      lastWinner = winner ? winner.name : "none";
      state="WIN";
      winFrames=0;
      renderWin();
    }else{
      renderPlay(holeCenterDeg);
    }
  }else{
    winFrames++;
    renderWin();
    if(winFrames >= WIN_SECONDS*FPS){
      startRound();
    }
  }
}

// PPM output
const headerBuf=Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf=Buffer.alloc(headerBuf.length + rgb.length);
function writeFrame(){
  headerBuf.copy(frameBuf,0);
  rgb.copy(frameBuf,headerBuf.length);
  process.stdout.write(frameBuf);
}

// boot frame
clearBG();
drawTextShadow("BOOTING...", (W/2 - 70)|0, (H/2)|0, 3);
writeFrame();

setInterval(()=>{ tick(); writeFrame(); }, Math.round(1000/FPS));
JS

node -c /tmp/yt_ring_game.js
echo "[sim] syntax OK"

# --------------------------------------------------
# RUN STREAM (YOUTUBE ONLY) - SAME AS YOUR WORKING EXAMPLE
# --------------------------------------------------
while true; do
  node /tmp/yt_ring_game.js | ffmpeg -hide_banner -loglevel info -stats \
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