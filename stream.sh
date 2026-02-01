#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?Missing STREAM_KEY}"

FPS="${FPS:-20}"
W="${W:-854}"
H="${H:-480}"

# Ball + ring tuning
BALLS="${BALLS:-200}"
RING_R="${RING_R:-160}"          # small-ish so some fall out
HOLE_DEG="${HOLE_DEG:-70}"       # bigger hole => more falls
SPIN="${SPIN:-0.9}"              # rad/sec, hole rotates

cat > /tmp/sim.js <<'JS'
/* Minimal physics + PPM renderer (no deps). */
'use strict';

const fs = require('fs');

const FPS = parseInt(process.env.FPS || '20', 10);
const W   = parseInt(process.env.W   || '854', 10);
const H   = parseInt(process.env.H   || '480', 10);

const N   = parseInt(process.env.BALLS || '200', 10);
const RING_R = parseFloat(process.env.RING_R || '160');
const HOLE_DEG = parseFloat(process.env.HOLE_DEG || '70');
const SPIN = parseFloat(process.env.SPIN || '0.9');

const CX = (W/2)|0, CY = (H/2)|0;

// Simple country-code pool (200-ish). You can replace/extend this list anytime.
const CODES = (
  "AF AL DZ AD AO AG AR AM AU AT AZ BS BH BD BB BY BE BZ BJ BT BO BA BW BR BN BG BF BI KH CM CA CV CF TD CL CN CO KM CG CR CI HR CU CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IR IQ IE IL IT JM JP JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU MG MW MY MV ML MT MR MU MX MD MC MN ME MA MZ MM NA NR NP NL NZ NI NE NG MK NO OM PK PW PA PG PY PE PH PL PT QA RO RU RW KN LC VC WS SM ST SA SN RS SC SL SG SK SI SB SO ZA ES LK SD SR SE CH SY TW TJ TZ TH TL TG TO TT TN TR TM UG UA AE GB US UY UZ VU VE VN YE ZM ZW"
).trim().split(/\s+/);

// --- tiny 5x7 bitmap font for A-Z0-9 (only need letters) ---
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

function randInt(a,b){ return (a + Math.floor(Math.random()*(b-a+1))); }
function randColor(){
  return [randInt(40,235), randInt(40,235), randInt(40,235)];
}

// framebuffer RGB
const buf = Buffer.alloc(W*H*3);

// balls
const balls = [];
const BALL_R = 10;        // keep small for 200
const SPEED = 70;

function spawnBall(i){
  const code = CODES[i % CODES.length];
  const col = randColor();
  // spawn near center
  const ang = Math.random()*Math.PI*2;
  const rad = Math.random()*(RING_R*0.45);
  const x = CX + Math.cos(ang)*rad;
  const y = CY + Math.sin(ang)*rad;
  balls[i] = {
    code, col,
    x, y,
    vx: (Math.random()*2-1)*SPEED,
    vy: (Math.random()*2-1)*SPEED,
  };
}
for (let i=0;i<N;i++) spawnBall(i);

function clearWhite(){
  buf.fill(255);
}

function setPix(x,y,r,g,b){
  if (x<0||y<0||x>=W||y>=H) return;
  const idx = (y*W + x)*3;
  buf[idx]=r; buf[idx+1]=g; buf[idx+2]=b;
}

function fillCircle(cx,cy,r, col){
  const [cr,cg,cb] = col;
  const r2 = r*r;
  const x0 = Math.max(0, (cx-r)|0), x1 = Math.min(W-1, (cx+r)|0);
  const y0 = Math.max(0, (cy-r)|0), y1 = Math.min(H-1, (cy+r)|0);
  for (let y=y0; y<=y1; y++){
    const dy = y - cy;
    for (let x=x0; x<=x1; x++){
      const dx = x - cx;
      if (dx*dx + dy*dy <= r2){
        setPix(x,y, cr,cg,cb);
      }
    }
  }
  // outline
  const o = [0,0,0];
  for (let t=0;t<360;t+=6){
    const a = t*Math.PI/180;
    const x = (cx + Math.cos(a)*r)|0;
    const y = (cy + Math.sin(a)*r)|0;
    setPix(x,y, o[0],o[1],o[2]);
  }
}

function drawChar(ch, x, y, scale=2){
  const rows = FONT[ch];
  if (!rows) return;
  for (let r=0;r<7;r++){
    const bits = rows[r];
    for (let c=0;c<5;c++){
      if (bits & (1<<(4-c))){
        for (let sy=0;sy<scale;sy++)
          for (let sx=0;sx<scale;sx++)
            setPix(x + c*scale + sx, y + r*scale + sy, 0,0,0);
      }
    }
  }
}
function drawText2(code, cx, cy){
  // code like "EG"
  const scale=2;
  const w = 2*5*scale + 2*scale;
  const x = (cx - (w/2))|0;
  const y = (cy - 7*scale/2)|0;
  drawChar(code[0], x, y, scale);
  drawChar(code[1], x + 5*scale + 2*scale, y, scale);
}

