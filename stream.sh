#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# Twitch chat (IRC)
: "${TWITCH_OAUTH:=}"
: "${TWITCH_CHANNEL:=}"
: "${TWITCH_NICK:=}"

# Twitch Helix (optional avatars)
: "${TWITCH_CLIENT_ID:=}"
: "${TWITCH_CLIENT_SECRET:=}"

# Video / game params
export FPS="${FPS:-20}"
export W="${W:-854}"
export H="${H:-480}"

export BALL_R="${BALL_R:-14}"
export RING_R="${RING_R:-160}"
export HOLE_DEG="${HOLE_DEG:-70}"
export SPIN="${SPIN:-0.9}"
export SPEED="${SPEED:-100}"
export PHYS_MULT="${PHYS_MULT:-3}"
export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-6}"

# Assets
export COUNTRIES_PATH="${COUNTRIES_PATH:-./countries.json}"

export FLAG_SIZE="${FLAG_SIZE:-26}"
export FLAGS_DIR="${FLAGS_DIR:-/tmp/flags}"

export AVATAR_SIZE="${AVATAR_SIZE:-26}"
export AVATARS_DIR="${AVATARS_DIR:-/tmp/avatars}"

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED PHYS_MULT=$PHYS_MULT"
echo "COUNTRIES_PATH=$COUNTRIES_PATH"
echo "FLAG_SIZE=$FLAG_SIZE FLAGS_DIR=$FLAGS_DIR"
echo "AVATAR_SIZE=$AVATAR_SIZE AVATARS_DIR=$AVATARS_DIR"
echo "WIN_SCREEN_SECONDS=$WIN_SCREEN_SECONDS"
echo "STREAM_KEY length: ${#STREAM_KEY}"
echo "TWITCH_CHAT: $([ -n "${TWITCH_OAUTH}" ] && [ -n "${TWITCH_CHANNEL}" ] && [ -n "${TWITCH_NICK}" ] && echo enabled || echo disabled)"
echo "HELIX_AVATARS: $([ -n "${TWITCH_CLIENT_ID}" ] && [ -n "${TWITCH_CLIENT_SECRET}" ] && echo enabled || echo disabled)"
node -v
ffmpeg -version | head -n 2
echo "====================="

mkdir -p "$FLAGS_DIR" "$AVATARS_DIR"

download_flag () {
  local iso="$1"
  local size="$2"
  local out_rgb="$FLAGS_DIR/${iso}_${size}.rgb"
  if [ -s "$out_rgb" ]; then return 0; fi

  local png="$FLAGS_DIR/${iso}.png"
  if [ ! -s "$png" ]; then
    # small flags endpoint
    curl -fsSL "https://flagcdn.com/w80/${iso}.png" -o "$png" || return 0
  fi

  ffmpeg -hide_banner -loglevel error -y \
    -i "$png" \
    -vf "scale=${size}:${size}:flags=lanczos" \
    -f rawvideo -pix_fmt rgb24 "$out_rgb" || true
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

cat > /tmp/sim.js <<'JS'
'use strict';
const fs = require('fs');
const tls = require('tls');
const { execFile } = require('child_process');

// -------- env --------
const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const R        = +process.env.BALL_R || 14;
const RING_R   = +process.env.RING_R || 160;
const HOLE_DEG = +process.env.HOLE_DEG || 70;
const SPIN     = +process.env.SPIN || 0.9;
const SPEED    = +process.env.SPEED || 255;
const PHYS_MULT = +process.env.PHYS_MULT || 3;

const WIN_SECONDS = +process.env.WIN_SCREEN_SECONDS || 6;

const FLAGS_DIR   = process.env.FLAGS_DIR || "/tmp/flags";
const FLAG_SIZE   = +process.env.FLAG_SIZE || 26;

const AVATARS_DIR = process.env.AVATARS_DIR || "/tmp/avatars";
const AVATAR_SIZE = +process.env.AVATAR_SIZE || 26;

const COUNTRIES_PATH = process.env.COUNTRIES_PATH || "./countries.json";

const TWITCH_OAUTH   = process.env.TWITCH_OAUTH || "";
const TWITCH_CHANNEL = (process.env.TWITCH_CHANNEL || "").toLowerCase();
const TWITCH_NICK    = (process.env.TWITCH_NICK || "").toLowerCase();

const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID || "";
const TWITCH_CLIENT_SECRET = process.env.TWITCH_CLIENT_SECRET || "";

const CX = W*0.5, CY = H*0.5;
const dt = (PHYS_MULT) / FPS;

// -------- framebuffer (P6) --------
const rgb = Buffer.alloc(W*H*3);
function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
}
function fillSolid(r,g,b){
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b; }
}
function fillRect(x,y,w,h,col){
  const [r,g,b]=col;
  const x0=Math.max(0,x|0), y0=Math.max(0,y|0);
  const x1=Math.min(W,(x+w)|0), y1=Math.min(H,(y+h)|0);
  for(let yy=y0; yy<y1; yy++){
    let idx=(yy*W + x0)*3;
    for(let xx=x0; xx<x1; xx++){
      rgb[idx]=r; rgb[idx+1]=g; rgb[idx+2]=b;
      idx+=3;
    }
  }
}
function rectOutline(x,y,w,h,col){
  const [r,g,b]=col;
  for(let i=0;i<w;i++){ setPix(x+i,y,r,g,b); setPix(x+i,y+h-1,r,g,b); }
  for(let i=0;i<h;i++){ setPix(x,y+i,r,g,b); setPix(x+w-1,y+i,r,g,b); }
}

