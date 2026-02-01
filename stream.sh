#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# ======= STREAM / GAME TUNING =======
export FPS="${FPS:-15}"          # lowered for smoothness
export W="${W:-854}"
export H="${H:-480}"

export BALLS="${BALLS:-200}"
export BALL_R="${BALL_R:-10}"
export RING_R="${RING_R:-160}"
export HOLE_DEG="${HOLE_DEG:-70}"
export SPIN="${SPIN:-0.9}"
export SPEED="${SPEED:-90}"

# round duration (seconds)
export ROUND_SECONDS="${ROUND_SECONDS:-120}"     # 02:00 like your screenshot
export WIN_SCREEN_SECONDS="${WIN_SCREEN_SECONDS:-10}"

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALLS=$BALLS BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED"
echo "ROUND_SECONDS=$ROUND_SECONDS WIN_SCREEN_SECONDS=$WIN_SCREEN_SECONDS"
echo "STREAM_KEY length: ${#STREAM_KEY}"
node -v
ffmpeg -version | head -n 2
echo "====================="

cat > /tmp/sim.js <<'JS'
'use strict';

/*
  Real-time frame generator @FPS with backpressure.
  Two states:
    - PLAY: balls fall out and die; timer counts down; last alive wins when <=1 or time runs out.
    - WIN: show round summary UI for a few seconds, then start next round.
*/

const FPS = +process.env.FPS || 15;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const N        = +process.env.BALLS  || 200;
const R        = +process.env.BALL_R || 10;
const RING_R   = +process.env.RING_R || 160;
const HOLE_DEG = +process.env.HOLE_DEG || 70;
const SPIN     = +process.env.SPIN || 0.9;
const SPEED    = +process.env.SPEED || 90;

const ROUND_SECONDS = +process.env.ROUND_SECONDS || 120;
const WIN_SECONDS   = +process.env.WIN_SCREEN_SECONDS || 10;

const CX = W*0.5, CY = H*0.5;
const dt = 1/FPS;

const buf = Buffer.alloc(W*H*3);

