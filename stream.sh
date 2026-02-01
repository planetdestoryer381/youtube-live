#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# ======= TUNING (edit these if you want) =======
export FPS="${FPS:-20}"
export W="${W:-854}"
export H="${H:-480}"

export BALLS="${BALLS:-200}"
export BALL_R="${BALL_R:-10}"        # ball size
export RING_R="${RING_R:-170}"       # ring radius (bigger = more room)
export HOLE_DEG="${HOLE_DEG:-70}"    # hole size in degrees (bigger = more fallouts)
export SPIN="${SPIN:-1.0}"           # rad/sec (faster = hole rotates faster)
export SPEED="${SPEED:-90}"          # initial speed

echo "=== GAME SETTINGS ==="
echo "FPS=$FPS SIZE=${W}x${H} BALLS=$BALLS BALL_R=$BALL_R RING_R=$RING_R HOLE_DEG=$HOLE_DEG SPIN=$SPIN SPEED=$SPEED"
echo "STREAM_KEY length: ${#STREAM_KEY}"
node -v
ffmpeg -version | head -n 2
echo "====================="

cat > /tmp/sim.js <<'JS'
'use strict';

/*
  Endless PPM frames to stdout.
  IMPORTANT: no console.log() (stdout). Use console.error() only.
*/

const FPS = +process.env.FPS || 20;
const W   = +process.env.W   || 854;
const H   = +process.env.H   || 480;

const N        = +process.env.BALLS  || 200;
const R        = +process.env.BALL_R || 10;
const RING_R   = +process.env.RING_R || 170;
const HOLE_DEG = +process.env.HOLE_DEG || 70;
const SPIN     = +process.env.SPIN || 1.0;
const SPEED    = +process.env.SPEED || 90;

const CX = W * 0.5;
const CY = H * 0.5;
const dt = 1 / FPS;

// Yellow text (RGB)
const TXT = [255, 215, 0];

// Minimal uppercase font (5x7)
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
  ' ':[0,0,0,0,0,0,0],
  '-':[0,0,0b11111,0,0,0,0],
};

const buf = Buffer.alloc(W * H * 3);

function setPix(x,y,r,g,b){
  if (x<0||y<0||x>=W||y>=H) return;
  const i = (y*W + x) * 3;
  buf[i]=r; buf[i+1]=g; buf[i+2]=b;
}
function clearWhite(){ buf.fill(255); }

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
  // black outline
  for(let deg=0;deg<360;deg+=10){
    const a=deg*Math.PI/180;
    setPix((cx+Math.cos(a)*rad)|0,(cy+Math.sin(a)*rad)|0,0,0,0);
  }
}

function drawChar(ch,x,y,scale,color){
  const rows=FONT[ch] || FONT[' '];
  const [r,g,b]=color;
  for(let rr=0;rr<7;rr++){
    const bits=rows[rr];
    for(let cc=0;cc<5;cc++){
      if(bits & (1<<(4-cc))){
        for(let sy=0;sy<scale;sy++){
          for(let sx=0;sx<scale;sx++){
            setPix(x+cc*scale+sx, y+rr*scale+sy, r,g,b);
          }
        }
      }
    }
  }
}

function drawTextCentered(text, cx, cy, scale, color, maxW){
  text = text.toUpperCase();

  // trim to fit maxW
  const charW = 5*scale;
  const gap = 1*scale;
  const fullW = (text.length * (charW + gap)) - gap;
  if (fullW > maxW){
    const fit = Math.max(1, Math.floor((maxW + gap) / (charW + gap)));
    text = text.slice(0, fit);
  }

  const w = (text.length * (charW + gap)) - gap;
  const h = 7*scale;
  let x = (cx - w/2) | 0;
  let y = (cy - h/2) | 0;
  for(let i=0;i<text.length;i++){
    drawChar(text[i], x, y, scale, color);
    x += charW + gap;
  }
}

function inHole(angleDeg, holeCenterDeg){
  const half = HOLE_DEG/2;
  let d = (angleDeg - holeCenterDeg + 180) % 360 - 180;
  return Math.abs(d) <= half;
}

function rand(a,b){ return a + Math.random()*(b-a); }
function rndi(a,b){ return a + ((Math.random()*(b-a+1))|0); }
function randColor(){ return [rndi(40,235), rndi(40,235), rndi(40,235)]; }

