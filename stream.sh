#!/usr/bin/env bash
set -euo pipefail

# -------- REQUIRED --------
: "${STREAM_KEY:?Missing STREAM_KEY (set as GitHub Secret)}"

# -------- Twitch chat (optional but you want it) --------
: "${TWITCH_OAUTH:=}"     # format: oauth:xxxxxxxxxxxx
: "${TWITCH_CHANNEL:=}"   # without '#'
: "${TWITCH_NICK:=}"      # bot/user login

# -------- Game/video settings --------
export FPS="${FPS:-20}"
export W="${W:-854}"
export H="${H:-480}"
export RESTART_SECONDS="${RESTART_SECONDS:-21000}"
export BALL_R="${BALL_R:-14}"
export RING_R="${RING_R:-160}"
export HOLE_DEG="${HOLE_DEG:-70}"
export SPIN="${SPIN:-0.9}"

# your request:
export SPEED="${SPEED:-100}"

export PHYS_MULT="${PHYS_MULT:-3}"
export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-6}"

# ring looks
export RING_THICKNESS="${RING_THICKNESS:-4}"      # thinner ring
export RING_HOLE_EDGE="${RING_HOLE_EDGE:-1}"      # 1 show hole edge glow

# assets
export COUNTRIES_PATH="${COUNTRIES_PATH:-./countries.json}"
export FLAG_SIZE="${FLAG_SIZE:-26}"
export FLAGS_DIR="${FLAGS_DIR:-/tmp/flags}"
mkdir -p "$FLAGS_DIR"

URL="rtmps://live.twitch.tv/app/${STREAM_KEY}"

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED PHYS_MULT=$PHYS_MULT"
echo "RING_THICKNESS=$RING_THICKNESS RING_HOLE_EDGE=$RING_HOLE_EDGE"
echo "COUNTRIES_PATH=$COUNTRIES_PATH FLAG_SIZE=$FLAG_SIZE FLAGS_DIR=$FLAGS_DIR"
echo "WIN_SCREEN_SECONDS=$WIN_SCREEN_SECONDS"
echo "STREAM_KEY length: ${#STREAM_KEY}"
echo "TWITCH_CHAT: $([ -n "${TWITCH_OAUTH}" ] && [ -n "${TWITCH_CHANNEL}" ] && [ -n "${TWITCH_NICK}" ] && echo enabled || echo disabled)"
node -v
ffmpeg -version | head -n 2
echo "====================="

# ---- download + preconvert flags to raw rgb once ----
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

# ---- node sim ----
cat > /tmp/sim.js <<'JS'
'use strict';
const fs = require('fs');
const tls = require('tls');

process.stdout.on("error", (e) => {
  if (e && e.code === "EPIPE") {
    console.error("[pipe] ffmpeg closed stdin (EPIPE) - exiting cleanly");
    process.exit(0);
  }
});

const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const R        = +process.env.BALL_R || 14;
const RING_R   = +process.env.RING_R || 160;
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

const TWITCH_OAUTH   = process.env.TWITCH_OAUTH || "";
const TWITCH_CHANNEL = (process.env.TWITCH_CHANNEL || "").toLowerCase();
const TWITCH_NICK    = (process.env.TWITCH_NICK || "").toLowerCase();

const CX = W*0.5, CY = H*0.5;
const dt = (PHYS_MULT) / FPS;

// ---- framebuffer ----
const rgb = Buffer.alloc(W*H*3);
function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
}
function fillSolid(r,g,b){
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b; }
}
function clearBG(){
  // dark-ish background so white usernames pop
  fillSolid(10,14,28);
}