// ---------- drawing helpers ----------
function setPix(x,y,r,g,b){
  if (x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  buf[i]=r; buf[i+1]=g; buf[i+2]=b;
}
function fill(r,g,b){ buf.fill(0); for(let i=0;i<buf.length;i+=3){ buf[i]=r; buf[i+1]=g; buf[i+2]=b; } }
function clearWhite(){ buf.fill(255); }

function fillRect(x,y,w,h, col){
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
function rectOutline(x,y,w,h, col){
  const [r,g,b]=col;
  for(let i=0;i<w;i++){
    setPix(x+i,y,r,g,b);
    setPix(x+i,y+h-1,r,g,b);
  }
  for(let i=0;i<h;i++){
    setPix(x,y+i,r,g,b);
    setPix(x+w-1,y+i,r,g,b);
  }
}

// ---------- tiny font (5x7 A-Z 0-9 : / space) ----------
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
  ':':[0b00000,0b00100,0b00100,0b00000,0b00100,0b00100,0b00000],
  '/':[0b00001,0b00010,0b00100,0b01000,0b10000,0b00000,0b00000],
  ' ':[0,0,0,0,0,0,0],
  '-':[0,0,0b11111,0,0,0,0],
};

function drawChar(ch,x,y,scale,color){
  const rows=FONT[ch] || FONT[' '];
  const [r,g,b]=color;
  for(let rr=0; rr<7; rr++){
    const bits=rows[rr];
    for(let cc=0; cc<5; cc++){
      if(bits & (1<<(4-cc))){
        for(let sy=0; sy<scale; sy++){
          for(let sx=0; sx<scale; sx++){
            setPix(x+cc*scale+sx, y+rr*scale+sy, r,g,b);
          }
        }
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
  const w=textWidth(text,scale);
  const h=7*scale;
  drawText(text, (cx - w/2)|0, (cy - h/2)|0, scale, color);
}

// ---------- fast circle mask ----------
const circleMask = [];
for(let y=-R; y<=R; y++){
  const row=[];
  for(let x=-R; x<=R; x++){
    if(x*x+y*y <= R*R) row.push([x,y]);
  }
  circleMask.push(...row);
}
function drawBall(cx,cy,col){
  const [r,g,b]=col;
  const x0=cx|0, y0=cy|0;
  for(let k=0;k<circleMask.length;k++){
    const dx=circleMask[k][0], dy=circleMask[k][1];
    setPix(x0+dx, y0+dy, r,g,b);
  }
  // outline (cheap)
  for(let deg=0; deg<360; deg+=18){
    const a=deg*Math.PI/180;
    setPix((x0+Math.cos(a)*R)|0, (y0+Math.sin(a)*R)|0, 0,0,0);
  }
}

// ---------- game logic ----------
function rndi(a,b){ return a + ((Math.random()*(b-a+1))|0); }
function rand(a,b){ return a + Math.random()*(b-a); }
function randColor(){ return [rndi(40,235), rndi(40,235), rndi(40,235)]; }

function inHole(angleDeg, holeCenterDeg){
  const half = HOLE_DEG/2;
  let d = (angleDeg - holeCenterDeg + 180) % 360 - 180;
  return Math.abs(d) <= half;
}

// a compact set of country names (reused to reach 200)
const NAMES = [
  "AFGHANISTAN","ALBANIA","ALGERIA","ANDORRA","ANGOLA","ARGENTINA","ARMENIA","AUSTRALIA","AUSTRIA","AZERBAIJAN",
  "BAHRAIN","BANGLADESH","BELARUS","BELGIUM","BELIZE","BENIN","BHUTAN","BOLIVIA","BOSNIA","BOTSWANA",
  "BRAZIL","BRUNEI","BULGARIA","BURUNDI","CAMBODIA","CAMEROON","CANADA","CHAD","CHILE","CHINA",
  "COLOMBIA","CROATIA","CUBA","CYPRUS","CZECHIA","DENMARK","ECUADOR","EGYPT","ESTONIA","ETHIOPIA",
  "FINLAND","FRANCE","GEORGIA","GERMANY","GHANA","GREECE","GUATEMALA","GUINEA","GUYANA","HAITI",
  "HONDURAS","HUNGARY","ICELAND","INDIA","INDONESIA","IRAN","IRAQ","IRELAND","ISRAEL","ITALY",
  "JAMAICA","JAPAN","JORDAN","KENYA","KUWAIT","LAOS","LATVIA","LEBANON","LIBERIA","LIBYA",
  "LITHUANIA","LUXEMBOURG","MADAGASCAR","MALAWI","MALAYSIA","MALDIVES","MALI","MALTA","MEXICO","MOLDOVA",
  "MONACO","MONGOLIA","MOROCCO","MOZAMBIQUE","MYANMAR","NAMIBIA","NEPAL","NETHERLANDS","NORWAY","OMAN",
  "PAKISTAN","PANAMA","PARAGUAY","PERU","PHILIPPINES","POLAND","PORTUGAL","QATAR","ROMANIA","RUSSIA",
  "RWANDA","SAUDI ARABIA","SENEGAL","SERBIA","SINGAPORE","SLOVAKIA","SLOVENIA","SOMALIA","SPAIN","SUDAN",
  "SWEDEN","SWITZERLAND","SYRIA","TAIWAN","TANZANIA","THAILAND","TUNISIA","TURKIYE","UGANDA","UKRAINE",
  "UAE","UNITED KINGDOM","UNITED STATES","URUGUAY","UZBEKISTAN","VENEZUELA","VIETNAM","YEMEN","ZAMBIA","ZIMBABWE"
];

// balls
const balls = new Array(N);
let alive = new Array(N);
let aliveCount = N;

function resetRound(){
  alive.fill(true);
  aliveCount = N;
  for(let i=0;i<N;i++){
    const name = NAMES[i % NAMES.length];
    const col = randColor();
    const ang = Math.random()*Math.PI*2;
    const rad = Math.random()*(RING_R*0.45);
    balls[i] = {
      name,
      col,
      x: CX + Math.cos(ang)*rad,
      y: CY + Math.sin(ang)*rad,
      vx: rand(-SPEED,SPEED),
      vy: rand(-SPEED,SPEED),
    };
  }
}

const cellSize = R*3;
const gridW = Math.ceil(W / cellSize);
const gridH = Math.ceil(H / cellSize);
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

// UI theme colors (approx your screenshots)
const UI_BG   = [30, 45, 65];
const UI_BG2  = [20, 30, 45];
const UI_LINE = [80, 110, 140];
const WHITE   = [255,255,255];
const YELLOW  = [255,215,0];

let state = "PLAY";
let t = 0;
let roundFrame = 0;
let winFrame = 0;

let lastWinner = "none";

function formatTime(sec){
  sec = Math.max(0, sec|0);
  const m = (sec/60)|0;
  const s = sec%60;
  const mm = String(m).padStart(2,'0');
  const ss = String(s).padStart(2,'0');
  return `${mm}:${ss}`;
}

function drawTopUI(timeLeftSec){
  // Top bar container
  const pad=10;
  const barH=60;
  fillRect(pad, pad, W-pad*2, barH, UI_BG);

  // inner cards
  const cardH=42;
  const cardY=pad+9;
  const cardW=(W-pad*2 - 20)/3;

  // left card: last winner
  fillRect(pad+6, cardY, cardW-6, cardH, UI_BG2);
  rectOutline(pad+6, cardY, cardW-6, cardH, UI_LINE);
  drawText("LAST WINNER", pad+14, cardY+6, 1, [180,200,220]);
  drawText(String(lastWinner).slice(0,18), pad+14, cardY+22, 2, WHITE);

  // center card: time + mode
  const cx0 = pad+6+cardW;
  fillRect(cx0, cardY, cardW-6, cardH, UI_BG2);
  rectOutline(cx0, cardY, cardW-6, cardH, UI_LINE);
  drawText("TIME", cx0+10, cardY+6, 1, [180,200,220]);
  drawText(`${formatTime(timeLeftSec)}/${formatTime(ROUND_SECONDS)}`, cx0+10, cardY+22, 2, YELLOW);
  drawText("MODE: THE LAST ONE WINS", cx0+210, cardY+10, 1, [200,220,240]);

  // right card: top chatter (placeholder)
  const rx0 = pad+6+cardW*2;
  fillRect(rx0, cardY, cardW-6, cardH, UI_BG2);
  rectOutline(rx0, cardY, cardW-6, cardH, UI_LINE);
  drawText("TOP CHATTER", rx0+10, cardY+6, 1, [180,200,220]);
  drawText("none", rx0+10, cardY+22, 2, WHITE);
}

function drawJoinText(){
  // Big center text like your screenshot
  drawTextCentered("WRITE YOUR COUNTRY IN CHAT TO JOIN", W/2, 105, 2, [0,0,0]);
  drawTextCentered("MODE: LAST ONE INSIDE WINS", W/2, 135, 1, [40,40,40]);
}

function drawRing(holeCenterDeg){
  const thick=4;
  for(let deg=0; deg<360; deg+=1){
    if(inHole(deg, holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const x=(CX+Math.cos(a)*RING_R)|0;
    const y=(CY+Math.sin(a)*RING_R)|0;
    for(let k=-thick;k<=thick;k++){
      setPix(x+k,y,0,0,0);
      setPix(x,y+k,0,0,0);
    }
  }
}

function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI)%360;

  gclear();
  for(let i=0;i<N;i++){
    if(!alive[i]) continue;
    const b=balls[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
    gpush(i,b.x,b.y);
  }

  const minD=2*R, minD2=minD*minD;

  // collisions
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

  // ring boundary + hole death
  const wallR = RING_R - R - 2;

  for(let i=0;i<N;i++){
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
      b.vx *= 0.996; b.vy *= 0.996;
    }
    b.vx *= 0.999;
    b.vy *= 0.999;
  }

  return holeCenterDeg;
}

function renderPlay(holeCenterDeg, timeLeftSec){
  clearWhite();
  drawTopUI(timeLeftSec);
  drawJoinText();

  drawRing(holeCenterDeg);

  // draw alive balls
  for(let i=0;i<N;i++){
    if(!alive[i]) continue;
    const b=balls[i];
    drawBall(b.x|0, b.y|0, b.col);

    // yellow name inside (trimmed to fit)
    const maxChars = Math.max(2, Math.floor((R*2-2) / 6)); // approx
    const txt = b.name.replace(/[^A-Z ]/g,' ').toUpperCase().slice(0, maxChars);
    drawTextCentered(txt, b.x|0, b.y|0, 1, YELLOW);
  }

  // eliminated “stack” at bottom (like your screenshot vibe)
  const rows=4;
  const cols=60;
  const startY = H-100;
  const startX = 40;
  const gap = 6;
  let elim = N - aliveCount;
  for(let r=0;r<rows;r++){
    for(let c=0;c<cols;c++){
      const idx = r*cols + c;
      const x = startX + c*gap;
      const y = startY + r*gap;
      if(idx < elim){
        setPix(x,y,20,20,25);
        setPix(x+1,y,20,20,25);
        setPix(x,y+1,20,20,25);
        setPix(x+1,y+1,20,20,25);
      } else {
        setPix(x,y,180,200,220);
      }
    }
  }
}

function getWinnerIndex(){
  for(let i=0;i<N;i++) if(alive[i]) return i;
  return -1;
}

function renderWin(winnerName){
  // darker background like your 2nd screenshot
  fill(10, 16, 28);

  // main panel
  const panelW = Math.min(W-80, 720);
  const panelH = 260;
  const px = ((W-panelW)/2)|0;
  const py = 70;

  fillRect(px, py, panelW, panelH, UI_BG);
  rectOutline(px, py, panelW, panelH, UI_LINE);

  drawTextCentered("ROUND SUMMARY", W/2, py+35, 3, WHITE);
  drawTextCentered("THE LAST ONE INSIDE THE ARENA WINS", W/2, py+65, 1, [200,220,240]);

  // winner card left
  const cardY = py+90;
  const cardH = 140;
  const cardW = (panelW-30)/2;
  fillRect(px+10, cardY, cardW, cardH, UI_BG2);
  rectOutline(px+10, cardY, cardW, cardH, UI_LINE);

  drawText("WINNER", px+20, cardY+15, 2, WHITE);
  drawText(winnerName.slice(0,22), px+20, cardY+45, 2, YELLOW);
  drawText(`TOTAL ROUNDS: --`, px+20, cardY+85, 1, [200,220,240]);

  // details card right
  fillRect(px+20+cardW, cardY, cardW, cardH, UI_BG2);
  rectOutline(px+20+cardW, cardY, cardW, cardH, UI_LINE);

  drawText("COUNTRY:", px+30+cardW, cardY+20, 1, [200,220,240]);
  drawText(winnerName.slice(0,22), px+120+cardW, cardY+18, 1, WHITE);

  drawText("CAPITAL:", px+30+cardW, cardY+45, 1, [200,220,240]);
  drawText("--", px+120+cardW, cardY+43, 1, WHITE);

  drawText("POPULATION:", px+30+cardW, cardY+70, 1, [200,220,240]);
  drawText("--", px+140+cardW, cardY+68, 1, WHITE);

  drawText("ISO:", px+30+cardW, cardY+95, 1, [200,220,240]);
  drawText("--", px+120+cardW, cardY+93, 1, WHITE);

  drawText("CALLING CODE:", px+30+cardW, cardY+120, 1, [200,220,240]);
  drawText("--", px+170+cardW, cardY+118, 1, WHITE);

  // bottom pile (decor)
  drawTextCentered("NEXT ROUND STARTING...", W/2, py+panelH+40, 2, [200,220,240]);
}

// ---------- main loop control ----------
resetRound();

let timeLeft = ROUND_SECONDS;
let winnerName = "none";

function tick(){
  if(state==="PLAY"){
    // update timer
    roundFrame++;
    if(roundFrame % FPS === 0) timeLeft--;

    const holeCenterDeg = stepPhysics();

    // win conditions
    if(aliveCount <= 1 || timeLeft <= 0){
      const wi = getWinnerIndex();
      winnerName = (wi>=0) ? balls[wi].name : "none";
      lastWinner = winnerName;
      state="WIN";
      winFrame = 0;
    }

    renderPlay(holeCenterDeg, timeLeft);
  } else {
    winFrame++;
    renderWin(winnerName);
    if(winFrame >= WIN_SECONDS * FPS){
      // start next round
      t = 0;
      roundFrame = 0;
      timeLeft = ROUND_SECONDS;
      resetRound();
      state="PLAY";
    }
  }

  // write one frame
  const header = `P6\n${W} ${H}\n255\n`;
  const ok1 = process.stdout.write(header);
  const ok2 = process.stdout.write(buf);
  return ok1 && ok2;
}

// backpressure-safe scheduler
let busy=false;
function stepOnce(){
  if(busy) return;
  busy = true;
  const ok = tick();
  if(ok){
    busy = false;
  } else {
    process.stdout.once('drain', ()=>{ busy=false; });
  }
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
