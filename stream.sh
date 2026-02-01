#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY is missing}"

# ======= TUNING (safe defaults) =======
export FPS="${FPS:-15}"
export W="${W:-640}"
export H="${H:-360}"

export BALLS="${BALLS:-200}"     # 200 country-balls
export BALL_R="${BALL_R:-8}"     # smaller ball radius for performance
export RING_R="${RING_R:-120}"   # slightly small so many can fall
export HOLE_DEG="${HOLE_DEG:-80}"# hole size in degrees
export SPIN="${SPIN:-1.2}"       # rad/sec hole rotation
export SPEED="${SPEED:-85}"      # initial speed

echo "=== RUN SETTINGS ==="
echo "FPS=$FPS  SIZE=${W}x${H}  BALLS=$BALLS  BALL_R=$BALL_R  RING_R=$RING_R  HOLE_DEG=$HOLE_DEG  SPIN=$SPIN  SPEED=$SPEED"
echo "STREAM_KEY length: ${#STREAM_KEY}"
node -v
ffmpeg -version | head -n 2
echo "===================="

cat > /tmp/sim.js <<'JS'
'use strict';

/*
  Emits endless PPM (P6) frames to stdout.
  IMPORTANT: never console.log() to stdout. Use console.error for debug.
*/

const FPS = +process.env.FPS || 15;
const W   = +process.env.W   || 640;
const H   = +process.env.H   || 360;

const N        = +process.env.BALLS  || 200;
const BALL_R   = +process.env.BALL_R || 8;
const RING_R   = +process.env.RING_R || 120;
const HOLE_DEG = +process.env.HOLE_DEG || 80;
const SPIN     = +process.env.SPIN  || 1.2;     // rad/sec
const SPEED    = +process.env.SPEED || 85;

const CX = (W * 0.5);
const CY = (H * 0.5);

const dt = 1 / FPS;

// Country-code pool (200-ish). Repeat if fewer than N.
const CODES = (
  "AF AL DZ AD AO AG AR AM AU AT AZ BS BH BD BB BY BE BZ BJ BT BO BA BW BR BN BG BF BI KH CM CA CV CF TD CL CN CO KM CG CR CI HR CU CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IR IQ IE IL IT JM JP JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU MG MW MY MV ML MT MR MU MX MD MC MN ME MA MZ MM NA NR NP NL NZ NI NE NG MK NO OM PK PW PA PG PY PE PH PL PT QA RO RU RW KN LC VC WS SM ST SA SN RS SC SL SG SK SI SB SO ZA ES LK SD SR SE CH SY TW TJ TZ TH TL TG TO TT TN TR TM UG UA AE GB US UY UZ VU VE VN YE ZM ZW"
).trim().split(/\s+/);

// 5x7 bitmap font (A-Z only; enough for 2-letter codes)
const FONT = {
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
};

function rnd(a,b){ return a + Math.random()*(b-a); }
function rndi(a,b){ return (a + Math.floor(Math.random()*(b-a+1))); }
function randColor(){ return [rndi(40,235), rndi(40,235), rndi(40,235)]; }

// Framebuffer
const buf = Buffer.alloc(W*H*3);

// Pixel helpers
function setPix(x,y,r,g,b){
  if (x<0||y<0||x>=W||y>=H) return;
  const i = (y*W + x)*3;
  buf[i]=r; buf[i+1]=g; buf[i+2]=b;
}
function clearWhite(){ buf.fill(255); }

function fillCircle(cx,cy,r,col){
  const [cr,cg,cb]=col;
  const r2=r*r;
  const x0=Math.max(0,(cx-r)|0), x1=Math.min(W-1,(cx+r)|0);
  const y0=Math.max(0,(cy-r)|0), y1=Math.min(H-1,(cy+r)|0);
  for(let y=y0;y<=y1;y++){
    const dy=y-cy;
    for(let x=x0;x<=x1;x++){
      const dx=x-cx;
      if(dx*dx+dy*dy<=r2) setPix(x,y,cr,cg,cb);
    }
  }
  // outline
  for(let deg=0;deg<360;deg+=12){
    const a=deg*Math.PI/180;
    setPix((cx+Math.cos(a)*r)|0,(cy+Math.sin(a)*r)|0,0,0,0);
  }
}

function drawChar(ch,x,y,scale){
  const rows=FONT[ch];
  if(!rows) return;
  for(let r=0;r<7;r++){
    const bits=rows[r];
    for(let c=0;c<5;c++){
      if(bits & (1<<(4-c))){
        for(let sy=0;sy<scale;sy++)
          for(let sx=0;sx<scale;sx++)
            setPix(x+c*scale+sx,y+r*scale+sy,0,0,0);
      }
    }
  }
}

function drawCode(code,cx,cy){
  const s=2;
  const w = 2*5*s + 2*s;
  const x=(cx - w/2)|0;
  const y=(cy - (7*s)/2)|0;
  drawChar(code[0], x, y, s);
  drawChar(code[1], x+5*s+2*s, y, s);
}

function inHole(angleDeg, holeCenterDeg){
  const half = HOLE_DEG/2;
  let d = (angleDeg - holeCenterDeg + 180) % 360 - 180;
  return Math.abs(d) <= half;
}

// Balls
const balls = Array(N);
function spawnBall(i){
  const code = CODES[i % CODES.length];
  const col  = randColor();
  const ang  = Math.random()*Math.PI*2;
  const rad  = Math.random()*(RING_R*0.45);
  const x    = CX + Math.cos(ang)*rad;
  const y    = CY + Math.sin(ang)*rad;
  balls[i] = {
    code, col,
    x, y,
    vx: rnd(-SPEED, SPEED),
    vy: rnd(-SPEED, SPEED),
  };
}
for(let i=0;i<N;i++) spawnBall(i);