// Country names (ISO-ish). If missing, fallback to code.
const COUNTRY = {
  AF:"AFGHANISTAN", AL:"ALBANIA", DZ:"ALGERIA", AD:"ANDORRA", AO:"ANGOLA",
  AR:"ARGENTINA", AM:"ARMENIA", AU:"AUSTRALIA", AT:"AUSTRIA", AZ:"AZERBAIJAN",
  BH:"BAHRAIN", BD:"BANGLADESH", BY:"BELARUS", BE:"BELGIUM", BZ:"BELIZE",
  BJ:"BENIN", BT:"BHUTAN", BO:"BOLIVIA", BA:"BOSNIA", BW:"BOTSWANA",
  BR:"BRAZIL", BN:"BRUNEI", BG:"BULGARIA", BF:"BURKINA FASO", BI:"BURUNDI",
  KH:"CAMBODIA", CM:"CAMEROON", CA:"CANADA", TD:"CHAD", CL:"CHILE", CN:"CHINA",
  CO:"COLOMBIA", CR:"COSTA RICA", HR:"CROATIA", CU:"CUBA", CY:"CYPRUS", CZ:"CZECHIA",
  DK:"DENMARK", DO:"DOMINICAN REP", EC:"ECUADOR", EG:"EGYPT", SV:"EL SALVADOR",
  EE:"ESTONIA", ET:"ETHIOPIA", FI:"FINLAND", FR:"FRANCE", GE:"GEORGIA", DE:"GERMANY",
  GH:"GHANA", GR:"GREECE", GT:"GUATEMALA", GN:"GUINEA", GY:"GUYANA",
  HT:"HAITI", HN:"HONDURAS", HU:"HUNGARY", IS:"ICELAND", IN:"INDIA", ID:"INDONESIA",
  IR:"IRAN", IQ:"IRAQ", IE:"IRELAND", IL:"ISRAEL", IT:"ITALY", JM:"JAMAICA",
  JP:"JAPAN", JO:"JORDAN", KZ:"KAZAKHSTAN", KE:"KENYA", KR:"KOREA", KW:"KUWAIT",
  KG:"KYRGYZSTAN", LA:"LAOS", LV:"LATVIA", LB:"LEBANON", LR:"LIBERIA", LY:"LIBYA",
  LT:"LITHUANIA", LU:"LUXEMBOURG", MG:"MADAGASCAR", MW:"MALAWI", MY:"MALAYSIA",
  MV:"MALDIVES", ML:"MALI", MT:"MALTA", MR:"MAURITANIA", MU:"MAURITIUS",
  MX:"MEXICO", MD:"MOLDOVA", MC:"MONACO", MN:"MONGOLIA", ME:"MONTENEGRO",
  MA:"MOROCCO", MZ:"MOZAMBIQUE", MM:"MYANMAR", NA:"NAMIBIA", NP:"NEPAL",
  NL:"NETHERLANDS", NZ:"NEW ZEALAND", NI:"NICARAGUA", NE:"NIGER", NG:"NIGERIA",
  MK:"N MACEDONIA", NO:"NORWAY", OM:"OMAN", PK:"PAKISTAN", PA:"PANAMA",
  PG:"PAPUA N GUINEA", PY:"PARAGUAY", PE:"PERU", PH:"PHILIPPINES", PL:"POLAND",
  PT:"PORTUGAL", QA:"QATAR", RO:"ROMANIA", RU:"RUSSIA", RW:"RWANDA",
  SA:"SAUDI ARABIA", SN:"SENEGAL", RS:"SERBIA", SG:"SINGAPORE", SK:"SLOVAKIA",
  SI:"SLOVENIA", SO:"SOMALIA", ZA:"SOUTH AFRICA", ES:"SPAIN", LK:"SRI LANKA",
  SD:"SUDAN", SE:"SWEDEN", CH:"SWITZERLAND", SY:"SYRIA", TW:"TAIWAN",
  TJ:"TAJIKISTAN", TZ:"TANZANIA", TH:"THAILAND", TN:"TUNISIA", TR:"TURKIYE",
  TM:"TURKMENISTAN", UG:"UGANDA", UA:"UKRAINE", AE:"UAE", GB:"UNITED KINGDOM",
  US:"UNITED STATES", UY:"URUGUAY", UZ:"UZBEKISTAN", VE:"VENEZUELA", VN:"VIETNAM",
  YE:"YEMEN", ZM:"ZAMBIA", ZW:"ZIMBABWE"
};

// Codes pool (repeats to reach 200)
const CODES = (
  "AF AL DZ AD AO AR AM AU AT AZ BH BD BY BE BZ BJ BT BO BA BW BR BN BG BF BI KH CM CA TD CL CN CO CR HR CU CY CZ DK DO EC EG SV EE ET FI FR GE DE GH GR GT GN GY HT HN HU IS IN ID IR IQ IE IL IT JM JP JO KZ KE KR KW KG LA LV LB LR LY LT LU MG MW MY MV ML MT MR MU MX MD MC MN ME MA MZ MM NA NP NL NZ NI NE NG MK NO OM PK PA PG PY PE PH PL PT QA RO RU RW SA SN RS SG SK SI SO ZA ES LK SD SE CH SY TW TJ TZ TH TN TR TM UG UA AE GB US UY UZ VE VN YE ZM ZW"
).trim().split(/\s+/);

