#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# Chat (optional but recommended)
: "${TWITCH_OAUTH:=}"
: "${TWITCH_CHANNEL:=}"
: "${TWITCH_NICK:=}"   # IMPORTANT: must match the token account

export FPS="${FPS:-15}"
export W="${W:-854}"
export H="${H:-480}"

export BALLS="${BALLS:-200}"
export BALL_R="${BALL_R:-14}"
export RING_R="${RING_R:-125}"      # smaller circle, more cramped
export HOLE_DEG="${HOLE_DEG:-80}"
export SPIN="${SPIN:-1.2}"
export SPEED="${SPEED:-85}"
export PHYS_MULT="${PHYS_MULT:-3}"  # 3x faster physics

export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-6}"

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALLS=$BALLS BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED PHYS_MULT=$PHYS_MULT"
echo "WIN_SCREEN_SECONDS=$WIN_SCREEN_SECONDS"
echo "STREAM_KEY length: ${#STREAM_KEY}"
echo "TWITCH_CHAT: $([ -n "${TWITCH_OAUTH}" ] && [ -n "${TWITCH_CHANNEL}" ] && [ -n "${TWITCH_NICK}" ] && echo enabled || echo disabled)"
node -v
ffmpeg -version | head -n 2
echo "====================="

cat > /tmp/sim.js <<'JS'
'use strict';
const tls = require('tls');

const FPS = +process.env.FPS || 15;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const MAX_BALLS = +process.env.BALLS || 200;
const R        = +process.env.BALL_R || 14;
const RING_R   = +process.env.RING_R || 125;
const HOLE_DEG = +process.env.HOLE_DEG || 80;
const SPIN     = +process.env.SPIN || 1.2;
const SPEED    = +process.env.SPEED || 85;
const PHYS_MULT = +process.env.PHYS_MULT || 3;

const WIN_SECONDS = +process.env.WIN_SCREEN_SECONDS || 6;

const TWITCH_OAUTH   = process.env.TWITCH_OAUTH || "";
const TWITCH_CHANNEL = process.env.TWITCH_CHANNEL || "";
const TWITCH_NICK    = process.env.TWITCH_NICK || "";

const CX = W*0.5, CY = H*0.5;
const dt = (PHYS_MULT) / FPS; // <-- 3x faster physics

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
function clearSky(){ fillSolid(155,215,255); }
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

// ---------- deterministic “icon” & color ----------
function hashStr(s){
  s=String(s);
  let h=2166136261>>>0;
  for(let i=0;i<s.length;i++){
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619)>>>0;
  }
  return h>>>0;
}
function colorFromName(name){
  const h = hashStr(name);
  const r = 60 + (h & 0x7F);
  const g = 60 + ((h>>7) & 0x7F);
  const b = 60 + ((h>>14) & 0x7F);
  return [r,g,b];
}
function isoFromName(name){
  // simple iso-like icon: first 2 letters
  name = String(name).toUpperCase().replace(/[^A-Z]/g,'');
  if(name.length>=2) return name.slice(0,2);
  return "??";
}

// ---------- ball drawing ----------
const mask=[];
for(let y=-R;y<=R;y++) for(let x=-R;x<=R;x++) if(x*x+y*y<=R*R) mask.push([x,y]);

function drawBall(cx,cy,col){
  const [r,g,b]=col;
  const x0=cx|0, y0=cy|0;
  for(let k=0;k<mask.length;k++){
    const dx=mask[k][0], dy=mask[k][1];
    setPix(x0+dx,y0+dy,r,g,b);
  }
  for(let deg=0;deg<360;deg+=14){
    const a=deg*Math.PI/180;
    setPix((x0+Math.cos(a)*R)|0, (y0+Math.sin(a)*R)|0, 0,0,0);
  }
}