// nicer dark bg (so white text pops)
function clearBG(){
  fillSolid(10,14,28);
  // subtle vignette
  for(let y=0;y<H;y+=2){
    const v = Math.abs(y-H/2)/(H/2);
    const dark = (v*18)|0;
    for(let x=0;x<W;x+=2){
      const i=(y*W+x)*3;
      rgb[i]   = Math.max(0, rgb[i]-dark);
      rgb[i+1] = Math.max(0, rgb[i+1]-dark);
      rgb[i+2] = Math.max(0, rgb[i+2]-dark);
    }
  }
}

// -------- tiny text --------
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
function textWidth(text,scale){
  text=String(text);
  return text.length*(5*scale+scale)-scale;
}
function drawTextShadow(text,x,y,scale){
  drawText(text, x+1, y+1, scale, [0,0,0]);
  drawText(text, x, y, scale, [255,255,255]);
}
function drawTextCenteredShadow(text,cx,cy,scale){
  const w=textWidth(text,scale), h=7*scale;
  drawTextShadow(text, (cx-w/2)|0, (cy-h/2)|0, scale);
}

// -------- sprites --------
function readRGB(path,size){
  try{
    const buf=fs.readFileSync(path);
    if(buf.length===size*size*3) return buf;
  }catch{}
  return null;
}
function flagRGB(iso2){ return readRGB(`${FLAGS_DIR}/${iso2}_${FLAG_SIZE}.rgb`, FLAG_SIZE); }
function avatarRGB(login){ return readRGB(`${AVATARS_DIR}/${login}_${AVATAR_SIZE}.rgb`, AVATAR_SIZE); }

// blit sprite clipped to a circle
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

// -------- ball drawing --------
const mask=[];
for(let y=-R;y<=R;y++) for(let x=-R;x<=R;x++) if(x*x+y*y<=R*R) mask.push([x,y]);

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

function drawBallBase(cx,cy,col){
  const x0=cx|0, y0=cy|0;
  const [r,g,b]=col;
  for(const [dx,dy] of mask) setPix(x0+dx,y0+dy,r,g,b);

  // small rim highlight
  for(let deg=0;deg<360;deg+=10){
    const a=deg*Math.PI/180;
    setPix((x0+Math.cos(a)*R)|0,(y0+Math.sin(a)*R)|0,0,0,0);
  }
}

function drawNameUnderBall(x,y,name){
  const label=String(name).toUpperCase().replace(/[^A-Z0-9_ .:-]/g,' ').trim().slice(0,16);
  const w=textWidth(label,1);
  drawTextShadow(label,(x-w/2)|0,(y+R+6)|0,1);
}

// -------- ring drawing (much nicer) --------
function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}

