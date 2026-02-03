#!/usr/bin/env bash
set -e

# =========================
# 🔑 CONFIG
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"
YOUTUBE_URL="rtmp://a.rtmp.youtube.com/live2/${YT_STREAM_KEY}"

export FPS=60
export W=1080
export H=1920
export FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

# --- Pre-Flight Stream Fixer ---
check_stream_readiness() {
  echo "--- Running Stream Health Check ---"
  # Check for flags
  local fcount=$(ls -1 $FLAGS_DIR/*_90.rgb 2>/dev/null | wc -l)
  if [ "$fcount" -lt 180 ]; then
    echo "Check Failed: Only $fcount/193 flags found. Downloading missing..."
    return 1
  fi
  # Check for countries.json
  if [ ! -f "countries.json" ]; then
    echo "Check Failed: countries.json missing!"
    exit 1
  fi
  echo "Stream Status: READY"
  return 0
}

download_flag () {
  local iso=$(echo "$1" | tr 'A-Z' 'a-z')
  [ -s "$FLAGS_DIR/${iso}_90.rgb" ] && return 0
  local png="$FLAGS_DIR/${iso}.png"
  if curl --retry 5 -m 15 -fsSL "https://flagcdn.com/w160/${iso}.png" -o "$png"; then
    ffmpeg -loglevel error -y -i "$png" -vf "scale=90:90" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_90.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=30:30" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_30.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=240:240" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_240.rgb" || true
    rm -f "$png"
  fi
}
export -f download_flag

# Ensure flags are synced
grep -oP '"iso2":\s*"\K[^"]+' countries.json | xargs -P 8 -I {} bash -c 'download_flag "{}"'

until check_stream_readiness; do
  grep -oP '"iso2":\s*"\K[^"]+' countries.json | xargs -P 8 -I {} bash -c 'download_flag "{}"'
  sleep 2
done

# --- Graphics Engine ---
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');
const W=1080, H=1920, FPS=60, DT=1/60;
const R=36, RING_R=250; // Circle is 1.5x smaller (was 380)
const CX=W/2, CY=750;   
const FLAGS_DIR="/tmp/flags";
const rgb = Buffer.alloc(W * H * 3);

const FONT={'A':[14,17,17,31,17,17,17],'B':[30,17,30,17,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],'E':[31,16,30,16,16,16,31],'F':[31,16,30,16,16,16,16],'G':[14,17,16,23,17,17,14],'H':[17,17,17,31,17,17,17],'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],'M':[17,27,21,17,17,17,17],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'X':[17,17,10,4,10,17,17],'Y':[17,17,10,4,4,4,4],'Z':[31,1,2,4,8,16,31],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],'!':[4,4,4,4,0,0,4],':':[0,0,4,0,4,0,0],'.':[0,0,0,0,0,0,4],'=':[0,0,31,0,31,0,0]};
function drawT(t,x,y,s,c){
  let cx=x; for(let char of (t||"").toString().toUpperCase()){
    const rows=FONT[char]||FONT[' '];
    for(let r=0;r<7;r++) for(let col=0;col<5;col++) if(rows[r]&(1<<(4-col))) for(let sy=0;sy<s;sy++) for(let sx=0;sx<s;sx++){
      let px=cx+col*s+sx, py=y+r*s+sy;
      if(px>=0&&px<W&&py>=0&&py<H){ const i=(py*W+px)*3; rgb[i]=c[0]; rgb[i+1]=c[1]; rgb[i+2]=c[2]; }
    }
    cx+=6*s;
  }
}

const flagCache = {};
function blit(cx,cy,rad,iso,sz,full){
  const k=`${iso}_${sz}`; if(!flagCache[k]) try{flagCache[k]=fs.readFileSync(`${FLAGS_DIR}/${iso}_${sz}.rgb`)}catch(e){return};
  const b=flagCache[k], x0=Math.floor(cx-sz/2), y0=Math.floor(cy-sz/2);
  for(let y=0;y<sz;y++) for(let x=0;x<sz;x++){
    if(full){ if((x-sz/2)**2+(y-sz/2)**2 > (sz/2)**2) continue; }
    else { if((x-sz/2)**2+(y-sz/2)**2 > rad**2) continue; }
    const si=(y*sz+x)*3, di=((y0+y)*W+(x0+x))*3;
    if(di>=0 && di<rgb.length-3){ rgb[di]=b[si]; rgb[di+1]=b[si+1]; rgb[di+2]=b[si+2]; }
  }
}

let ents=[], deadStack=[], winStats={}, state="PLAY", timer=0, lastWin="NONE";
const countries = JSON.parse(fs.readFileSync('countries.json', 'utf8'));

function init(){
  ents=countries.sort(()=>0.5-Math.random()).map(c=>({
    n:c.name, i:c.iso2.toLowerCase(), x:CX, y:CY, vx:(Math.random()-0.5)*1200, vy:(Math.random()-0.5)*1200, f:false
  }));
  deadStack=[]; state="PLAY";
}

function drawUI(){
  // Top Connected Bar
  for(let y=40;y<160;y++) for(let x=40;x<W-40;x++){
    const idx=(y*W+x)*3; rgb[idx]=20; rgb[idx+1]=20; rgb[idx+2]=25;
  }
  drawT("LAST WINNER", 80, 65, 1, [150,150,150]);
  drawT(lastWin.substring(0,14), 80, 95, 2, [255,255,255]);
  drawT("ALIVE", 480, 65, 1, [150,150,150]);
  drawT(ents.filter(e=>!e.f).length.toString(), 480, 95, 2, [255,255,255]);
  drawT("!67 = BAN", 780, 85, 4, [255, 50, 50]);

  // Bigger Leaderboard Font
  for(let y=170;y<440;y++) for(let x=40;x<W-40;x++){
    const idx=(y*W+x)*3; rgb[idx]=15; rgb[idx+1]=15; rgb[idx+2]=20;
  }
  drawT("LEADERBOARD", 60, 190, 3, [255,255,100]); // Font scale 3
  const leaders = Object.entries(winStats).sort((a,b)=>b[1]-a[1]).slice(0,5);
  leaders.forEach(([name, wins], i) => {
    drawT(`${i+1}. ${name.substring(0,16)}`, 60, 245 + i*35, 2, [220,220,220]); // Font scale 2
    drawT(wins.toString(), 950, 245 + i*35, 2, [255,255,255]);
  });

  // Small Lose Area Grid (Fits 193 easily)
  for(let y=1100;y<1920;y++) for(let x=0;x<W;x++){
    const idx=(y*W+x)*3; rgb[idx]=10; rgb[idx+1]=10; rgb[idx+2]=15;
  }
  deadStack.forEach((e, idx) => {
    const col=idx%15, row=Math.floor(idx/15); // 15 columns instead of 11
    blit(60+col*68, 1150+row*40, 14, e.i, 30, false); 
  });
}

function loop(){
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=165; rgb[i+1]=110; rgb[i+2]=85; }
  const hDeg=(Date.now()/1000*1.5*60)%360;
  drawUI();
  
  if(state==="PLAY"){
    // Arena
    for(let a=0;a<360;a+=0.4){
      let diff=Math.abs(((a-hDeg+180)%360)-180);
      if(diff<22) continue; 
      const r=a*Math.PI/180;
      for(let t=-10;t<10;t++){
        const px=Math.floor(CX+(RING_R+t)*Math.cos(r)), py=Math.floor(CY+(RING_R+t)*Math.sin(r));
        if(px>=0&&px<W&&py>=0&&py<H){ const idx=(py*W+px)*3; rgb[idx]=255; rgb[idx+1]=255; rgb[idx+2]=255; }
      }
    }

    ents.forEach((e, i) => {
      if(e.f){ 
        const targetIdx = deadStack.indexOf(e);
        const tx = 60 + (targetIdx%15)*68, ty = 1150 + Math.floor(targetIdx/15)*40;
        e.x += (tx - e.x) * 0.15; e.y += (ty - e.y) * 0.15;
        blit(e.x, e.y, 14, e.i, 30, false);
        return;
      }
      for(let j=i+1;j<ents.length;j++){
        let b=ents[j]; if(b.f) continue;
        let dx=b.x-e.x, dy=b.y-e.y, d=Math.sqrt(dx*dx+dy*dy);
        if(d < R*2 && d>0){
          let nx=dx/d, ny=dy/d, overlap=(R*2-d)+1;
          e.x-=nx*(overlap/2); e.y-=ny*(overlap/2); b.x+=nx*(overlap/2); b.y+=ny*(overlap/2);
          let p=(e.vx*nx+e.vy*ny-(b.vx*nx+b.vy*ny));
          e.vx-=p*nx; e.vy-=p*ny; b.vx+=p*nx; b.vy+=p*ny;
        }
      }
      e.x+=e.vx*DT; e.y+=e.vy*DT;
      let dx=e.x-CX, dy=e.y-CY, dist=Math.sqrt(dx*dx+dy*dy);
      if(dist > RING_R-R){
        const ang=(Math.atan2(dy,dx)*180/Math.PI+360)%360;
        if(Math.abs(((ang-hDeg+180)%360)-180) < 22){
          e.f=true; deadStack.push(e);
        } else {
          let nx=dx/dist, ny=dy/dist, dot=e.vx*nx+e.vy*ny;
          e.vx=(e.vx-2*dot*nx)*1.02; e.vy=(e.vy-2*dot*ny)*1.02;
          e.x=CX+nx*(RING_R-R); e.y=CY+ny*(RING_R-R);
        }
      }
      blit(e.x, e.y, R, e.i, 90, true); 
    });

    let alive=ents.filter(e=>!e.f);
    if(alive.length===1){ 
      state="WIN"; winner=alive[0]; lastWin=winner.n; timer=0;
      winStats[winner.n] = (winStats[winner.n]||0) + 1;
    }
  } else {
    for(let y=450;y<950;y++) for(let x=150;x<930;x++){
      const idx=(y*W+x)*3; rgb[idx]=30; rgb[idx+1]=40; rgb[idx+2]=100;
    }
    drawT("WINNER!", 430, 500, 6, [255,255,255]);
    blit(W/2, 730, 100, winner.i, 240, true);
    drawT(winner.n, 350, 870, 3, [255,255,255]);
    if(++timer > 300) init();
  }
  process.stdout.write(rgb);
}
init();
setInterval(loop, 1000/FPS);
JS

# --- Final Stream Loop ---
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel error -y \
    -f rawvideo -pixel_format rgb24 -video_size 1080x1920 -framerate 60 -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
    -x264-params "keyint=120:min-keyint=120:scenecut=0" \
    -b:v 6000k -minrate 6000k -maxrate 6000k -bufsize 12000k \
    -f flv "$YOUTUBE_URL"
  sleep 5
done
