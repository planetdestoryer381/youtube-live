#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

: "${TWITCH_OAUTH:=}"
: "${TWITCH_CHANNEL:=}"
: "${TWITCH_NICK:=}"

: "${TWITCH_CLIENT_ID:=}"
: "${TWITCH_CLIENT_SECRET:=}"

export FPS="${FPS:-15}"
export W="${W:-854}"
export H="${H:-480}"

export BALL_R="${BALL_R:-14}"
export RING_R="${RING_R:-125}"
export HOLE_DEG="${HOLE_DEG:-90}"
export SPIN="${SPIN:-1.2}"
export SPEED="${SPEED:-255}"
export PHYS_MULT="${PHYS_MULT:-3}"
export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-6}"

export FLAG_SIZE="${FLAG_SIZE:-24}"
export AVATAR_SIZE="${AVATAR_SIZE:-24}"
export FLAGS_DIR="${FLAGS_DIR:-/tmp/flags}"
export AVATARS_DIR="${AVATARS_DIR:-/tmp/avatars}"
export COUNTRIES_PATH="${COUNTRIES_PATH:-./countries.json}"

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

const FPS = +process.env.FPS || 15;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const R        = +process.env.BALL_R || 14;
const RING_R   = +process.env.RING_R || 125;
const HOLE_DEG = +process.env.HOLE_DEG || 90;
const SPIN     = +process.env.SPIN || 1.2;
const SPEED    = +process.env.SPEED || 255;
const PHYS_MULT = +process.env.PHYS_MULT || 3;

const WIN_SECONDS = +process.env.WIN_SCREEN_SECONDS || 6;

const FLAG_SIZE   = +process.env.FLAG_SIZE || 24;
const AVATAR_SIZE = +process.env.AVATAR_SIZE || 24;
const FLAGS_DIR   = process.env.FLAGS_DIR || "/tmp/flags";
const AVATARS_DIR = process.env.AVATARS_DIR || "/tmp/avatars";
const COUNTRIES_PATH = process.env.COUNTRIES_PATH || "./countries.json";

const TWITCH_OAUTH   = process.env.TWITCH_OAUTH || "";
const TWITCH_CHANNEL = process.env.TWITCH_CHANNEL || "";
const TWITCH_NICK    = process.env.TWITCH_NICK || "";

const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID || "";
const TWITCH_CLIENT_SECRET = process.env.TWITCH_CLIENT_SECRET || "";

const CX = W*0.5, CY = H*0.5;
const dt = (PHYS_MULT) / FPS;

// ---------- framebuffer ----------
const rgb = Buffer.alloc(W*H*3);
function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b;
}
function fillSolid(r,g,b){
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b; }
}
function clearBG(){ fillSolid(14,20,38); } // deep navy
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

// ---------- tiny font ----------
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

// colors
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

// sprites
function readRGB(path,size){
  try{
    const buf=fs.readFileSync(path);
    if(buf.length===size*size*3) return buf;
  }catch{}
  return null;
}
function flagRGB(iso2){ return readRGB(`${FLAGS_DIR}/${iso2}_${FLAG_SIZE}.rgb`, FLAG_SIZE); }
function avatarRGB(login){ return readRGB(`${AVATARS_DIR}/${login}_${AVATAR_SIZE}.rgb`, AVATAR_SIZE); }

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

const mask=[];
for(let y=-R;y<=R;y++) for(let x=-R;x<=R;x++) if(x*x+y*y<=R*R) mask.push([x,y]);

function drawBallBase(cx,cy,col){
  const x0=cx|0, y0=cy|0;
  const [r,g,b]=col;
  for(const [dx,dy] of mask) setPix(x0+dx,y0+dy,r,g,b);
  for(let deg=0;deg<360;deg+=14){
    const a=deg*Math.PI/180;
    setPix((x0+Math.cos(a)*R)|0,(y0+Math.sin(a)*R)|0,0,0,0);
  }
}