// draw thick ring with soft-ish edge
function drawRing(holeCenterDeg){
  const thickness = 4;
  const inner = RING_R - thickness;
  const outer = RING_R + thickness;

  // Draw ring by sampling angles with thickness bands
  for(let deg=0; deg<360; deg+=0.5){
    if(inHole(deg, holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const ca=Math.cos(a), sa=Math.sin(a);

    // multi-stroke gives a smoother look
    for(let rr=inner; rr<=outer; rr++){
      const x=(CX + ca*rr)|0;
      const y=(CY + sa*rr)|0;

      // gradient-ish based on rr
      const t=(rr-inner)/(outer-inner);
      const v=(200 + (1-t)*30)|0;
      setPix(x,y,v,v,v);
    }
  }

  // emphasize outer/inner edges
  for(let deg=0; deg<360; deg+=1){
    if(inHole(deg, holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const ca=Math.cos(a), sa=Math.sin(a);
    const x1=(CX + ca*(outer+1))|0, y1=(CY + sa*(outer+1))|0;
    const x2=(CX + ca*(inner-1))|0, y2=(CY + sa*(inner-1))|0;
    setPix(x1,y1,30,30,30);
    setPix(x2,y2,30,30,30);
  }

  // draw the "hole" edges so it looks intentional
  const edgeA = (holeCenterDeg - HOLE_DEG/2);
  const edgeB = (holeCenterDeg + HOLE_DEG/2);
  for(const edge of [edgeA, edgeB]){
    const a=edge*Math.PI/180;
    const ca=Math.cos(a), sa=Math.sin(a);
    for(let rr=inner-2; rr<=outer+2; rr++){
      const x=(CX + ca*rr)|0, y=(CY + sa*rr)|0;
      setPix(x,y,180,90,30);
    }
  }
}

// -------- UI --------
const UI_BG=[18,26,46], UI_BG2=[10,14,28], UI_LINE=[110,150,210];
let topChatter="none";
let lastWinner="none";

function drawPanel(x,y,w,h,fillCol,lineCol){ fillRect(x,y,w,h,fillCol); rectOutline(x,y,w,h,lineCol); }
function drawTopUI(aliveCount,total){
  const pad=10, barH=58;
  drawPanel(pad,pad,W-pad*2,barH,UI_BG,UI_LINE);
  const cardH=40, cardY=pad+9;
  const cardW=(W-pad*2 - 20)/3;

  drawPanel(pad+6,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("LAST WINNER", pad+14, cardY+6, 1, [180,200,230]);
  drawTextShadow(String(lastWinner).slice(0,18), pad+14, cardY+20, 2);

  const cx0=pad+6+cardW;
  drawPanel(cx0,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("ALIVE", cx0+10, cardY+6, 1, [180,200,230]);
  drawTextShadow(`${aliveCount}/${total}`, cx0+10, cardY+20, 2);

  const rx0=pad+6+cardW*2;
  drawPanel(rx0,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("TOP CHATTER", rx0+10, cardY+6, 1, [180,200,230]);
  drawTextShadow(String(topChatter).slice(0,14), rx0+10, cardY+20, 2);
}
function drawJoinText(){
  drawTextCenteredShadow("JOIN OPENS WHEN < 10 COUNTRIES LEFT", W/2, 95, 2);
  drawTextCenteredShadow("TYPE  ME  OR  YOUR USERNAME", W/2, 115, 2);
}

// -------- countries.json --------
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

// -------- helix avatars (optional) --------
function execFFmpegToRGB(url,outPath,size){
  return new Promise((resolve,reject)=>{
    execFile("ffmpeg",[
      "-hide_banner","-loglevel","error","-y",
      "-i",url,
      "-vf",`scale=${size}:${size}:flags=lanczos`,
      "-f","rawvideo","-pix_fmt","rgb24",outPath
    ], (err)=>err?reject(err):resolve());
  });
}

let appToken="", appTokenExp=0;
async function getAppToken(){
  const now=Date.now();
  if(appToken && now < appTokenExp-30_000) return appToken;
  if(!TWITCH_CLIENT_ID || !TWITCH_CLIENT_SECRET){
    console.error("[helix] missing TWITCH_CLIENT_ID/SECRET; avatars disabled");
    return "";
  }
  const url=`https://id.twitch.tv/oauth2/token?client_id=${encodeURIComponent(TWITCH_CLIENT_ID)}&client_secret=${encodeURIComponent(TWITCH_CLIENT_SECRET)}&grant_type=client_credentials`;
  const res=await fetch(url,{method:"POST"});
  const j=await res.json();
  if(!j.access_token){
    console.error("[helix] token error:", JSON.stringify(j).slice(0,250));
    return "";
  }
  appToken=j.access_token;
  appTokenExp=now+(j.expires_in?j.expires_in*1000:3600_000);
  console.error("[helix] app token ok");
  return appToken;
}
async function helixUserByLogin(login){
  const tok=await getAppToken();
  if(!tok) return null;
  const res=await fetch(`https://api.twitch.tv/helix/users?login=${encodeURIComponent(login)}`,{
    headers:{ "Client-ID": TWITCH_CLIENT_ID, "Authorization": `Bearer ${tok}` }
  });
  const j=await res.json();
  const u=j && j.data && j.data[0];
  if(!u) return null;
  return { display_name:u.display_name, profile_image_url:u.profile_image_url };
}

// -------- players --------
const players=new Map(); // login -> {login, display, avatarBuf|null, baseCol}
let joinedThisRound = new Set();

function updateTopChatter(){
  let last="none";
  for(const k of players.keys()) last=k;
  topChatter=last==="none"?"none":last;
}

async function fetchAndCacheAvatar(login){
  const p=players.get(login);
  if(!p) return;
  const info=await helixUserByLogin(login);
  if(!info){ console.error(`[avatar] helix user not found for ${login}`); return; }
  p.display=info.display_name||p.display;
  if(!info.profile_image_url){ console.error(`[avatar] no profile_image_url for ${login}`); return; }

  const outPath=`${AVATARS_DIR}/${login}_${AVATAR_SIZE}.rgb`;
  try{
    await execFFmpegToRGB(info.profile_image_url,outPath,AVATAR_SIZE);
    const buf=readRGB(outPath,AVATAR_SIZE);
    if(buf){
      p.avatarBuf=buf;
      console.error(`[avatar] cached ${login}`);
      // upgrade any existing in-round entity
      for(let i=0;i<entities.length;i++){
        const e=entities[i];
        if(e && e.type==="player" && e.login===login){
          e.imageBuf = p.avatarBuf;
          e.imageSize = AVATAR_SIZE;
        }
      }
    }
  }catch(e){
    console.error(`[avatar] ffmpeg failed for ${login}: ${e.message}`);
  }
}

// -------- game state --------
let entities=[];
let alive=[];
let aliveCount=0;

let state="PLAY";
let t=0;
let winFrames=0;
let winner=null;

function aliveCountryCount(){
  let c=0;
  for(let i=0;i<entities.length;i++){
    if(alive[i] && entities[i].type==="country") c++;
  }
  return c;
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
  b.vx *= s;
  b.vy *= s;
}

function addPlayerIntoCurrentRound(login){
  const p = players.get(login);
  if(!p) return;

  // prevent duplicates in the same round entity list
  for(let i=0;i<entities.length;i++){
    const e=entities[i];
    if(e && e.type==="player" && e.login===login && alive[i]) return;
  }

  if(!p.avatarBuf){
    const cached = avatarRGB(p.login);
    if(cached) p.avatarBuf = cached;
  }

  const a = Math.random()*Math.PI*2;
  const e = {
    type:"player",
    login,
    name:(p.display||p.login),
    imageBuf:p.avatarBuf,
    imageSize:AVATAR_SIZE,
    baseCol:p.baseCol,
    x: CX + (Math.random()*30-15),
    y: CY + (Math.random()*30-15),
    vx: Math.cos(a)*SPEED,
    vy: Math.sin(a)*SPEED
  };

  entities.push(e);
  alive.push(true);
  aliveCount++;
  console.error(`[inject] player "${login}" added (countriesLeft=${aliveCountryCount()})`);
}

function startRound(){
  joinedThisRound = new Set(); // queue expires every new game
  console.error("[round] new round: join list reset");

  entities=[];
  // countries
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
  }
  // players currently known (but they still must "join" each round to be injected;
  // we DO NOT auto-add them at round start)
  // So they only enter when chat condition becomes true.

  alive=new Array(entities.length).fill(true);
  aliveCount=entities.length;

  // cramped spawn: fill near center in a tight disc
  const innerR = Math.max(40, RING_R - R - 30);
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
}

startRound();

// collision grid
const cellSize=R*3;
const gridW=Math.ceil(W/cellSize);
const gridH=Math.ceil(H/cellSize);
const grid=new Array(gridW*gridH);

function gclear(){ grid.fill(null); }
function gidx(x,y){
  const gx=Math.max(0,Math.min(gridW-1,(x/cellSize)|0));
  const gy=Math.max(0,Math.min(gridH-1,(y/cellSize)|0));
  return gy*gridW+gx;
}
function gpush(i,x,y){
  const k=gidx(x,y);
  if(grid[k]==null) grid[k]=[i]; else grid[k].push(i);
}

function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI)%360;

  gclear();

  // integrate
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
    gpush(i,b.x,b.y);
  }

  // collide
  const minD=2*R;
  const minD2=minD*minD;

  for(let gy=0; gy<gridH; gy++){
    for(let gx=0; gx<gridW; gx++){
      const base=gy*gridW+gx;
      const cell=grid[base];
      if(!cell) continue;

      for(let oy=-1; oy<=1; oy++){
        for(let ox=-1; ox<=1; ox++){
          const nx=gx+ox, ny=gy+oy;
          if(nx<0||ny<0||nx>=gridW||ny>=gridH) continue;
          const other=grid[ny*gridW+nx];
          if(!other) continue;

          for(let ai=0; ai<cell.length; ai++){
            const i=cell[ai]; if(!alive[i]) continue;
            const A=entities[i];

            for(let bj=0; bj<other.length; bj++){
              const j=other[bj]; if(!alive[j]) continue;
              if((ny*gridW+nx)===base && j<=i) continue;

              const B=entities[j];
              const dx=B.x-A.x, dy=B.y-A.y;
              const d2=dx*dx+dy*dy;
              if(d2>0 && d2<minD2){
                const d=Math.sqrt(d2);
                const nxn=dx/d, nyn=dy/d;
                const overlap=minD-d;

                // separate
                A.x -= nxn*overlap*0.5; A.y -= nyn*overlap*0.5;
                B.x += nxn*overlap*0.5; B.y += nyn*overlap*0.5;

                // swap velocity along normal (elastic-ish)
                const vax=A.vx, vay=A.vy;
                const vbx=B.vx, vby=B.vy;

                const van=vax*nxn + vay*nyn;
                const vbn=vbx*nxn + vby*nyn;

                const tax=vax - van*nxn, tay=vay - van*nyn;
                const tbx=vbx - vbn*nxn, tby=vby - vbn*nyn;

                // exchange normal components
                A.vx = tax + vbn*nxn;
                A.vy = tay + vbn*nyn;
                B.vx = tbx + van*nxn;
                B.vy = tby + van*nyn;
              }
            }
          }
        }
      }
    }
  }

  // ring constraint + hole elimination
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
      const nxn=dx/dist, nyn=dy/dist;
      b.x = CX + nxn*wallR;
      b.y = CY + nyn*wallR;

      // reflect direction (speed normalized later)
      const vn=b.vx*nxn + b.vy*nyn;
      b.vx -= 2*vn*nxn;
      b.vy -= 2*vn*nyn;
    }
  }

  // **HARD RULE: fixed speed forever**
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    normalizeSpeed(entities[i], SPEED);
  }

  return holeCenterDeg;
}

