#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# ======= SETTINGS =======
FPS="${FPS:-20}"
W="${W:-854}"
H="${H:-480}"

BALLS="${BALLS:-200}"
BALL_R="${BALL_R:-10}"
RING_R="${RING_R:-160}"
HOLE_DEG="${HOLE_DEG:-70}"
SPIN="${SPIN:-0.9}"
SPEED="${SPEED:-90}"

export FPS W H BALLS BALL_R RING_R HOLE_DEG SPIN SPEED

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALLS=$BALLS BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED"
echo "STREAM_KEY length: ${#STREAM_KEY}"
node -v
ffmpeg -version | head -n 2
echo "====================="

URL="rtmps://live.twitch.tv/app/${STREAM_KEY}"

echo "=== STEP 1: QUICK TWITCH KEY TEST (10 seconds) ==="
# If this does NOT go live, your stream key / channel is the issue — not the game.
timeout 10 ffmpeg -hide_banner -loglevel info -stats \
  -f lavfi -i "testsrc=size=${W}x${H}:rate=${FPS}" \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "$URL" || true

echo "=== STEP 2: START GAME STREAM (FOREVER UNTIL RUNNER STOPS) ==="

cat > /tmp/sim.js <<'JS'
'use strict';

const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const N        = +process.env.BALLS  || 200;
const R        = +process.env.BALL_R || 10;
const RING_R   = +process.env.RING_R || 160;
const HOLE_DEG = +process.env.HOLE_DEG || 70;
const SPIN     = +process.env.SPIN || 0.9;
const SPEED    = +process.env.SPEED || 90;

const CX = W*0.5, CY = H*0.5;
const dt = 1/FPS;

const buf = Buffer.alloc(W*H*3);
function setPix(x,y,r,g,b){
  if (x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  buf[i]=r; buf[i+1]=g; buf[i+2]=b;
}
function clearWhite(){ buf.fill(255); }

function rndi(a,b){ return a + ((Math.random()*(b-a+1))|0); }
function rand(a,b){ return a + Math.random()*(b-a); }
function randColor(){ return [rndi(40,235), rndi(40,235), rndi(40,235)]; }

const TXT=[255,215,0]; // yellow

// simple 5x7 A-Z + space
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
  ' ':[0,0,0,0,0,0,0],
};

function drawChar(ch,x,y,scale,color){
  const rows = FONT[ch] || FONT[' '];
  const [r,g,b]=color;
  for(let rr=0;rr<7;rr++){
    const bits=rows[rr];
    for(let cc=0;cc<5;cc++){
      if(bits & (1<<(4-cc))){
        for(let sy=0;sy<scale;sy++)
          for(let sx=0;sx<scale;sx++)
            setPix(x+cc*scale+sx,y+rr*scale+sy,r,g,b);
      }
    }
  }
}
function drawTextFit(text,cx,cy,scale,color,maxW){
  text = text.toUpperCase();
  const charW=5*scale, gap=scale;
  const fit=Math.max(1, Math.floor((maxW+gap)/(charW+gap)));
  if(text.length>fit) text=text.slice(0,fit);
  const w=text.length*(charW+gap)-gap;
  const h=7*scale;
  let x=(cx-w/2)|0, y=(cy-h/2)|0;
  for(let i=0;i<text.length;i++){
    drawChar(text[i], x, y, scale, color);
    x += charW+gap;
  }
}

function fillCircle(cx,cy,rad,col){
  const [cr,cg,cb]=col;
  const r2=rad*rad;
  const x0=Math.max(0,(cx-rad)|0), x1=Math.min(W-1,(cx+rad)|0);
  const y0=Math.max(0,(cy-rad)|0), y1=Math.min(H-1,(cy+rad)|0);
  for(let y=y0;y<=y1;y++){
    const dy=y-cy;
    for(let x=x0;x<=x1;x++){
      const dx=x-cx;
      if(dx*dx+dy*dy<=r2) setPix(x,y,cr,cg,cb);
    }
  }
  for(let deg=0;deg<360;deg+=12){
    const a=deg*Math.PI/180;
    setPix((cx+Math.cos(a)*rad)|0,(cy+Math.sin(a)*rad)|0,0,0,0);
  }
}

function inHole(angleDeg, holeCenterDeg){
  const half=HOLE_DEG/2;
  let d=(angleDeg-holeCenterDeg+180)%360-180;
  return Math.abs(d)<=half;
}

