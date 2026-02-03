#!/usr/bin/env bash
set -e

# =========================
# 🔑 CONFIG
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"
YOUTUBE_URL="rtmp://a.rtmp.youtube.com/live2/${YT_STREAM_KEY}"

export FPS=30
export W=1080
export H=1920
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

# --- Asset Loader ---
download_flag () {
  local iso=$(echo "$1" | tr 'A-Z' 'a-z')
  local out_rgb="$FLAGS_DIR/${iso}_70.rgb"
  [ -s "$out_rgb" ] && return 0
  local png="$FLAGS_DIR/${iso}.png"
  curl -fsSL "https://flagcdn.com/w160/${iso}.png" -o "$png" || return 0
  ffmpeg -loglevel error -y -i "$png" -vf "scale=70:70" -f rawvideo -pix_fmt rgb24 "$out_rgb" >/dev/null 2>&1 || true
  ffmpeg -loglevel error -y -i "$png" -vf "scale=40:40" -f rawvideo -pix_fmt rgb24 "${FLAGS_DIR}/${iso}_40.rgb" >/dev/null 2>&1 || true
  ffmpeg -loglevel error -y -i "$png" -vf "scale=240:240" -f rawvideo -pix_fmt rgb24 "${FLAGS_DIR}/${iso}_240.rgb" >/dev/null 2>&1 || true
}

echo "--- Loading Assets ---"
ISO_LIST=$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' "./countries.json" | cut -d'"' -f4 | tr 'A-Z' 'a-z' | sort -u)
for iso in $ISO_LIST; do download_flag "$iso"; done

# --- Node.js Engine (Physics & Fall Animation) ---
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');
const W=1080, H=1920, FPS=30, R=35, RING_R=420, DT=1/30, GRAVITY=800;
const CX=W/2, CY=H/2, FLAGS_DIR="/tmp/flags";
const rgb = Buffer.alloc(W * H * 3);

function setP(x,y,r,g,b){ 
  if(x<0||y<0||x>=W||y>=H) return; 
  const i=(Math.floor(y)*W+Math.floor(x))*3; 
  rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b; 
}

function drawRect(x1,y1,w,h,c){
  for(let y=y1;y<y1+h;y++) for(let x=x1;x<x1+w;x++) setP(x,y,...c);
}