// Spatial grid for collisions (much faster than O(n^2))
const cellSize = BALL_R*3;
const gridW = Math.ceil(W / cellSize);
const gridH = Math.ceil(H / cellSize);
let grid = new Array(gridW*gridH);

function gridClear(){
  grid.fill(null);
}
function gridIndex(x,y){
  const cx = Math.max(0, Math.min(gridW-1, (x/cellSize)|0));
  const cy = Math.max(0, Math.min(gridH-1, (y/cellSize)|0));
  return cy*gridW + cx;
}
function gridPush(i, x, y){
  const idx = gridIndex(x,y);
  if (grid[idx] === null) grid[idx] = [i];
  else grid[idx].push(i);
}

let t = 0;
let frameCount = 0;
let lastReport = Date.now();

function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;

  // integrate & put into grid
  gridClear();
  for(let i=0;i<N;i++){
    const b=balls[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
    gridPush(i, b.x, b.y);
  }

  // collisions using neighbors
  const minD = BALL_R*2;
  const minD2 = minD*minD;

  for(let cy=0; cy<gridH; cy++){
    for(let cx=0; cx<gridW; cx++){
      const base = cy*gridW + cx;
      const cell = grid[base];
      if(!cell) continue;

      // check this cell against itself and 8 neighbors
      for(let oy=-1; oy<=1; oy++){
        for(let ox=-1; ox<=1; ox++){
          const nx = cx+ox, ny = cy+oy;
          if(nx<0||ny<0||nx>=gridW||ny>=gridH) continue;
          const other = grid[ny*gridW + nx];
          if(!other) continue;

          for(let ai=0; ai<cell.length; ai++){
            const i = cell[ai];
            const A = balls[i];
            // if same cell, avoid double double-check by only pairing j>i
            for(let bj=0; bj<other.length; bj++){
              const j = other[bj];
              if (base === (ny*gridW + nx) && j <= i) continue;

              const B = balls[j];
              const dx = B.x - A.x, dy = B.y - A.y;
              const d2 = dx*dx + dy*dy;
              if(d2 > 0 && d2 < minD2){
                const d = Math.sqrt(d2);
                const nxn = dx/d, nyn = dy/d;
                const overlap = (minD - d);

                // separate
                A.x -= nxn*overlap*0.5; A.y -= nyn*overlap*0.5;
                B.x += nxn*overlap*0.5; B.y += nyn*overlap*0.5;

                // elastic impulse (equal mass)
                const rvx = B.vx - A.vx, rvy = B.vy - A.vy;
                const vn = rvx*nxn + rvy*nyn;
                if(vn < 0){
                  const imp = -vn; // near-elastic
                  const ix = imp*nxn, iy = imp*nyn;
                  A.vx -= ix; A.vy -= iy;
                  B.vx += ix; B.vy += iy;
                }
              }
            }
          }
        }
      }
    }
  }

  // ring boundary & hole escape
  const wallR = RING_R - BALL_R - 1;

  for(let i=0;i<N;i++){
    const b=balls[i];
    const dx = b.x - CX, dy = b.y - CY;
    const dist = Math.sqrt(dx*dx + dy*dy) || 0.0001;
    const angDeg = (Math.atan2(dy, dx)*180/Math.PI + 360) % 360;

    if(dist > wallR){
      if(inHole(angDeg, holeCenterDeg)){
        // escaped through hole: respawn forever
        spawnBall(i);
        continue;
      }
      // bounce
      const nxn = dx/dist, nyn = dy/dist;
      b.x = CX + nxn*wallR;
      b.y = CY + nyn*wallR;

      const vn = b.vx*nxn + b.vy*nyn;
      if(vn > 0){
        b.vx -= 2*vn*nxn;
        b.vy -= 2*vn*nyn;
      }
      b.vx *= 0.996;
      b.vy *= 0.996;
    }

    // mild damping to keep speeds sane
    b.vx *= 0.999;
    b.vy *= 0.999;
  }

  // liveness report to stderr (safe)
  frameCount++;
  const now = Date.now();
  if (now - lastReport >= 5000){
    console.error(`[sim] fps_target=${FPS} frames=${frameCount} holeDeg=${HOLE_DEG} ringR=${RING_R} balls=${N}`);
    lastReport = now;
  }
}

function drawRing(){
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;
  const thick = 4;

  for(let deg=0;deg<360;deg+=1){
    if(inHole(deg, holeCenterDeg)) continue;
    const a = deg*Math.PI/180;
    const x = (CX + Math.cos(a)*RING_R)|0;
    const y = (CY + Math.sin(a)*RING_R)|0;
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
    fillCircle(b.x|0, b.y|0, BALL_R, b.col);
    drawCode(b.code, b.x|0, b.y|0);
  }
}

function writePPM(){
  process.stdout.write(`P6\n${W} ${H}\n255\n`);
  process.stdout.write(buf);
}

// Forever loop
while(true){
  stepPhysics();
  render();
  writePPM();
}
JS

# Pipe frames -> FFmpeg -> Twitch
# NOTE: Do NOT print anything else to stdout or it will corrupt the video pipe.
node /tmp/sim.js | ffmpeg -loglevel info \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -g 60 -b:v 2200k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmps://live.twitch.tv/app/${STREAM_KEY}"