function drawEntity(e){
  const x=e.x|0, y=e.y|0;
  drawBallBase(x,y,e.baseCol);

  if(e.imageBuf) blitSpriteInCircle(x,y,R,e.imageBuf,e.imageSize);

  drawNameUnderBall(x,y,e.name);
}

function getWinnerIndex(){
  for(let i=0;i<entities.length;i++) if(alive[i]) return i;
  return -1;
}

function renderPlay(holeCenterDeg){
  clearBG();
  drawTopUI(aliveCount, entities.length);
  drawJoinText();
  drawRing(holeCenterDeg);

  for(let i=0;i<entities.length;i++){
    if(alive[i]) drawEntity(entities[i]);
  }
}

function renderWin(){
  fillSolid(6,8,16);
  const panelW=Math.min(W-60,760), panelH=260;
  const px=((W-panelW)/2)|0, py=75;
  drawPanel(px,py,panelW,panelH,[18,26,46],[110,150,210]);

  drawTextCenteredShadow("WOHOO WE HAVE A WINNER HERE", W/2, py+45, 2);

  if(winner){
    const box=96;
    const bx=(W/2 - box/2)|0;
    const by=(py+75)|0;

    fillRect(bx,by,box,box,[255,255,255]);
    rectOutline(bx,by,box,box,[0,0,0]);

    if(winner.imageBuf){
      const s=winner.imageSize, buf=winner.imageBuf;
      for(let yy=0; yy<box; yy++){
        for(let xx=0; xx<box; xx++){
          const sx=Math.min(s-1,(xx*s/box)|0);
          const sy=Math.min(s-1,(yy*s/box)|0);
          const si=(sy*s+sx)*3;
          setPix(bx+xx,by+yy,buf[si],buf[si+1],buf[si+2]);
        }
      }
    }

    drawTextCenteredShadow(winner.name, W/2, py+190, 2);
    drawTextCenteredShadow(winner.type==="country" ? "COUNTRY WINNER" : "PLAYER WINNER", W/2, py+220, 1);
  }

  drawTextCenteredShadow("NEXT ROUND STARTING...", W/2, py+panelH+40, 2);
}