const FONT={'A':[14,17,17,31,17,17,17],'B':[30,17,30,17,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],'E':[31,16,30,16,16,16,31],'F':[31,16,30,16,16,16,16],'G':[14,17,16,23,17,17,14],'H':[17,17,17,31,17,17,17],'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],'M':[17,27,21,17,17,17,17],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'X':[17,17,10,4,10,17,17],'Y':[17,17,10,4,4,4,4],'Z':[31,1,2,4,8,16,31],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],'!':[4,4,4,4,0,0,4],'=':[0,0,31,0,31,0,0]};
function drawT(t,x,y,s,c){
  let cx=x; for(let char of (t||"").toString().toUpperCase()){
    const rows=FONT[char]||FONT[' '];
    for(let r=0;r<7;r++) for(let col=0;col<5;col++) if(rows[r]&(1<<(4-col))) for(let sy=0;sy<s;sy++) for(let sx=0;sx<s;sx++) setP(cx+col*s+sx,y+r*s+sy,...c);
    cx+=6*s;
  }
}

function blit(cx,cy,rad,iso,sz){
  try {
    const b=fs.readFileSync(`${FLAGS_DIR}/${iso}_${sz}.rgb`);
    const x0=Math.floor(cx-sz/2), y0=Math.floor(cy-sz/2);
    for(let y=0;y<sz;y++) for(let x=0;x<sz;x++){
      if((x-sz/2)**2+(y-sz/2)**2 > rad**2) continue;
      const si=(y*sz+x)*3; setP(x0+x,y0+y,b[si],b[si+1],b[si+2]);
    }
  }catch(e){}
}

let ents=[], state="PLAY", timer=0, lastWin="NONE", lastIso="un"; 
const countries=JSON.parse(fs.readFileSync("./countries.json","utf8"));

function init(){
  ents=countries.sort(()=>0.5-Math.random()).slice(0,35).map(c=>({
    n:c.name, i:c.iso2.toLowerCase(), cap:c.capital||"---",
    x:CX+(Math.random()-0.5)*200, y:CY+(Math.random()-0.5)*200,
    vx:(Math.random()-0.5)*700, vy:(Math.random()-0.5)*700, a:true, falling:false
  }));
  state="PLAY";
}

function drawUI() {
  // 1:1 Top Bar
  drawRect(40, 60, 1000, 140, [25, 25, 30]);
  
  // Last Winner Slot
  drawRect(60, 75, 300, 110, [45, 45, 55]);
  if(lastIso!=="un") blit(90, 130, 20, lastIso, 40);
  drawT("Last winner", 120, 90, 1, [180, 180, 180]);
  drawT(lastWin.substring(0,12), 120, 115, 2, [255, 255, 255]);

  // Mode Slot
  drawRect(390, 75, 300, 110, [45, 45, 55]);
  drawT("Mode", 480, 90, 1, [180, 180, 180]);
  drawT("Last one wins", 410, 115, 2, [255, 255, 255]);

  // BAN Slot (Integrated into Top Bar)
  drawRect(720, 75, 300, 110, [45, 45, 55]);
  drawT("!67 = BAN", 760, 105, 4, [255, 50, 50]);

  // Bottom Staging
  drawRect(0, 1450, 1080, 470, [15, 15, 20]);
  countries.slice(0, 120).forEach((c, idx) => {
    let r = Math.floor(idx/15), col = idx%15;
    blit(55 + col*70, 1500 + r*65, 18, c.iso2, 40);
  });
}

function loop(){
  drawRect(0, 0, W, H, [158, 100, 75]); 
  const hDeg=(Date.now()/1000*1.1*60)%360;
  drawUI();
  
  if(state==="PLAY"){
    // Ring
    for(let a=0;a<360;a+=0.2){
      let diff=Math.abs(((a-hDeg+180)%360)-180);
      if(diff<25)continue;
      const r=a*Math.PI/180;
      for(let t=-4;t<4;t++) setP(CX+(RING_R+t)*Math.cos(r),CY+(RING_R+t)*Math.sin(r),255,255,255);
    }

    ents.forEach((e, i) => {
      if(e.falling){
        e.vy += GRAVITY * DT; e.x += e.vx*DT; e.y += e.vy*DT;
        blit(e.x, e.y, R, e.i, 70);
        if(e.y > 1450) e.a = false; // Stop rendering once in staging area
        return;
      }
      if(!e.a) return;

      // Collision
      for(let j=i+1; j<ents.length; j++){
        let b=ents[j]; if(!b.a || b.falling) continue;
        let dx=b.x-e.x, dy=b.y-e.y, d=Math.sqrt(dx*dx+dy*dy);
        if(d < R*2 && d > 0){
          let nx=dx/d, ny=dy/d, overlap = (R*2 - d) + 2; 
          e.x -= nx*(overlap/2); e.y -= ny*(overlap/2);
          b.x += nx*(overlap/2); b.y += ny*(overlap/2);
          let p = (e.vx*nx+e.vy*ny-(b.vx*nx+b.vy*ny));
          e.vx -= p*nx; e.vy -= p*ny; b.vx += p*nx; b.vy += p*ny;
        }
      }

      e.x+=e.vx*DT; e.y+=e.vy*DT;
      let dx=e.x-CX, dy=e.y-CY, dist=Math.sqrt(dx*dx+dy*dy);
      if(dist > RING_R-R){
        const ang=(Math.atan2(dy,dx)*180/Math.PI+360)%360;
        if(Math.abs(((ang-hDeg+180)%360)-180) < 25){
          e.falling = true; e.vx *= 0.2; e.vy = 100; // Trigger Fall Animation
        } else {
          let nx=dx/dist, ny=dy/dist, dot=e.vx*nx+e.vy*ny;
          e.vx=(e.vx-2*dot*nx)*1.05; e.vy=(e.vy-2*dot*ny)*1.05;
          e.x=CX+nx*(RING_R-R); e.y=CY+ny*(RING_R-R);
        }
      }
      blit(e.x,e.y,R,e.i,70);
    });

    let alive=ents.filter(e=>e.a && !e.falling);
    if(alive.length === 1){ 
      state="WIN"; winner=alive[0]; lastWin=winner.n; lastIso=winner.i; timer=0; 
    }
  } else {
    // Round Summary Overlay
    drawRect(80, 350, 920, 1000, [30, 45, 95]);
    drawRect(120, 380, 840, 100, [20, 25, 50]);
    drawT("ROUND SUMMARY", 320, 405, 5, [255, 255, 255]);
    drawRect(120, 840, 840, 480, [20, 25, 45]);
    blit(300, 1080, 120, winner.i, 240);
    drawT("Winner", 580, 870, 2, [180, 180, 220]);
    drawT(winner.n, 580, 920, 3, [255, 255, 255]);
    drawT(`Capital: ${winner.cap}`, 580, 1000, 2, [200, 200, 200]);
    if(++timer > 180) init();
  }
  process.stdout.write(rgb);
}
init();
setInterval(loop, 1000/FPS);
JS

# --- FFmpeg Execution ---
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel error -y \
    -f rawvideo -pixel_format rgb24 -video_size 1080x1920 -framerate "$FPS" -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -g 60 -b:v 3500k -f flv "$YOUTUBE_URL"
  sleep 2
done