// ---- tiny font ----
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
  '/':[0b00001,0b00010,0b00100,0b01000,0b10000,0,0],
  ' ':[0,0,0,0,0,0,0],
  '-':[0,0,0b11111,0,0,0,0],
  '_':[0,0,0,0,0,0,0b11111],
  ':':[0,0b00100,0,0,0b00100,0,0],
  '.':[0,0,0,0,0,0,0b00100],
  '?':[0b01110,0b10001,0b00010,0b00100,0b00100,0,0b00100],
};
function drawChar(ch,x,y,scale,color){
  const rows = FONT[ch] || FONT['?'];
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
function textWidth(text,scale){ return String(text).length*(5*scale+scale)-scale; }
function drawTextShadow(text,x,y,scale){
  drawText(text, x+1, y+1, scale, [0,0,0]);
  drawText(text, x, y, scale, [255,255,255]);
}

// ---- sprites ----
function readRGB(path,size){
  try{
    const buf=fs.readFileSync(path);
    if(buf.length===size*size*3) return buf;
  }catch{}
  return null;
}
function flagRGB(iso2){ return readRGB(`${FLAGS_DIR}/${iso2}_${FLAG_SIZE}.rgb`, FLAG_SIZE); }

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

// ---- colors ----
function hashStr(s){
  s=String(s);
  let h=2166136261>>>0;
  for(let i=0;i<s.length;i++){
    h^=s.charCodeAt(i);
    h=Math.imul(h,16777619)>>>0;
  }
  return h>>>0;
}
function colorFromName(name){
  const h=hashStr(name);
  return [60+(h&0x7F), 60+((h>>7)&0x7F), 60+((h>>14)&0x7F)];
}

// ---- physics helpers ----
function normalizeSpeed(b, target){
  const v = Math.hypot(b.vx, b.vy);
  if(v < 1e-6){
    const a = Math.random()*Math.PI*2;
    b.vx = Math.cos(a)*target;
    b.vy = Math.sin(a)*target;
    return;
  }
  const s = target / v;
  b.vx *= s;
  b.vy *= s;
}

function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}

