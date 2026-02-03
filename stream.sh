#!/usr/bin/env bash
set -e

# =========================
# 🔑 CONFIG
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"
YOUTUBE_URL="rtmp://a.rtmp.youtube.com/live2/${YT_STREAM_KEY}"

# Use the Env variables provided by your runner, or defaults
export FPS=${FPS:-30}
export W=${W:-1080}
export H=${H:-1920}
export RING_R=${RING_R:-380}

export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

# --- Hardened Flag Downloader ---
download_flag () {
  local iso=$(echo "$1" | tr 'A-Z' 'a-z')
  local size="$2"
  local out_rgb="$FLAGS_DIR/${iso}_${size}.rgb"
  
  if [ ! -s "$out_rgb" ]; then
    local png="$FLAGS_DIR/${iso}.png"
    # Download PNG if not exists
    if [ ! -s "$png" ]; then
      curl -fsSL "https://flagcdn.com/w80/${iso}.png" -o "$png" || return 0
    fi
    # Convert to Raw RGB (Fail Silently to avoid crash)
    ffmpeg -loglevel error -y -i "$png" -vf "scale=${size}:${size}" -f rawvideo -pix_fmt rgb24 "$out_rgb" || rm -f "$out_rgb"
  fi
}

echo "--- Loading Assets ---"
if [ ! -f "countries.json" ]; then
    echo "Error: countries.json missing!"
    exit 1
fi

# Robust ISO extraction: works even if JSON is formatted weirdly
ISO_LIST=$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' countries.json | cut -d'"' -f4 | sort -u)

for iso in $ISO_LIST; do
  download_flag "$iso" "50"
  download_flag "$iso" "150"
done
echo "--- Assets Loaded ---"

# --- Node.js Engine (Condensed & Shielded) ---
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');
const W=parseInt(process.env.W), H=parseInt(process.env.H), FPS=parseInt(process.env.FPS);
const R=25, RING_R=parseInt(process.env.RING_R), DT=1/FPS, CX=W/2, CY=H/2;
const rgb = Buffer.alloc(W * H * 3);

function setP(x,y,r,g,b){ if(x<0||y<0||x>=W||y>=H)return; const i=(Math.floor(y)*W+Math.floor(x))*3; rgb[i]=r; rgb[i+1]=g; rgb[i+2]=b; }
function blit(cx,cy,rad,iso,sz){
  try {
    const b=fs.readFileSync(`/tmp/flags/${iso.toLowerCase()}_${sz}.rgb`);
    const x0=Math.floor(cx-sz/2), y0=Math.floor(cy-sz/2);
    for(let y=0;y<sz;y++) for(let x=0;x<sz;x++){
      if((x-sz/2)**2+(y-sz/2)**2 > rad**2) continue;
      const si=(y*sz+x)*3; setP(x0+x,y0+y,b[si],b[si+1],b[si+2]);
    }
  }catch(e){}
}

let ents=[], state="PLAY";
const countries=JSON.parse(fs.readFileSync("./countries.json","utf8"));

function init(){
  ents=countries.map(c=>({
    n:c.name, i:c.iso2, x:CX+(Math.random()-0.5)*200, y:CY+(Math.random()-0.5)*200,
    vx:(Math.random()-0.5)*500, vy:(Math.random()-0.5)*500, a:true
  }));
}

function loop(){
  rgb.fill(15);
  const hDeg=(Date.now()/1000*60)%360;
  let alive = ents.filter(e=>e.a);

  // Draw Opening in Ring
  for(let a=0;a<360;a+=0.5){
    let diff=Math.abs(((a-hDeg+180)%360)-180);
    if(diff<35)continue;
    const r=a*Math.PI/180;
    for(let t=0;t<5;t++) setP(CX+(RING_R+t)*Math.cos(r),CY+(RING_R+t)*Math.sin(r),255,255,255);
  }

  ents.forEach((e,idx)=>{
    if(!e.a) return;
    // Basic Anti-Stick Physics
    for(let j=idx+1;j<ents.length;j++){
      let b=ents[j]; if(!b.a) continue;
      let dx=b.x-e.x, dy=b.y-e.y, d=Math.sqrt(dx*dx+dy*dy);
      if(d<R*2 && d>0){
        let nx=dx/d, ny=dy/d, overlap=(R*2-d)+1;
        e.x-=nx*(overlap/2); e.y-=ny*(overlap/2);
        b.x+=nx*(overlap/2); b.y+=ny*(overlap/2);
        let p=(e.vx*nx+e.vy*ny-(b.vx*nx+b.vy*ny));
        e.vx-=p*nx; e.vy-=p*ny; b.vx+=p*nx; b.vy+=p*ny;
      }
    }
    e.x+=e.vx*DT; e.y+=e.vy*DT;
    let dx=e.x-CX, dy=e.y-CY, dist=Math.sqrt(dx*dx+dy*dy);
    if(dist > RING_R-R){
      const ang=(Math.atan2(dy,dx)*180/Math.PI+360)%360;
      if(Math.abs(((ang-hDeg+180)%360)-180)<35) e.a=false;
      else {
        let nx=dx/dist, ny=dy/dist, dot=e.vx*nx+e.vy*ny;
        e.vx=(e.vx-2*dot*nx)*1.02; e.vy=(e.vy-2*dot*ny)*1.02;
        e.x=CX+nx*(RING_R-R); e.y=CY+ny*(RING_R-R);
      }
    }
    blit(e.x,e.y,R,e.i,50);
  });

  if(alive.length <= 1) init();
  process.stdout.write(rgb);
}
init();
setInterval(loop, 1000/FPS);
JS

# --- Stream Loop ---
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel error -y \
    -f rawvideo -pixel_format rgb24 -video_size ${W}x${H} -framerate $FPS -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -g 40 -b:v 2500k -maxrate 2500k -bufsize 5000k \
    -c:a aac -b:a 128k -f flv "$YOUTUBE_URL"
  sleep 2
done
