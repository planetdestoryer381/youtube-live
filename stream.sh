#!/usr/bin/env bash
set -euo pipefail

: "${STREAM_KEY:?STREAM_KEY missing}"

# ===== SETTINGS =====
FPS=20
W=854
H=480
BALLS=200
BALL_R=10

export FPS W H BALLS BALL_R

echo "=== BALL VISIBILITY TEST ==="
echo "FPS=$FPS SIZE=${W}x${H} BALLS=$BALLS BALL_R=$BALL_R"
node -v
ffmpeg -version | head -n 2
echo "============================"

cat > /tmp/sim.js <<'JS'
const FPS=+process.env.FPS,W=+process.env.W,H=+process.env.H;
const N=+process.env.BALLS,R=+process.env.BALL_R;

const CODES = (
  "AF AL DZ AD AO AG AR AM AU AT AZ BS BH BD BB BY BE BZ BJ BT BO BA BW BR BN BG BF BI KH CM CA CV CF TD CL CN CO KM CG CR CI HR CU CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IR IQ IE IL IT JM JP JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU MG MW MY MV ML MT MR MU MX MD MC MN ME MA MZ MM NA NR NP NL NZ NI NE NG MK NO OM PK PW PA PG PY PE PH PL PT QA RO RU RW KN LC VC WS SM ST SA SN RS SC SL SG SK SI SB SO ZA ES LK SD SR SE CH SY TW TJ TZ TH TL TG TO TT TN TR TM UG UA AE GB US UY UZ VU VE VN YE ZM ZW"
).trim().split(/\s+/);

const FONT = {
  'A':[0b01110,0b10001,0b11111,0b10001,0b10001],
  'B':[0b11110,0b10001,0b11110,0b10001,0b11110],
  'C':[0b01111,0b10000,0b10000,0b10000,0b01111],
  'D':[0b11110,0b10001,0b10001,0b10001,0b11110],
  'E':[0b11111,0b10000,0b11110,0b10000,0b11111],
  'F':[0b11111,0b10000,0b11110,0b10000,0b10000],
  'G':[0b01111,0b10000,0b10111,0b10001,0b01111],
  'H':[0b10001,0b10001,0b11111,0b10001,0b10001],
  'I':[0b11111,0b00100,0b00100,0b00100,0b11111],
  'J':[0b00111,0b00010,0b00010,0b10010,0b01100],
  'K':[0b10001,0b10010,0b11100,0b10010,0b10001],
  'L':[0b10000,0b10000,0b10000,0b10000,0b11111],
  'M':[0b10001,0b11011,0b10101,0b10001,0b10001],
  'N':[0b10001,0b11001,0b10101,0b10011,0b10001],
  'O':[0b01110,0b10001,0b10001,0b10001,0b01110],
  'P':[0b11110,0b10001,0b11110,0b10000,0b10000],
  'Q':[0b01110,0b10001,0b10001,0b10011,0b01111],
  'R':[0b11110,0b10001,0b11110,0b10010,0b10001],
  'S':[0b01111,0b10000,0b01110,0b00001,0b11110],
  'T':[0b11111,0b00100,0b00100,0b00100,0b00100],
  'U':[0b10001,0b10001,0b10001,0b10001,0b01110],
  'V':[0b10001,0b10001,0b10001,0b01010,0b00100],
  'W':[0b10001,0b10101,0b10101,0b11011,0b10001],
  'X':[0b10001,0b01010,0b00100,0b01010,0b10001],
  'Y':[0b10001,0b01010,0b00100,0b00100,0b00100],
  'Z':[0b11111,0b00010,0b00100,0b01000,0b11111],
};

const buf = Buffer.alloc(W*H*3);

function setPix(x,y){
  if(x<0||y<0||x>=W||y>=H) return;
  const i=(y*W+x)*3;
  buf[i]=0;buf[i+1]=0;buf[i+2]=0;
}

function clear(){
  buf.fill(255);
}

function drawBall(cx,cy){
  for(let y=-R;y<=R;y++)
    for(let x=-R;x<=R;x++)
      if(x*x+y*y<=R*R) setPix(cx+x,cy+y);
}

let positions=[];
for(let i=0;i<N;i++){
  positions.push({
    x: Math.random()*(W-2*R)+R,
    y: Math.random()*(H-2*R)+R,
    code: CODES[i%CODES.length]
  });
}

setInterval(()=>{
  clear();
  for(const b of positions){
    drawBall(b.x|0,b.y|0);
  }
  process.stdout.write(`P6\n${W} ${H}\n255\n`);
  process.stdout.write(buf);
},1000/FPS);
JS

node /tmp/sim.js | ffmpeg -loglevel info -stats \
  -f image2pipe -vcodec ppm -r "$FPS" -i - \
  -f lavfi -i anullsrc \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -pix_fmt yuv420p -g 60 \
  -c:a aac -b:a 128k \
  -f flv "rtmps://live.twitch.tv/app/${STREAM_KEY}"
