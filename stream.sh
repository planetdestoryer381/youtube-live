#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# Optional (for chat integration)
: "${TWITCH_OAUTH:=}"
: "${TWITCH_CHANNEL:=}"

# ======= TUNING =======
export FPS="${FPS:-15}"
export W="${W:-854}"
export H="${H:-480}"

export BALLS="${BALLS:-200}"
export BALL_R="${BALL_R:-14}"        # bigger balls
export RING_R="${RING_R:-135}"       # smaller circle
export HOLE_DEG="${HOLE_DEG:-80}"    # bigger hole so people die faster
export SPIN="${SPIN:-1.15}"          # rotate hole a bit faster
export SPEED="${SPEED:-85}"

export ROUND_SECONDS="${ROUND_SECONDS:-120}"
export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-8}"

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALLS=$BALLS BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED"
echo "ROUND_SECONDS=$ROUND_SECONDS WIN_SCREEN_SECONDS=$WIN_SCREEN_SECONDS"
echo "STREAM_KEY length: ${#STREAM_KEY}"
echo "TWITCH_CHAT: $([ -n "${TWITCH_OAUTH}" ] && [ -n "${TWITCH_CHANNEL}" ] && echo enabled || echo disabled)"
node -v
ffmpeg -version | head -n 2
echo "====================="

cat > /tmp/sim.js <<'JS'
'use strict';

const tls = require('tls');

// ---------------- ENV ----------------
const FPS = +process.env.FPS || 15;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const MAX_BALLS = +process.env.BALLS  || 200;
const R        = +process.env.BALL_R || 14;
const RING_R   = +process.env.RING_R || 135;
const HOLE_DEG = +process.env.HOLE_DEG || 80;
const SPIN     = +process.env.SPIN || 1.15;
const SPEED    = +process.env.SPEED || 85;

const ROUND_SECONDS = +process.env.ROUND_SECONDS || 120;
const WIN_SECONDS   = +process.env.WIN_SCREEN_SECONDS || 8;

const TWITCH_OAUTH   = process.env.TWITCH_OAUTH || "";
const TWITCH_CHANNEL = process.env.TWITCH_CHANNEL || "";

const CX = W*0.5, CY = H*0.5;
const dt = 1/FPS;

// ---------------- Buffer ----------------
const buf = Buffer.alloc(W*H*3);
function setPix(x,y,r,g,b){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  buf[i]=r; buf[i+1]=g; buf[i+2]=b;
}
function fillSolid(r,g,b){
  for(let i=0;i<buf.length;i+=3){ buf[i]=r; buf[i+1]=g; buf[i+2]=b; }
}
function clearSky(){
  // simple light sky background
  fillSolid(155, 215, 255);
}

// ---------------- Tiny font (5x7) ----------------
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
  ':':[0,0b00100,0b00100,0,0b00100,0b00100,0],
  '/':[0b00001,0b00010,0b00100,0b01000,0b10000,0,0],
  ' ':[0,0,0,0,0,0,0],
  '-':[0,0,0b11111,0,0,0,0],
};

function drawChar(ch,x,y,scale,color){
  const rows = FONT[ch] || FONT[' '];
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
  text = String(text).toUpperCase();
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
function drawTextCentered(text,cx,cy,scale,color){
  const w=textWidth(text,scale), h=7*scale;
  drawText(text, (cx-w/2)|0, (cy-h/2)|0, scale, color);
}
function drawPanel(x,y,w,h,fillCol,lineCol){
  // simple rounded-ish panel
  fillRect(x,y,w,h,fillCol);
  rectOutline(x,y,w,h,lineCol);
}
function fillRect(x,y,w,h,col){
  const [r,g,b]=col;
  const x0=Math.max(0,x|0), y0=Math.max(0,y|0);
  const x1=Math.min(W,(x+w)|0), y1=Math.min(H,(y+h)|0);
  for(let yy=y0; yy<y1; yy++){
    let idx=(yy*W + x0)*3;
    for(let xx=x0; xx<x1; xx++){
      buf[idx]=r; buf[idx+1]=g; buf[idx+2]=b;
      idx+=3;
    }
  }
}
function rectOutline(x,y,w,h,col){
  const [r,g,b]=col;
  for(let i=0;i<w;i++){ setPix(x+i,y,r,g,b); setPix(x+i,y+h-1,r,g,b); }
  for(let i=0;i<h;i++){ setPix(x,y+i,r,g,b); setPix(x+w-1,y+i,r,g,b); }
}

// ---------------- circle drawing ----------------
const mask=[];
for(let y=-R;y<=R;y++) for(let x=-R;x<=R;x++) if(x*x+y*y<=R*R) mask.push([x,y]);

function drawBall(cx,cy,col){
  const [r,g,b]=col;
  const x0=cx|0, y0=cy|0;
  for(let k=0;k<mask.length;k++){
    const dx=mask[k][0], dy=mask[k][1];
    setPix(x0+dx,y0+dy,r,g,b);
  }
  // outline
  for(let deg=0;deg<360;deg+=14){
    const a=deg*Math.PI/180;
    setPix((x0+Math.cos(a)*R)|0, (y0+Math.sin(a)*R)|0, 0,0,0);
  }
}

function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}