// -------- game loop --------
function tick(){
  if(state==="PLAY"){
    const holeCenterDeg=stepPhysics();

    if(aliveCount<=1){
      const wi=getWinnerIndex();
      const e=wi>=0?entities[wi]:null;
      winner=e?{type:e.type,name:e.name,imageBuf:e.imageBuf,imageSize:e.imageSize}:null;
      lastWinner=winner?winner.name:"none";
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

// -------- PPM output (atomic) --------
const headerBuf=Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf=Buffer.alloc(headerBuf.length + rgb.length);
function writeFrameAtomic(){
  headerBuf.copy(frameBuf,0);
  rgb.copy(frameBuf,headerBuf.length);
  return process.stdout.write(frameBuf);
}

// Boot frame (so ffmpeg always detects size immediately)
(function bootFrame(){
  clearBG();
  drawTextCenteredShadow("BOOTING...", W/2, H/2, 3);
  writeFrameAtomic();
})();

let busy=false;
function stepOnce(){
  if(busy) return;
  busy=true;
  tick();
  const ok=writeFrameAtomic();
  if(ok) busy=false;
  else process.stdout.once('drain', ()=>{ busy=false; });
}
setInterval(stepOnce, Math.round(1000/FPS));

// -------- Twitch chat (IRC) --------
function startTwitchChat(){
  if(!TWITCH_OAUTH || !TWITCH_CHANNEL || !TWITCH_NICK){
    console.error("[chat] disabled (missing TWITCH_OAUTH/TWITCH_CHANNEL/TWITCH_NICK)");
    return;
  }

  const sock=tls.connect(6697,'irc.chat.twitch.tv',{rejectUnauthorized:false},()=>{
    console.error(`[chat] connecting as nick="${TWITCH_NICK}" channel="#${TWITCH_CHANNEL}" oauth_prefix="${TWITCH_OAUTH.slice(0,5)}" oauth_len=${TWITCH_OAUTH.length}`);
    sock.write(`PASS ${TWITCH_OAUTH}\r\n`);
    sock.write(`NICK ${TWITCH_NICK}\r\n`);
    sock.write(`CAP REQ :twitch.tv/tags\r\n`);
    sock.write(`JOIN #${TWITCH_CHANNEL}\r\n`);
    console.error(`[chat] sent JOIN #${TWITCH_CHANNEL}`);
  });

  let acc="", printed=0;
  sock.on('data',(d)=>{
    acc += d.toString('utf8');
    let idx;
    while((idx=acc.indexOf('\r\n'))>=0){
      let line=acc.slice(0,idx); acc=acc.slice(idx+2);

      if(printed<25){ console.error("[chat:raw]", line); printed++; }

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

        const cleaned = msg.toLowerCase();
        const isJoin = (cleaned === "me") || (cleaned === user);

        if(isJoin){
          const countriesLeft = aliveCountryCount();

          // join only when countries left < 10
          if(countriesLeft >= 10){
            console.error(`[join] ${user} blocked (countriesLeft=${countriesLeft} >= 10)`);
            continue;
          }

          // once per round
          if(joinedThisRound.has(user)){
            console.error(`[join] ${user} already joined THIS round (ignored)`);
            continue;
          }

          joinedThisRound.add(user);

          if(!players.has(user)){
            players.set(user,{login:user,display:user,avatarBuf:null,baseCol:colorFromName(user)});
            fetchAndCacheAvatar(user).catch(e=>console.error("[avatar] error", e.message));
          }

          console.error(`[join] ${user} accepted (countriesLeft=${countriesLeft})`);
          updateTopChatter();
          addPlayerIntoCurrentRound(user);
        }
      }
    }
  });

  sock.on('error', e=>console.error('[chat] error', e.message));
  sock.on('end', ()=>console.error('[chat] ended'));
}
startTwitchChat();
JS

URL="rtmps://live.twitch.tv/app/${STREAM_KEY}"

node /tmp/sim.js | ffmpeg -hide_banner -loglevel info -stats \
  -thread_queue_size 1024 \
  -probesize 50M -analyzeduration 2M \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -g 60 -b:v 2200k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "$URL"