// ring boundary + hole
function inHole(angleDeg, holeCenterDeg){
  const half = HOLE_DEG/2;
  let d = (angleDeg - holeCenterDeg + 180) % 360 - 180;
  return Math.abs(d) <= half;
}

const dt = 1/FPS;
let t = 0;

function stepPhysics(){
  // rotate hole center with "spin"
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;

  // integrate
  for (let i=0;i<N;i++){
    const b = balls[i];
    b.x += b.vx*dt;
    b.y += b.vy*dt;
  }

  // ball-ball collisions (naive O(n^2), ok for 200)
  for (let i=0;i<N;i++){
    const a = balls[i];
    for (let j=i+1;j<N;j++){
      const b = balls[j];
      const dx = b.x - a.x, dy = b.y - a.y;
      const dist2 = dx*dx + dy*dy;
      const minD = BALL_R*2;
      if (dist2 > 0 && dist2 < minD*minD){
        const dist = Math.sqrt(dist2);
        const nx = dx/dist, ny = dy/dist;
        const overlap = (minD - dist);

        // separate
        a.x -= nx*overlap*0.5; a.y -= ny*overlap*0.5;
        b.x += nx*overlap*0.5; b.y += ny*overlap*0.5;

        // elastic impulse (equal mass)
        const rvx = b.vx - a.vx, rvy = b.vy - a.vy;
        const vn = rvx*nx + rvy*ny;
        if (vn < 0){
          const impulse = -(1.0)*vn; // elasticity=1-ish
          const ix = impulse*nx, iy = impulse*ny;
          a.vx -= ix; a.vy -= iy;
          b.vx += ix; b.vy += iy;
        }
      }
    }
  }

  // ring collision: keep inside circle except where the hole is
  for (let i=0;i<N;i++){
    const b = balls[i];
    const dx = b.x - CX, dy = b.y - CY;
    const dist = Math.sqrt(dx*dx + dy*dy) || 0.0001;
    const angleDeg = (Math.atan2(dy, dx) * 180/Math.PI + 360) % 360;

    const wallR = RING_R - BALL_R - 2;
    if (dist > wallR){
      // If you're in the hole region, let it escape
      if (inHole(angleDeg, holeCenterDeg)){
        // fall out -> respawn somewhere inside (forever behavior)
        spawnBall(i);
        continue;
      }
      // otherwise bounce off the ring
      const nx = dx / dist, ny = dy / dist;
      const targetX = CX + nx*wallR;
      const targetY = CY + ny*wallR;
      b.x = targetX; b.y = targetY;

      // reflect velocity along normal
      const vn = b.vx*nx + b.vy*ny;
      if (vn > 0){
        b.vx -= 2*vn*nx;
        b.vy -= 2*vn*ny;
      }
      // add slight tangential friction
      b.vx *= 0.995;
      b.vy *= 0.995;
    }
  }
}

function drawRing(){
  // draw ring as circle outline, then erase hole arc in white
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;
  const thick = 5;

  // outline (sample points)
  for (let deg=0; deg<360; deg+=1){
    if (inHole(deg, holeCenterDeg)) continue;
    const a = deg*Math.PI/180;
    const x = (CX + Math.cos(a)*RING_R)|0;
    const y = (CY + Math.sin(a)*RING_R)|0;
    // thickness
    for (let k=-thick;k<=thick;k++){
      setPix(x, y+k, 0,0,0);
      setPix(x+k, y, 0,0,0);
    }
  }
}

function renderFrame(){
  clearWhite();
  drawRing();
  for (let i=0;i<N;i++){
    const b = balls[i];
    fillCircle(b.x|0, b.y|0, BALL_R, b.col);
    // code on top
    drawText2(b.code, (b.x|0), (b.y|0));
  }
}

function writePPM(){
  // P6 binary ppm
  process.stdout.write(`P6\n${W} ${H}\n255\n`);
  process.stdout.write(buf);
}

// main loop forever
while (true){
  stepPhysics();
  renderFrame();
  writePPM();
}
JS

# Pipe frames from node -> ffmpeg -> Twitch
# - image2pipe ppm input
# - add silent audio so Twitch is happy
node /tmp/sim.js | ffmpeg -hide_banner -loglevel warning \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -shortest \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -g 60 -b:v 2500k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmps://live.twitch.tv/app/${STREAM_KEY}"