function drawRing(holeCenterDeg){
  const thick=4;
  for(let deg=0;deg<360;deg+=1){
    if(inHole(deg,holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const x=(CX+Math.cos(a)*RING_R)|0;
    const y=(CY+Math.sin(a)*RING_R)|0;
    for(let k=-thick;k<=thick;k++){
      setPix(x+k,y,30,30,30);
      setPix(x,y+k,30,30,30);
    }
  }
}

// ---------------- data + chat ----------------
// Keep it simple now: countries pool + chat chooses a country by name.
const COUNTRIES = [
  "QATAR","EGYPT","SAUDI ARABIA","UNITED STATES","UNITED KINGDOM","FRANCE","GERMANY","SPAIN","ITALY","CANADA",
  "BRAZIL","ARGENTINA","MEXICO","RUSSIA","CHINA","INDIA","JAPAN","KOREA","TURKIYE","INDONESIA",
  "AUSTRALIA","NEW ZEALAND","SOUTH AFRICA","NIGERIA","KENYA","MOROCCO","TUNISIA","UAE","QATAR","OMAN",
  "PAKISTAN","IRAN","IRAQ","SYRIA","YEMEN","LEBANON","JORDAN","ISRAEL","UKRAINE","POLAND",
  "PORTUGAL","NETHERLANDS","SWEDEN","NORWAY","FINLAND","SWITZERLAND","AUSTRIA","BELGIUM","GREECE","ROMANIA",
  "PHILIPPINES","VIETNAM","THAILAND","MALAYSIA","SINGAPORE","BANGLADESH","NEPAL","SRI LANKA","AFGHANISTAN","UZBEKISTAN"
];
const countrySet = new Set(COUNTRIES);

function normalizeCountry(s){
  s = String(s||"").toUpperCase().trim();
  s = s.replace(/[^A-Z ]/g,' ').replace(/\s+/g,' ').trim();
  if(countrySet.has(s)) return s;

  // allow partial: "UNITED" -> "UNITED STATES" (first match)
  for(const c of COUNTRIES){
    if(c.startsWith(s) && s.length>=3) return c;
  }
  return null;
}

// Chat state
const chatUsers = new Map(); // user -> {msgs, country}
let topChatter = "none";

function updateTopChatter(){
  let best = null, bestN = -1;
  for(const [u,info] of chatUsers.entries()){
    if(info.msgs > bestN){
      bestN = info.msgs;
      best = u;
    }
  }
  topChatter = best ? best : "none";
}

// Twitch IRC (optional)
function startTwitchChat(){
  if(!TWITCH_OAUTH || !TWITCH_CHANNEL) return;

  const socket = tls.connect(6697, 'irc.chat.twitch.tv', { rejectUnauthorized: false }, () => {
    socket.write(`PASS ${TWITCH_OAUTH}\r\n`);
    socket.write(`NICK justinfan${Math.floor(Math.random()*99999)}\r\n`);
    socket.write(`JOIN #${TWITCH_CHANNEL}\r\n`);
    socket.write(`CAP REQ :twitch.tv/tags\r\n`);
    console.error(`[chat] connected to #${TWITCH_CHANNEL}`);
  });

  let bufStr = '';
  socket.on('data', (d) => {
    bufStr += d.toString('utf8');
    let idx;
    while((idx = bufStr.indexOf('\r\n')) >= 0){
      const line = bufStr.slice(0, idx);
      bufStr = bufStr.slice(idx+2);

      if(line.startsWith('PING')){
        socket.write('PONG :tmi.twitch.tv\r\n');
        continue;
      }

      // Example: :username!username@username.tmi.twitch.tv PRIVMSG #channel :message
      const m = line.match(/^:([^!]+)![^ ]+ PRIVMSG #[^ ]+ :(.+)$/);
      if(m){
        const user = m[1].toLowerCase();
        const msg  = m[2];

        const info = chatUsers.get(user) || { msgs: 0, country: null };
        info.msgs++;
        // user sets country by typing it anywhere in message
        const maybe = normalizeCountry(msg);
        if(maybe) info.country = maybe;

        chatUsers.set(user, info);
        updateTopChatter();
      }
    }
  });

  socket.on('error', (e)=> console.error('[chat] error', e.message));
  socket.on('end', ()=> console.error('[chat] ended'));
}
startTwitchChat();

// ---------------- game state ----------------
function rndi(a,b){ return a + ((Math.random()*(b-a+1))|0); }
function rand(a,b){ return a + Math.random()*(b-a); }
function randColor(){ return [rndi(60,235), rndi(60,235), rndi(60,235)]; }

const balls = [];
let alive = [];
let aliveCount = 0;

let state = "PLAY";
let t = 0;
let roundFrames = 0;
let winFrames = 0;
let timeLeft = ROUND_SECONDS;

let lastWinner = "none";
let winnerName = "none";

// ---- packed spawn (cramped) ----
function packedSpawn(names){
  balls.length = 0;
  alive = new Array(names.length).fill(true);
  aliveCount = names.length;

  // Fill inside ring with jittered grid so it's cramped:
  const innerR = RING_R - R - 6;
  const spacing = R * 1.9; // tighter = more collisions
  const startX = CX - innerR;
  const startY = CY - innerR;

  let idx=0;
  for(let y=startY; y<=CY+innerR && idx<names.length; y+=spacing){
    for(let x=startX; x<=CX+innerR && idx<names.length; x+=spacing){
      const dx=x-CX, dy=y-CY;
      if(dx*dx+dy*dy <= innerR*innerR){
        const jx = rand(-R*0.4, R*0.4);
        const jy = rand(-R*0.4, R*0.4);
        const name = names[idx];
        balls.push({
          name,
          col: randColor(),
          x: x+jx,
          y: y+jy,
          vx: rand(-SPEED,SPEED),
          vy: rand(-SPEED,SPEED),
          avatar: randColor(), // placeholder “profile image” color (replace with flag later)
        });
        idx++;
      }
    }
  }

  // If not enough spots (small ring), just drop remaining near center
  while(idx < names.length){
    balls.push({
      name: names[idx],
      col: randColor(),
      x: CX + rand(-innerR*0.2, innerR*0.2),
      y: CY + rand(-innerR*0.2, innerR*0.2),
      vx: rand(-SPEED,SPEED),
      vy: rand(-SPEED,SPEED),
      avatar: randColor(),
    });
    idx++;
  }
}

function getRoundPlayers(){
  // If there are chatters, next round is ONLY them (their chosen country, else their username)
  const players = [];
  for(const [u,info] of chatUsers.entries()){
    const label = info.country ? info.country : u.toUpperCase();
    players.push(label);
  }

  if(players.length > 0){
    // cap for performance
    return players.slice(0, Math.min(MAX_BALLS, players.length));
  }

  // fallback: default countries to fill
  const out=[];
  for(let i=0;i<MAX_BALLS;i++) out.push(COUNTRIES[i % COUNTRIES.length]);
  return out;
}

function startRound(){
  t = 0;
  roundFrames = 0;
  timeLeft = ROUND_SECONDS;

  const players = getRoundPlayers();
  packedSpawn(players);

  state = "PLAY";
}

startRound();

// ---------------- collisions grid ----------------
const cellSize = R*3;
const gridW = Math.ceil(W/cellSize);
const gridH = Math.ceil(H/cellSize);
const grid = new Array(gridW*gridH);

function gclear(){ grid.fill(null); }
function gidx(x,y){
  const gx=Math.max(0,Math.min(gridW-1,(x/cellSize)|0));
  const gy=Math.max(0,Math.min(gridH-1,(y/cellSize)|0));
  return gy*gridW+gx;
}
function gpush(i,x,y){
  const k=gidx(x,y);
  if(grid[k]==null) grid[k]=[i];
  else grid[k].push(i);
}

function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI)%360;

  gclear();
  for(let i=0;i<balls.length;i++){
    if(!alive[i]) continue;
    const b=balls[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
    gpush(i,b.x,b.y);
  }

  const minD = 2*R;
  const minD2 = minD*minD;

  for(let gy=0; gy<gridH; gy++){
    for(let gx=0; gx<gridW; gx++){
      const base = gy*gridW+gx;
      const cell = grid[base];
      if(!cell) continue;

      for(let oy=-1; oy<=1; oy++){
        for(let ox=-1; ox<=1; ox++){
          const nx=gx+ox, ny=gy+oy;
          if(nx<0||ny<0||nx>=gridW||ny>=gridH) continue;
          const other = grid[ny*gridW+nx];
          if(!other) continue;

          for(let ai=0; ai<cell.length; ai++){
            const i = cell[ai];
            if(!alive[i]) continue;
            const A = balls[i];

            for(let bj=0; bj<other.length; bj++){
              const j = other[bj];
              if(!alive[j]) continue;
              if(base === (ny*gridW+nx) && j<=i) continue;

              const B = balls[j];
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

  // boundary + hole kill
  const wallR = RING_R - R - 2;

  for(let i=0;i<balls.length;i++){
    if(!alive[i]) continue;
    const b=balls[i];

    const dx=b.x-CX, dy=b.y-CY;
    const dist=Math.sqrt(dx*dx+dy*dy)||0.0001;
    const angDeg=(Math.atan2(dy,dx)*180/Math.PI+360)%360;

    if(dist > wallR){
      if(inHole(angDeg, holeCenterDeg)){
        alive[i]=false;
        aliveCount--;
        continue;
      }
      const nxn=dx/dist, nyn=dy/dist;
      b.x = CX + nxn*wallR;
      b.y = CY + nyn*wallR;

      const vn=b.vx*nxn + b.vy*nyn;
      if(vn>0){
        b.vx -= 2*vn*nxn;
        b.vy -= 2*vn*nyn;
      }
      b.vx *= 0.994;
      b.vy *= 0.994;
    }

    b.vx *= 0.999;
    b.vy *= 0.999;
  }

  return holeCenterDeg;
}

function formatTime(sec){
  sec = Math.max(0, sec|0);
  const m=(sec/60)|0, s=sec%60;
  return String(m).padStart(2,'0') + ":" + String(s).padStart(2,'0');
}

const UI_BG=[35,55,80];
const UI_BG2=[20,32,50];
const UI_LINE=[90,120,150];
const WHITE=[255,255,255];
const YELLOW=[255,215,0];
const BLACK=[0,0,0];

function drawTopUI(){
  const pad=10, barH=58;
  drawPanel(pad,pad,W-pad*2,barH,UI_BG,UI_LINE);

  const cardH=40;
  const cardY=pad+9;
  const cardW=(W-pad*2 - 20)/3;

  // Left: last winner
  drawPanel(pad+6,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("LAST WINNER", pad+14, cardY+6, 1, [190,210,230]);
  drawText(String(lastWinner).slice(0,18), pad+14, cardY+20, 2, WHITE);

  // Middle: time/mode
  const cx0=pad+6+cardW;
  drawPanel(cx0,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("TIME", cx0+10, cardY+6, 1, [190,210,230]);
  drawText(`${formatTime(timeLeft)}/${formatTime(ROUND_SECONDS)}`, cx0+10, cardY+20, 2, YELLOW);
  drawText("MODE: THE LAST ONE WINS", cx0+220, cardY+10, 1, [210,230,245]);

  // Right: top chatter
  const rx0=pad+6+cardW*2;
  drawPanel(rx0,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("TOP CHATTER", rx0+10, cardY+6, 1, [190,210,230]);
  drawText(String(topChatter).slice(0,14), rx0+10, cardY+20, 2, WHITE);
}

function drawJoinText(){
  drawTextCentered("WRITE YOUR COUNTRY IN CHAT TO JOIN", W/2, 95, 2, BLACK);
  drawTextCentered("TYPE A COUNTRY NAME (EX: QATAR) - NEXT ROUND USES CHATTERS", W/2, 120, 1, [20,20,20]);
}

function drawProfileLabel(x,y,avatarCol,name){
  // [avatar]
  // NAME
  const boxW = Math.max(48, Math.min(90, name.length*6));
  const boxH = 28;
  const bx = (x - boxW/2)|0;
  const by = (y + R + 4)|0;

  // keep on screen
  const fx = Math.max(2, Math.min(W-boxW-2, bx));
  const fy = Math.max(70, Math.min(H-boxH-2, by));

  // box
  fillRect(fx, fy, boxW, boxH, [255,255,255]);
  rectOutline(fx, fy, boxW, boxH, [0,0,0]);

  // avatar placeholder (colored circle)
  const ax = fx + 10;
  const ay = fy + 9;
  for(let dy=-4;dy<=4;dy++){
    for(let dx=-4;dx<=4;dx++){
      if(dx*dx+dy*dy<=16) setPix(ax+dx, ay+dy, avatarCol[0], avatarCol[1], avatarCol[2]);
    }
  }
  rectOutline(ax-5, ay-5, 11, 11, [0,0,0]);

  // name (yellow)
  const label = String(name).toUpperCase().replace(/[^A-Z ]/g,' ').trim().slice(0,10);
  drawText(label, fx+22, fy+10, 1, YELLOW);
}

function renderPlay(holeCenterDeg){
  clearSky();
  drawTopUI();
  drawJoinText();
  drawRing(holeCenterDeg);

  // draw balls + labels
  for(let i=0;i<balls.length;i++){
    if(!alive[i]) continue;
    const b=balls[i];
    drawBall(b.x|0, b.y|0, b.col);

    // profile label (can cost CPU; still ok at 15fps)
    drawProfileLabel(b.x|0, b.y|0, b.avatar, b.name);
  }
}

function renderWin(){
  fillSolid(10,16,28);

  const panelW = Math.min(W-60, 760);
  const panelH = 280;
  const px = ((W-panelW)/2)|0;
  const py = 60;

  drawPanel(px,py,panelW,panelH,UI_BG,UI_LINE);

  drawTextCentered("ROUND SUMMARY", W/2, py+40, 3, WHITE);
  drawTextCentered("THE LAST ONE INSIDE THE ARENA WINS", W/2, py+70, 1, [210,230,245]);

  // Winner card
  const cardY = py+95;
  const cardW = panelW-40;
  const cardH = 160;
  drawPanel(px+20, cardY, cardW, cardH, UI_BG2, UI_LINE);

  drawText("WINNER:", px+35, cardY+25, 2, WHITE);
  drawText(String(winnerName).slice(0,26), px+150, cardY+25, 2, YELLOW);

  drawText("COUNTRY:", px+35, cardY+65, 1, [210,230,245]);
  drawText(String(winnerName).slice(0,30), px+130, cardY+63, 1, WHITE);

  drawText("TOP CHATTER:", px+35, cardY+90, 1, [210,230,245]);
  drawText(String(topChatter).slice(0,18), px+160, cardY+88, 1, WHITE);

  drawTextCentered("NEXT ROUND STARTING...", W/2, py+panelH+40, 2, [210,230,245]);
}

function getWinnerIndex(){
  for(let i=0;i<balls.length;i++) if(alive[i]) return i;
  return -1;
}

function tick(){
  if(state==="PLAY"){
    roundFrames++;
    if(roundFrames % FPS === 0) timeLeft--;

    const holeCenterDeg = stepPhysics();

    if(aliveCount <= 1 || timeLeft <= 0){
      const wi = getWinnerIndex();
      winnerName = wi>=0 ? balls[wi].name : "none";
      lastWinner = winnerName;

      // IMPORTANT: if there are chatters, "instantly start a round with all commenters"
      // We'll show win screen briefly; you can set WIN_SECONDS small (like 2) if you want instant.
      state="WIN";
      winFrames=0;
    } else {
      renderPlay(holeCenterDeg);
    }
  }

  if(state==="WIN"){
    winFrames++;
    renderWin();

    if(winFrames >= WIN_SECONDS * FPS){
      // start next round using current chatUsers (commenters)
      startRound();
    }
  }

  // write one frame
  const header = `P6\n${W} ${H}\n255\n`;
  const ok1 = process.stdout.write(header);
  const ok2 = process.stdout.write(buf);
  return ok1 && ok2;
}

// backpressure-safe loop
let busy=false;
function stepOnce(){
  if(busy) return;
  busy=true;
  const ok = tick();
  if(ok) busy=false;
  else process.stdout.once('drain', ()=>{ busy=false; });
}

setInterval(stepOnce, Math.round(1000/FPS));
JS

URL="rtmps://live.twitch.tv/app/${STREAM_KEY}"

node /tmp/sim.js | ffmpeg -hide_banner -loglevel info -stats \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -g 60 -b:v 2200k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "$URL"