// ---------- ring ----------
function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}
function drawRing(holeCenterDeg){
  const thick=4;
  for(let deg=0;deg<360;deg+=1){
    if(inHole(deg, holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const x=(CX+Math.cos(a)*RING_R)|0;
    const y=(CY+Math.sin(a)*RING_R)|0;
    for(let k=-thick;k<=thick;k++){
      setPix(x+k,y,30,30,30);
      setPix(x,y+k,30,30,30);
    }
  }
}

// ---------- UI ----------
const UI_BG=[35,55,80];
const UI_BG2=[20,32,50];
const UI_LINE=[90,120,150];
const WHITE=[255,255,255];
const YELLOW=[255,215,0];

let topChatter="none";
let lastWinner="none";

function drawPanel(x,y,w,h,fillCol,lineCol){
  fillRect(x,y,w,h,fillCol);
  rectOutline(x,y,w,h,lineCol);
}
function drawTopUI(aliveCount, total){
  const pad=10, barH=58;
  drawPanel(pad,pad,W-pad*2,barH,UI_BG,UI_LINE);

  const cardH=40;
  const cardY=pad+9;
  const cardW=(W-pad*2 - 20)/3;

  drawPanel(pad+6,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("LAST WINNER", pad+14, cardY+6, 1, [190,210,230]);
  drawText(String(lastWinner).slice(0,18), pad+14, cardY+20, 2, WHITE);

  const cx0=pad+6+cardW;
  drawPanel(cx0,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("ALIVE", cx0+10, cardY+6, 1, [190,210,230]);
  drawText(`${aliveCount}/${total}`, cx0+10, cardY+20, 2, YELLOW);
  drawText("MODE: LAST ONE WINS", cx0+220, cardY+10, 1, [210,230,245]);

  const rx0=pad+6+cardW*2;
  drawPanel(rx0,cardY,cardW-6,cardH,UI_BG2,UI_LINE);
  drawText("TOP CHATTER", rx0+10, cardY+6, 1, [190,210,230]);
  drawText(String(topChatter).slice(0,14), rx0+10, cardY+20, 2, WHITE);
}
function drawJoinText(){
  drawTextCentered("WRITE YOUR COUNTRY IN CHAT TO JOIN", W/2, 95, 2, [0,0,0]);
}

// profile label: [ISO] + NAME (ready to become image+name later)
function drawProfileLabel(x,y,iso,name){
  const label = String(name).toUpperCase().replace(/[^A-Z ]/g,' ').trim().slice(0,12);
  const boxW = Math.max(72, Math.min(120, label.length*6 + 32));
  const boxH = 28;

  let bx = (x - boxW/2)|0;
  let by = (y + R + 4)|0;

  bx = Math.max(2, Math.min(W-boxW-2, bx));
  by = Math.max(70, Math.min(H-boxH-2, by));

  fillRect(bx,by,boxW,boxH,[255,255,255]);
  rectOutline(bx,by,boxW,boxH,[0,0,0]);

  // “icon” placeholder square
  fillRect(bx+6, by+6, 16, 16, [0,0,0]);
  drawText(iso, bx+8, by+10, 1, [255,255,255]);

  drawText(label, bx+26, by+10, 1, [255,215,0]);
}

// ---------- chat ----------
const countrySet = new Set([
  "QATAR","EGYPT","SAUDI ARABIA","UAE","OMAN","TUNISIA","MOROCCO","ALGERIA","JORDAN","LEBANON",
  "UNITED STATES","UNITED KINGDOM","FRANCE","GERMANY","SPAIN","ITALY","CANADA","BRAZIL","ARGENTINA",
  "CHINA","INDIA","JAPAN","KOREA","TURKIYE","RUSSIA","UKRAINE","POLAND","NETHERLANDS","SWEDEN","NORWAY"
]);

function normalizeCountry(s){
  s=String(s||"").toUpperCase().replace(/[^A-Z ]/g,' ').replace(/\s+/g,' ').trim();
  if(countrySet.has(s)) return s;
  // partial match
  if(s.length>=3){
    for(const c of countrySet) if(c.startsWith(s)) return c;
  }
  return null;
}

const chatUsers = new Map(); // user -> {msgs, country}
function updateTopChatter(){
  let best=null, bestN=-1;
  for(const [u,info] of chatUsers.entries()){
    if(info.msgs>bestN){ bestN=info.msgs; best=u; }
  }
  topChatter = best ? best : "none";
}

function startTwitchChat(){
  if(!TWITCH_OAUTH || !TWITCH_CHANNEL || !TWITCH_NICK) return;

  const sock = tls.connect(6697, 'irc.chat.twitch.tv', { rejectUnauthorized:false }, () => {
    sock.write(`PASS ${TWITCH_OAUTH}\r\n`);
    sock.write(`NICK ${TWITCH_NICK}\r\n`);
    sock.write(`JOIN #${TWITCH_CHANNEL}\r\n`);
    console.error(`[chat] connected to #${TWITCH_CHANNEL} as ${TWITCH_NICK}`);
  });

  let acc='';
  sock.on('data', (d)=>{
    acc += d.toString('utf8');
    let idx;
    while((idx=acc.indexOf('\r\n'))>=0){
      let line = acc.slice(0,idx);
      acc = acc.slice(idx+2);

      if(line.startsWith('PING')){
        sock.write('PONG :tmi.twitch.tv\r\n');
        continue;
      }

      // Strip tags if present: "@tag=...;tag=... :user!user@... PRIVMSG #chan :msg"
      if(line[0]==='@'){
        const sp=line.indexOf(' ');
        if(sp>0) line=line.slice(sp+1);
      }

      const m = line.match(/^:([^!]+)![^ ]+ PRIVMSG #[^ ]+ :(.+)$/);
      if(m){
        const user = m[1].toLowerCase();
        const msg  = m[2];

        const info = chatUsers.get(user) || { msgs:0, country:null };
        info.msgs++;

        const c = normalizeCountry(msg);
        if(c) info.country = c;

        chatUsers.set(user, info);
        updateTopChatter();
      }
    }
  });
  sock.on('error', e=>console.error('[chat] error', e.message));
  sock.on('end', ()=>console.error('[chat] ended'));
}
startTwitchChat();

// ---------- game ----------
function rand(a,b){ return a + Math.random()*(b-a); }

let balls=[], alive=[], aliveCount=0;
let state="PLAY";
let t=0;
let winFrames=0;
let winnerName="none";

function getRoundPlayers(){
  const players=[];
  for(const [u,info] of chatUsers.entries()){
    players.push(info.country ? info.country : u.toUpperCase());
  }
  if(players.length>0) return players.slice(0, Math.min(MAX_BALLS, players.length));

  // fallback fill
  const defaults = Array.from(countrySet);
  const out=[];
  for(let i=0;i<MAX_BALLS;i++) out.push(defaults[i % defaults.length]);
  return out;
}

// cramped spawn
function startRound(){
  const names=getRoundPlayers();
  balls=[]; alive=new Array(names.length).fill(true); aliveCount=names.length;

  const innerR = RING_R - R - 6;
  const spacing = R * 1.75; // tighter = more collisions
  const sx = CX - innerR;
  const sy = CY - innerR;

  let idx=0;
  for(let y=sy; y<=CY+innerR && idx<names.length; y+=spacing){
    for(let x=sx; x<=CX+innerR && idx<names.length; x+=spacing){
      const dx=x-CX, dy=y-CY;
      if(dx*dx+dy*dy <= innerR*innerR){
        const name=names[idx++];
        balls.push({
          name,
          iso: isoFromName(name),
          col: colorFromName(name),
          x: x + rand(-R*0.35, R*0.35),
          y: y + rand(-R*0.35, R*0.35),
          vx: rand(-SPEED,SPEED),
          vy: rand(-SPEED,SPEED),
        });
      }
    }
  }
  while(idx<names.length){
    const name=names[idx++];
    balls.push({
      name,
      iso: isoFromName(name),
      col: colorFromName(name),
      x: CX + rand(-innerR*0.15, innerR*0.15),
      y: CY + rand(-innerR*0.15, innerR*0.15),
      vx: rand(-SPEED,SPEED),
      vy: rand(-SPEED,SPEED),
    });
  }

  state="PLAY";
  t=0;
}
startRound();

// grid for collisions
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
  if(grid[k]==null) grid[k]=[i]; else grid[k].push(i);
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
            const i=cell[ai];
            if(!alive[i]) continue;
            const A=balls[i];

            for(let bj=0; bj<other.length; bj++){
              const j=other[bj];
              if(!alive[j]) continue;
              if(base===(ny*gridW+nx) && j<=i) continue;

              const B=balls[j];
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

  const wallR = RING_R - R - 2;
  for(let i=0;i<balls.length;i++){
    if(!alive[i]) continue;
    const b=balls[i];

    const dx=b.x-CX, dy=b.y-CY;
    const dist=Math.sqrt(dx*dx+dy*dy)||0.0001;
    const angDeg=(Math.atan2(dy,dx)*180/Math.PI+360)%360;

    if(dist>wallR){
      if(inHole(angDeg, holeCenterDeg)){
        alive[i]=false;
        aliveCount--;
        continue;
      }
      const nxn=dx/dist, nyn=dy/dist;
      b.x = CX + nxn*wallR;
      b.y = CY + nyn*wallR;

      const vn=b.vx*nxn + b.vy*nyn;
      if(vn>0){ b.vx -= 2*vn*nxn; b.vy -= 2*vn*nyn; }
      b.vx *= 0.994; b.vy *= 0.994;
    }
    b.vx *= 0.999; b.vy *= 0.999;
  }

  return holeCenterDeg;
}

function renderPlay(holeCenterDeg){
  clearSky();
  drawTopUI(aliveCount, balls.length);
  drawJoinText();
  drawRing(holeCenterDeg);

  // labels are a bit heavy; still ok @15fps but we can cap if needed
  for(let i=0;i<balls.length;i++){
    if(!alive[i]) continue;
    const b=balls[i];
    drawBall(b.x|0, b.y|0, b.col);
    // “icon”: ISO in the ball center
    drawTextCentered(b.iso, b.x|0, b.y|0, 1, [255,255,255]);
    // profile label under ball
    drawProfileLabel(b.x|0, b.y|0, b.iso, b.name);
  }
}

function renderWin(){
  fillSolid(10,16,28);
  const panelW=Math.min(W-60,760), panelH=240;
  const px=((W-panelW)/2)|0, py=70;

  drawPanel(px,py,panelW,panelH,UI_BG,UI_LINE);
  drawTextCentered("ROUND SUMMARY", W/2, py+45, 3, WHITE);
  drawTextCentered("THE LAST ONE INSIDE THE ARENA WINS", W/2, py+75, 1, [210,230,245]);

  drawPanel(px+20, py+100, panelW-40, 110, UI_BG2, UI_LINE);
  drawText("WINNER:", px+35, py+130, 2, WHITE);
  drawText(String(winnerName).slice(0,26), px+170, py+130, 2, YELLOW);

  drawTextCentered("NEXT ROUND STARTING...", W/2, py+panelH+40, 2, [210,230,245]);
}

function getWinnerIndex(){
  for(let i=0;i<balls.length;i++) if(alive[i]) return i;
  return -1;
}

// ---------- frame writer (FIXES “Invalid maxval: 0”) ----------
const headerBuf = Buffer.from(`P6\n${W} ${H}\n255\n`);
const frameBuf = Buffer.alloc(headerBuf.length + rgb.length);

function writeFrameAtomic(){
  headerBuf.copy(frameBuf, 0);
  rgb.copy(frameBuf, headerBuf.length);
  return process.stdout.write(frameBuf);
}

// ---------- main loop ----------
let busy=false;
let winFrames=0;

function tick(){
  if(state==="PLAY"){
    const holeCenterDeg = stepPhysics();

    if(aliveCount <= 1){
      const wi=getWinnerIndex();
      winnerName = wi>=0 ? balls[wi].name : "none";
      lastWinner = winnerName;
      state="WIN";
      winFrames=0;
      renderWin();
    } else {
      renderPlay(holeCenterDeg);
    }
  } else {
    winFrames++;
    renderWin();
    if(winFrames >= WIN_SECONDS*FPS){
      startRound();
    }
  }
}

function stepOnce(){
  if(busy) return;
  busy=true;
  tick();
  const ok = writeFrameAtomic();
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