function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}
function drawRing(holeCenterDeg){
  const thick=4;
  for(let deg=0;deg<360;deg++){
    if(inHole(deg,holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const x=(CX+Math.cos(a)*RING_R)|0;
    const y=(CY+Math.sin(a)*RING_R)|0;
    for(let k=-thick;k<=thick;k++){
      setPix(x+k,y,220,220,220);
      setPix(x,y+k,220,220,220);
    }
  }
}

// UI
const UI_BG=[24,34,58], UI_BG2=[14,20,38], UI_LINE=[100,140,190];
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
function drawJoinText(){ drawTextCenteredShadow("TYPE  ME  IN CHAT TO JOIN", W/2, 95, 2); }
function drawNameUnderBall(x,y,name){
  const label=String(name).toUpperCase().replace(/[^A-Z0-9_ ]/g,' ').trim().slice(0,14);
  const w=textWidth(label,1);
  drawTextShadow(label,(x-w/2)|0,(y+R+6)|0,1);
}

// countries.json
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

// helix avatars
function execFFmpegToRGB(url,outPath,size){
  return new Promise((resolve,reject)=>{
    execFile("ffmpeg",["-hide_banner","-loglevel","error","-y","-i",url,"-vf",`scale=${size}:${size}:flags=lanczos`,"-f","rawvideo","-pix_fmt","rgb24",outPath],
      (err)=>err?reject(err):resolve()
    );
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

// players map (join via "me")
const players=new Map(); // login -> {login, display, avatarBuf|null, baseCol}
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
    if(buf){ p.avatarBuf=buf; console.error(`[avatar] cached ${login}`); }
  }catch(e){
    console.error(`[avatar] ffmpeg failed for ${login}: ${e.message}`);
  }
}

// IRC chat
function startTwitchChat(){
  if(!TWITCH_OAUTH || !TWITCH_CHANNEL || !TWITCH_NICK){
    console.error("[chat] disabled (missing TWITCH_OAUTH/TWITCH_CHANNEL/TWITCH_NICK)");
    return;
  }
  const sock=tls.connect(6697,'irc.chat.twitch.tv',{rejectUnauthorized:false},()=>{
    sock.write(`PASS ${TWITCH_OAUTH}\r\n`);
    sock.write(`NICK ${TWITCH_NICK}\r\n`);
    sock.write(`JOIN #${TWITCH_CHANNEL}\r\n`);
    sock.write(`CAP REQ :twitch.tv/tags\r\n`);
    console.error(`[chat] connected to #${TWITCH_CHANNEL} as ${TWITCH_NICK}`);
  });

  let acc="", printed=0;
  sock.on('data',(d)=>{
    acc += d.toString('utf8');
    let idx;
    while((idx=acc.indexOf('\r\n'))>=0){
      let line=acc.slice(0,idx); acc=acc.slice(idx+2);

      if(printed<30){ console.error("[chat:raw]", line); printed++; }

      if(line.startsWith('PING')){ sock.write('PONG :tmi.twitch.tv\r\n'); continue; }
      if(line[0]==='@'){ const sp=line.indexOf(' '); if(sp>0) line=line.slice(sp+1); }

      const m=line.match(/^:([^!]+)![^ ]+ PRIVMSG #[^ ]+ :(.+)$/);
      if(m){
        const user=m[1].toLowerCase();
        const msg=m[2].trim();
        console.error(`[chat:msg] ${user}: ${msg}`);

        if(msg.toLowerCase()==="me"){
          if(players.has(user)){
            console.error(`[join] ${user} already joined (ignored)`);
          }else{
            players.set(user,{login:user,display:user,avatarBuf:null,baseCol:colorFromName(user)});
            console.error(`[join] ${user} joined queue`);
            updateTopChatter();
            fetchAndCacheAvatar(user).catch(e=>console.error("[avatar] error", e.message));
          }
        }
      }
    }
  });
  sock.on('error', e=>console.error('[chat] error', e.message));
  sock.on('end', ()=>console.error('[chat] ended'));
}
startTwitchChat();

// game entities
function rand(a,b){ return a + Math.random()*(b-a); }
let entities=[];
let alive=[];
let aliveCount=0;

let state="PLAY";       // declared ONCE
let t=0;
let winFrames=0;
let winner=null;

function startRound(){
  entities=[];

  // countries first
  for(const c of COUNTRIES){
    entities.push({
      type:"country",
      name:c.name,
      imageBuf: flagRGB(c.iso2),
      imageSize: FLAG_SIZE,
      baseCol:[50,70,110],
      x:0,y:0,vx:0,vy:0
    });
  }
  // players joined
  for(const p of players.values()){
    if(!p.avatarBuf){
      const buf=avatarRGB(p.login);
      if(buf) p.avatarBuf=buf;
    }
    entities.push({
      type:"player",
      name:p.display || p.login,
      imageBuf:p.avatarBuf,
      imageSize: AVATAR_SIZE,
      baseCol:p.baseCol,
      x:0,y:0,vx:0,vy:0
    });
  }

  alive=new Array(entities.length).fill(true);
  aliveCount=entities.length;

  const innerR = RING_R - R - 6;
  const spacing = R * 1.65;
  const sx = CX - innerR;
  const sy = CY - innerR;

  let idx=0;
  for(let y=sy; y<=CY+innerR && idx<entities.length; y+=spacing){
    for(let x=sx; x<=CX+innerR && idx<entities.length; x+=spacing){
      const dx=x-CX, dy=y-CY;
      if(dx*dx+dy*dy <= innerR*innerR){
        const e=entities[idx++];
        e.x = x + rand(-R*0.35, R*0.35);
        e.y = y + rand(-R*0.35, R*0.35);
        e.vx = rand(-SPEED,SPEED);
        e.vy = rand(-SPEED,SPEED);
      }
    }
  }
  while(idx<entities.length){
    const e=entities[idx++];
    e.x = CX + rand(-innerR*0.15, innerR*0.15);
    e.y = CY + rand(-innerR*0.15, innerR*0.15);
    e.vx = rand(-SPEED,SPEED);
    e.vy = rand(-SPEED,SPEED);
  }

  winner=null;
  state="PLAY";
  t=0;
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
  const holeCenterDeg=(t*SPIN*180/Math.PI)%360;

  gclear();
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
    gpush(i,b.x,b.y);
  }

  const minD=2*R, minD2=minD*minD;
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
              if(base===(ny*gridW+nx) && j<=i) continue;

              const B=entities[j];
              const dx=B.x-A.x, dy=B.y-A.y;
              const d2=dx*dx+dy*dy;
              if(d2>0 && d2<minD2){
                const d=Math.sqrt(d2);
                const nxn=dx/d, nyn=dy/d;
                const overlap=minD-d;

                A.x -= nxn*overlap*0.5; A.y -= nyn*overlap*0.5;
                B.x += nxn*overlap*0.5; B.y += nyn*overlap*0.5;

                const rvx=B.vx-A.vx, rvy=B.vy-A.vy;
                const vn=rvx*nxn + rvy*nyn;
                if(vn<0){
                  const imp=-vn;
                  A.vx -= imp*nxn; A.vy -= imp*nyn;
                  B.vx += imp*nxn; B.vy += imp*nyn;
                }
              }
            }
          }
        }
      }
    }
  }

  const wallR=RING_R - R - 2;
  for(let i=0;i<entities.length;i++){
    if(!alive[i]) continue;
    const b=entities[i];
    const dx=b.x-CX, dy=b.y-CY;
    const dist=Math.sqrt(dx*dx+dy*dy)||0.0001;
    const angDeg=(Math.atan2(dy,dx)*180/Math.PI+360)%360;

    if(dist>wallR){
      if(inHole(angDeg,holeCenterDeg)){
        alive[i]=false; aliveCount--; continue;
      }
      const nxn=dx/dist, nyn=dy/dist;
      b.x = CX + nxn*wallR;
      b.y = CY + nyn*wallR;

      const vn=b.vx*nxn + b.vy*nyn;
      if(vn>0){
        b.vx -= 2*vn*nxn;
        b.vy -= 2*vn*nyn;
      }
    }
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
  fillSolid(8,10,18);
  const panelW=Math.min(W-60,760), panelH=260;
  const px=((W-panelW)/2)|0, py=65;
  drawPanel(px,py,panelW,panelH,UI_BG,[100,140,190]);
  drawTextCenteredShadow("WE HAVE A WINNER", W/2, py+45, 3);

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
    drawTextCenteredShadow(winner.type==="country"?"COUNTRY WINNER":"PLAYER WINNER", W/2, py+215, 1);
  }

  drawTextCenteredShadow("NEXT ROUND STARTING...", W/2, py+panelH+38, 2);
}

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

// atomic ppm
const headerBuf=Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf=Buffer.alloc(headerBuf.length + rgb.length);
function writeFrameAtomic(){
  headerBuf.copy(frameBuf,0);
  rgb.copy(frameBuf,headerBuf.length);
  return process.stdout.write(frameBuf);
}

// Write one boot frame immediately so ffmpeg can detect size even if later error occurs
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

// restart round when player count changes
let lastPlayerCount=players.size;
setInterval(()=>{
  const pc=players.size;
  if(pc!==lastPlayerCount){
    console.error(`[round] players changed ${lastPlayerCount} -> ${pc}, restarting round`);
    lastPlayerCount=pc;
    startRound();
  }
}, 1000);
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