function drawRing(holeCenterDeg){
  const thickness = Math.max(2, RING_THICKNESS);
  const inner = RING_R - thickness;
  const outer = RING_R + thickness;

  for(let deg=0; deg<360; deg+=0.5){
    if(inHole(deg, holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const ca=Math.cos(a), sa=Math.sin(a);
    for(let rr=inner; rr<=outer; rr++){
      const x=(CX + ca*rr)|0;
      const y=(CY + sa*rr)|0;
      const t=(rr-inner)/(outer-inner);
      const v=(210 + (1-t)*20)|0;
      setPix(x,y,v,v,v);
    }
  }

  // outline
  for(let deg=0; deg<360; deg+=1){
    if(inHole(deg, holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const ca=Math.cos(a), sa=Math.sin(a);
    setPix((CX + ca*(outer+1))|0, (CY + sa*(outer+1))|0, 40,40,40);
    setPix((CX + ca*(inner-1))|0, (CY + sa*(inner-1))|0, 40,40,40);
  }

  if(RING_HOLE_EDGE){
    const edgeA = (holeCenterDeg - HOLE_DEG/2);
    const edgeB = (holeCenterDeg + HOLE_DEG/2);
    for(const edge of [edgeA, edgeB]){
      const a=edge*Math.PI/180;
      const ca=Math.cos(a), sa=Math.sin(a);
      for(let rr=inner-2; rr<=outer+2; rr++){
        setPix((CX + ca*rr)|0, (CY + sa*rr)|0, 180, 90, 30);
      }
    }
  }
}

// ---- countries ----
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

// ---- game state ----
function fmtCountdown(sec){
  sec = Math.max(0, sec|0);
  const h = (sec/3600)|0;
  const m = ((sec%3600)/60)|0;
  const s = (sec%60)|0;
  return `${h} hours ${m} minutes ${s} seconds till stream restarts`;
}

let entities=[], alive=[], aliveCount=0;
let state="PLAY";
let t=0;
let winFrames=0;
let winner=null;
let lastWinner="none";
let topChatter="none";

// chat join queue (DOES NOT EXPIRE)
let joinQueue = [];
let joinQueued = new Set(); // prevents duplicate queueing this round
let playerActive = new Set(); // prevents multiple spawns in same round

function aliveCountryCount(){
  let c=0;
  for(let i=0;i<entities.length;i++){
    if(alive[i] && entities[i].type === "country") c++;
  }
  return c;
}

function startRound(){
  // reset round gameplay, but KEEP joinQueue/joinQueued (your request)
  playerActive = new Set();

  entities=[];
  alive=[];
  aliveCount=0;

  for(const c of COUNTRIES){
    entities.push({
      type:"country",
      name:c.name,
      iso2:c.iso2,
      imageBuf: flagRGB(c.iso2),
      imageSize: FLAG_SIZE,
      baseCol:[45,65,110],
      x:0,y:0,vx:0,vy:0
    });
    alive.push(true);
  }
  aliveCount = entities.length;

  // cramped spawn near center
  const innerR = Math.max(35, RING_R - R - 35);
  for(let i=0;i<entities.length;i++){
    const e=entities[i];
    const a=Math.random()*Math.PI*2;
    const rr=Math.random()*innerR;
    e.x = CX + Math.cos(a)*rr;
    e.y = CY + Math.sin(a)*rr;

    const dir=Math.random()*Math.PI*2;
    e.vx = Math.cos(dir)*SPEED;
    e.vy = Math.sin(dir)*SPEED;
  }

  winner=null;
  state="PLAY";
  t=0;
  winFrames=0;

  console.error(`[round] new round (queue=${joinQueue.length})`);
}
startRound();

function spawnPlayer(username){
  username = String(username||"").toLowerCase().trim();
  if(!username) return false;
  if(playerActive.has(username)) return false; // already spawned this round

  const innerR = Math.max(30, RING_R - R - 40);
  const a = Math.random()*Math.PI*2;
  const rr = Math.random()*innerR;
  const dir = Math.random()*Math.PI*2;

  entities.push({
    type:"player",
    name:username,
    iso2:null,
    imageBuf:null,
    imageSize:0,
    baseCol:colorFromName(username),
    x: CX + Math.cos(a)*rr,
    y: CY + Math.sin(a)*rr,
    vx: Math.cos(dir)*SPEED,
    vy: Math.sin(dir)*SPEED,
  });
  alive.push(true);
  aliveCount++;
  playerActive.add(username);

  console.error(`[join] spawned "${username}" (alive=${aliveCount})`);
  return true;
}

// ---- draw balls ----
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
  // NO white rectangle background (your request). Just shadow + white.
  drawTextShadow(label,(x-w/2)|0,(y+R+6)|0,1);
}

function drawEntity(e){
  const x=e.x|0, y=e.y|0;
  drawBallBase(x,y,e.baseCol);
  if(e.imageBuf) blitSpriteInCircle(x,y,R,e.imageBuf,e.imageSize);
  drawNameUnderBall(x,y,e.name);
}

// ---- OLD-STYLE UI ----
function drawTopUI(){
  const s = 2;
  const y = 10;
  let x = 14;

  const aliveTxt = `ALIVE: ${aliveCount}/${entities.length}`;
  const lastTxt  = `LAST WIN: ${String(lastWinner).toUpperCase().slice(0,18)}`;
  const queueTxt = `QUEUE: ${joinQueue.length}`;

  drawTextShadow(aliveTxt, x, y, s);
  x += textWidth(aliveTxt, s) + 22;

  drawTextShadow(lastTxt, x, y, s);
  x += textWidth(lastTxt, s) + 22;

  drawTextShadow(queueTxt, x, y, s);

  // countdown line (below)
  const elapsed = ((Date.now() - startMs)/1000)|0;
  const left = RESTART_SECONDS - elapsed;
  drawTextShadow(fmtCountdown(left), 14, y + (7*s + 8), 2);
}



function renderPlay(holeCenterDeg){
  clearBG();
  drawTopUI();
  drawRing(holeCenterDeg);
  for(let i=0;i<entities.length;i++){
    if(alive[i]) drawEntity(entities[i]);
  }
}

// ---- OLD-STYLE WIN SCREEN ----
function renderWin(){
  fillSolid(8,10,18);

  const title = "WE HAVE A WINNER!";

  drawTextShadow(title,(W/2-textWidth(title,4)/2)|0,(H/2-90)|0,4);

  if(winner){
    const iconX = (W/2)|0;
    const iconY = (H/2 - 20)|0;

    drawBallBase(iconX, iconY, [50,70,120]);
    if(winner.iso2){
      const buf = flagRGB(winner.iso2);
      if(buf) blitSpriteInCircle(iconX, iconY, R, buf, FLAG_SIZE);
    }

    const name = String(winner.name).toUpperCase().slice(0,20);
    drawTextShadow(name, (W/2 - (textWidth(name,2)/2))|0, (H/2 + 25)|0, 2);
  }
}

// ---- physics ----
function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI)%360;

  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
  }

  // collisions
  const minD=2*R;
  const minD2=minD*minD;
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

  // ring boundary + hole elimination
  const wallR = RING_R - R - 3;
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    const dx=b.x-CX, dy=b.y-CY;
    const dist=Math.sqrt(dx*dx+dy*dy)||0.0001;
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

  // FIXED speed always
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    normalizeSpeed(entities[i], SPEED);
  }

  return holeCenterDeg;
}