// Balls
const balls = Array(N);

function spawnBall(i){
  const code = CODES[i % CODES.length];
  const name = COUNTRY[code] || code;
  const col  = randColor();

  const ang = Math.random() * Math.PI * 2;
  const rad = Math.random() * (RING_R * 0.45);
  const x = CX + Math.cos(ang) * rad;
  const y = CY + Math.sin(ang) * rad;

  balls[i] = {
    code, name, col,
    x, y,
    vx: rand(-SPEED, SPEED),
    vy: rand(-SPEED, SPEED),
  };
}
for(let i=0;i<N;i++) spawnBall(i);

// Spatial grid for collisions (fast)
const cellSize = R * 3;
const gridW = Math.ceil(W / cellSize);
const gridH = Math.ceil(H / cellSize);
const grid = new Array(gridW * gridH);

function gridClear(){ grid.fill(null); }
function gridIndex(x,y){
  const gx = Math.max(0, Math.min(gridW-1, (x/cellSize)|0));
  const gy = Math.max(0, Math.min(gridH-1, (y/cellSize)|0));
  return gy*gridW + gx;
}
function gridPush(i,x,y){
  const idx = gridIndex(x,y);
  if(grid[idx] === null) grid[idx] = [i];
  else grid[idx].push(i);
}

let t = 0;
let frames = 0;
let lastReport = Date.now();

function stepPhysics(){
  t += dt;
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;

  // integrate + grid
  gridClear();
  for(let i=0;i<N;i++){
    const b = balls[i];
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    gridPush(i, b.x, b.y);
  }

  // collisions (neighbors)
  const minD = R * 2;
  const minD2 = minD * minD;

  for(let gy=0; gy<gridH; gy++){
    for(let gx=0; gx<gridW; gx++){
      const base = gy*gridW + gx;
      const cell = grid[base];
      if(!cell) continue;

      for(let oy=-1; oy<=1; oy++){
        for(let ox=-1; ox<=1; ox++){
          const nx = gx+ox, ny = gy+oy;
          if(nx<0||ny<0||nx>=gridW||ny>=gridH) continue;

          const other = grid[ny*gridW + nx];
          if(!other) continue;

          for(let ai=0; ai<cell.length; ai++){
            const i = cell[ai];
            const A = balls[i];
            for(let bj=0; bj<other.length; bj++){
              const j = other[bj];
              if(base === (ny*gridW + nx) && j <= i) continue;

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

                // elastic impulse
                const rvx = B.vx - A.vx, rvy = B.vy - A.vy;
                const vn = rvx*nxn + rvy*nyn;
                if(vn < 0){
                  const imp = -vn;
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

  // ring boundary with hole escape
  const wallR = RING_R - R - 2;

  for(let i=0;i<N;i++){
    const b = balls[i];
    const dx = b.x - CX, dy = b.y - CY;
    const dist = Math.sqrt(dx*dx + dy*dy) || 0.0001;
    const angDeg = (Math.atan2(dy, dx)*180/Math.PI + 360) % 360;

    if(dist > wallR){
      if(inHole(angDeg, holeCenterDeg)){
        // escaped via hole: respawn (forever game)
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

    // mild damping
    b.vx *= 0.999;
    b.vy *= 0.999;
  }

  // debug heartbeat
  frames++;
  const now = Date.now();
  if(now - lastReport >= 5000){
    console.error(`[sim] fps=${FPS} frames=${frames} balls=${N} ringR=${RING_R} holeDeg=${HOLE_DEG}`);
    lastReport = now;
  }
}

function drawRing(){
  const holeCenterDeg = (t*SPIN*180/Math.PI) % 360;
  const thick = 4;

  for(let deg=0; deg<360; deg+=1){
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
    const b = balls[i];
    fillCircle(b.x|0, b.y|0, R, b.col);

    // Country name in the middle, small yellow font
    // Scale is tiny; auto-trims to fit inside ball width.
    const maxTextW = (R*2 - 2);
    drawTextCentered(b.name, b.x|0, b.y|0, 1, TXT, maxTextW);
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

# Stream to Twitch
node /tmp/sim.js | ffmpeg -loglevel info -stats \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -g 60 -b:v 2500k \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmps://live.twitch.tv/app/${STREAM_KEY}"