const NAMES = [
  "AFGHANISTAN","ALBANIA","ALGERIA","ANDORRA","ANGOLA","ARGENTINA","ARMENIA","AUSTRALIA","AUSTRIA","AZERBAIJAN",
  "BAHRAIN","BANGLADESH","BELARUS","BELGIUM","BELIZE","BENIN","BHUTAN","BOLIVIA","BOSNIA","BOTSWANA",
  "BRAZIL","BRUNEI","BULGARIA","BURKINA FASO","BURUNDI","CAMBODIA","CAMEROON","CANADA","CHAD","CHILE",
  "CHINA","COLOMBIA","COSTA RICA","CROATIA","CUBA","CYPRUS","CZECHIA","DENMARK","DOMINICAN REP","ECUADOR",
  "EGYPT","EL SALVADOR","ESTONIA","ETHIOPIA","FINLAND","FRANCE","GEORGIA","GERMANY","GHANA","GREECE",
  "GUATEMALA","GUINEA","GUYANA","HAITI","HONDURAS","HUNGARY","ICELAND","INDIA","INDONESIA","IRAN",
  "IRAQ","IRELAND","ISRAEL","ITALY","JAMAICA","JAPAN","JORDAN","KAZAKHSTAN","KENYA","KOREA",
  "KUWAIT","KYRGYZSTAN","LAOS","LATVIA","LEBANON","LIBERIA","LIBYA","LITHUANIA","LUXEMBOURG","MADAGASCAR",
  "MALAWI","MALAYSIA","MALDIVES","MALI","MALTA","MAURITANIA","MAURITIUS","MEXICO","MOLDOVA","MONACO",
  "MONGOLIA","MONTENEGRO","MOROCCO","MOZAMBIQUE","MYANMAR","NAMIBIA","NEPAL","NETHERLANDS","NEW ZEALAND","NICARAGUA",
  "NIGER","NIGERIA","N MACEDONIA","NORWAY","OMAN","PAKISTAN","PANAMA","PAPUA N GUINEA","PARAGUAY","PERU",
  "PHILIPPINES","POLAND","PORTUGAL","QATAR","ROMANIA","RUSSIA","RWANDA","SAUDI ARABIA","SENEGAL","SERBIA",
  "SINGAPORE","SLOVAKIA","SLOVENIA","SOMALIA","SOUTH AFRICA","SPAIN","SRI LANKA","SUDAN","SWEDEN","SWITZERLAND",
  "SYRIA","TAIWAN","TAJIKISTAN","TANZANIA","THAILAND","TUNISIA","TURKIYE","TURKMENISTAN","UGANDA","UKRAINE",
  "UAE","UNITED KINGDOM","UNITED STATES","URUGUAY","UZBEKISTAN","VENEZUELA","VIETNAM","YEMEN","ZAMBIA","ZIMBABWE"
];

const balls = Array(N);
function spawn(i){
  const name = NAMES[i % NAMES.length];
  const col = randColor();
  const ang = Math.random()*Math.PI*2;
  const rad = Math.random()*(RING_R*0.45);
  balls[i]={
    name, col,
    x: CX + Math.cos(ang)*rad,
    y: CY + Math.sin(ang)*rad,
    vx: rand(-SPEED,SPEED),
    vy: rand(-SPEED,SPEED),
  };
}
for(let i=0;i<N;i++) spawn(i);

// grid accel
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

let t=0, frames=0, last=Date.now();

function step(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI)%360;

  gclear();
  for(let i=0;i<N;i++){
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
            const A=balls[i];
            for(let bj=0; bj<other.length; bj++){
              const j=other[bj];
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

  for(let i=0;i<N;i++){
    const b=balls[i];
    const dx=b.x-CX, dy=b.y-CY;
    const dist=Math.sqrt(dx*dx+dy*dy)||0.0001;
    const angDeg=(Math.atan2(dy,dx)*180/Math.PI+360)%360;

    if(dist>wallR){
      if(inHole(angDeg, holeCenterDeg)){
        spawn(i); // forever
        continue;
      }
      const nxn=dx/dist, nyn=dy/dist;
      b.x = CX + nxn*wallR;
      b.y = CY + nyn*wallR;
      const vn=b.vx*nxn + b.vy*nyn;
      if(vn>0){ b.vx -= 2*vn*nxn; b.vy -= 2*vn*nyn; }
      b.vx *= 0.996; b.vy *= 0.996;
    }
    b.vx *= 0.999; b.vy *= 0.999;
  }

  frames++;
  const now=Date.now();
  if(now-last>=5000){
    console.error(`[sim] fps=${FPS} frames=${frames} balls=${N} ringR=${RING_R} holeDeg=${HOLE_DEG}`);
    last=now;
  }
}

function drawRing(){
  const holeCenterDeg=(t*SPIN*180/Math.PI)%360;
  const thick=4;
  for(let deg=0; deg<360; deg+=1){
    if(inHole(deg,holeCenterDeg)) continue;
    const a=deg*Math.PI/180;
    const x=(CX+Math.cos(a)*RING_R)|0;
    const y=(CY+Math.sin(a)*RING_R)|0;
    for(let k=-thick;k<=thick;k++){
      setPix(x+k,y,0,0,0);
      setPix(x,y+k,0,0,0);
    }
  }
}

function render(){
  clearWhite();
  drawRing();
  for(let i=0;i<N;i++){
    const b=balls[i];
    fillCircle(b.x|0,b.y|0,R,b.col);
    drawTextFit(b.name, b.x|0, b.y|0, 1, TXT, (R*2-2));
  }
}

function writePPM(){
  process.stdout.write(`P6\n${W} ${H}\n255\n`);
  process.stdout.write(buf);
}

while(true){
  step();
  render();
  writePPM();
}
JS

# IMPORTANT: make ffmpeg print progress no matter what
node /tmp/sim.js | ffmpeg -hide_banner -loglevel info -stats \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 -b:v 2500k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "$URL"