function getWinnerIndex(){
  for(let i=0;i<entities.length;i++) if(alive[i]) return i;
  return -1;
}

function tick(){

  if(state==="PLAY"){
    // spawn queued players ONLY when <10 countries alive
    while(aliveCountryCount() < 10 && joinQueue.length > 0){
      const u = joinQueue.shift();
      // allow re-queue next round by removing from joinQueued only when spawned
      joinQueued.delete(u);
      spawnPlayer(u);
    }

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

// ---- PPM output ----
const headerBuf=Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf=Buffer.alloc(headerBuf.length + rgb.length);

function writeFrame(){
  headerBuf.copy(frameBuf,0);
  rgb.copy(frameBuf,headerBuf.length);
  process.stdout.write(frameBuf);
}

// boot frame so ffmpeg detects size
clearBG();
drawTextShadow("BOOTING...", (W/2 - 70)|0, (H/2)|0, 3);
writeFrame();

setInterval(()=>{
  tick();
  writeFrame();
}, Math.round(1000/FPS));

// ---- twitch chat ----
function startTwitchChat(){
  if(!TWITCH_OAUTH || !TWITCH_CHANNEL || !TWITCH_NICK){
    console.error("[chat] disabled (missing TWITCH_OAUTH/TWITCH_CHANNEL/TWITCH_NICK)");
    return;
  }

  const sock=tls.connect(6697,'irc.chat.twitch.tv',{rejectUnauthorized:false},()=>{
    console.error(`[chat] connecting nick="${TWITCH_NICK}" channel="#${TWITCH_CHANNEL}" oauth_len=${TWITCH_OAUTH.length}`);
    sock.write(`PASS ${TWITCH_OAUTH}\r\n`);
    sock.write(`NICK ${TWITCH_NICK}\r\n`);
    sock.write(`CAP REQ :twitch.tv/tags\r\n`);
    sock.write(`JOIN #${TWITCH_CHANNEL}\r\n`);
  });

  let acc="", printed=0;
  sock.on('data',(d)=>{
    acc += d.toString('utf8');
    let idx;
    while((idx=acc.indexOf('\r\n'))>=0){
      let line=acc.slice(0,idx); acc=acc.slice(idx+2);
      if(printed<12){ console.error("[chat:raw]", line); printed++; }

      if(line.startsWith('PING')){ sock.write('PONG :tmi.twitch.tv\r\n'); continue; }

      // strip tags
      if(line[0]==='@'){
        const sp=line.indexOf(' ');
        if(sp>0) line=line.slice(sp+1);
      }

      const m=line.match(/^:([^!]+)![^ ]+ PRIVMSG #[^ ]+ :(.+)$/);
      if(m){
        const user=m[1].toLowerCase();
        const msg=m[2].trim();
        console.error(`[chat:msg] ${user}: ${msg}`);
        topChatter=user;

        if(msg.toLowerCase()==="me"){
          if(joinQueued.has(user)){
            console.error(`[join] ${user} already queued (ignored)`);
          }else{
            joinQueued.add(user);
            joinQueue.push(user);
            console.error(`[join] queued ${user} (queue=${joinQueue.length})`);
          }
        }
      }
    }
  });

  sock.on('error', e=>console.error('[chat] error', e.message));
  sock.on('end', ()=>console.error('[chat] ended'));
}
startTwitchChat();
JS

# ---- stream loop (auto reconnect) ----
set +e
while true; do
  echo "[stream] starting node -> ffmpeg ..."
  node /tmp/sim.js | ffmpeg -hide_banner -loglevel info -stats \
    -thread_queue_size 1024 \
    -probesize 50M -analyzeduration 2M \
    -f image2pipe -vcodec ppm -r "$FPS" -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -map 0:v -map 1:a \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -pix_fmt yuv420p \
    -g $((FPS*2)) \
    -x264-params "keyint=$((FPS*2)):min-keyint=$((FPS*2)):scenecut=0" \
    -b:v 1800k -maxrate 1800k -bufsize 3600k \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$URL"

  code=$?
  echo "[stream] ffmpeg exited (code=$code). reconnecting in 3s..."
  sleep 3
done
