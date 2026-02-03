#!/usr/bin/env bash

# =========================
# 🔑 CONFIG
# =========================
export YT_STREAM_KEY="u0d7-eetf-a97p-uer8-18ju"
YOUTUBE_URL="rtmp://a.rtmp.youtube.com/live2/${YT_STREAM_KEY}"
FLAGS_DIR="/tmp/flags"
mkdir -p "$FLAGS_DIR"

# 🛑 CLEANUP: Kill any ghost processes from previous failed runs
pkill -9 node || true
pkill -9 ffmpeg || true

# --- 1. ASSET CHECK (The "No-Ghost" Rule) ---
download_flag () {
  local iso=$(echo "$1" | tr 'A-Z' 'a-z')
  if [ ! -s "$FLAGS_DIR/${iso}_40.rgb" ]; then
    local png="$FLAGS_DIR/${iso}.png"
    curl --retry 3 -m 10 -fsSL "https://flagcdn.com/w160/${iso}.png" -o "$png" && \
    ffmpeg -loglevel error -y -i "$png" -vf "scale=40:40" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_40.rgb" && \
    ffmpeg -loglevel error -y -i "$png" -vf "scale=240:240" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_240.rgb"
    rm -f "$png"
  fi
}
export -f download_flag

echo "--- RULE: CHECKING ASSETS ---"
grep -oP '"iso2":\s*"\K[^"]+' countries.json | xargs -P 8 -I {} bash -c 'download_flag "{}"'

# --- 2. THE ENGINE (Graphics) ---
cat > /tmp/yt_sim.js <<'JS'
const fs=require('fs');const W=1080,H=1920,FPS=60,DT=1/60;
const R=16, RING_R=125, CX=W/2, CY=880, UI_TOP=280; 
const FLAGS_DIR="/tmp/flags";
const rgb=Buffer.alloc(W*H*3);

// Font/Graphics code (Condensed for stability)
const FONT={'A':[14,17,17,31,17,17,17],'B':[30,17,30,17,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],'E':[31,16,30,16,16,16,31],'F':[31,16,30,16,16,16,16],'G':[14,17,16,23,17,17,14],'H':[17,17,17,31,17,17,17],'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],'M':[17,27,21,17,17,17,17],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'X':[17,17,10,4,10,17,17],'Y':[17,17,10,4,4,4,4],'Z':[31,1,2,4,8,16,31],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],'!':[4,4,4,4,0,0,4],':':[0,0,4,0,4,0,0],'.':[0,0,0,0,0,0,4],'=':[0,0,31,0,31,0,0]};
function drawT(t,x,y,s,c){let cx=x;for(let char of (t||"").toString().toUpperCase()){const rows=FONT[char]||FONT[' '];for(let r=0;r<7;r++)for(let col=0;col<5;col++)if(rows[r]&(1<<(4-col)))for(let sy=0;sy<s;sy++)for(let sx=0;sx<s;sx++){let px=cx+col*s+sx,py=y+r*s+sy;if(px>=0&&px<W&&py>=0&&py<H){const i=(py*W+px)*3;rgb[i]=c[0];rgb[i+1]=c[1];rgb[i+2]=c[2];}}cx+=6*s;}}
const flagCache={};function blit(cx,cy,iso,sz,clipRad){const k=`${iso}_${sz}`;if(!flagCache[k]){try{flagCache[k]=fs.readFileSync(`${FLAGS_DIR}/${iso}_${sz}.rgb`)}catch(e){return}}const b=flagCache[k],x0=Math.floor(cx-sz/2),y0=Math.floor(cy-sz/2);for(let y=0;y<sz;y++)for(let x=0;x<sz;x++){if((x-sz/2)**2+(y-sz/2)**2 > clipRad**2) continue;const si=(y*sz+x)*3,di=((y0+y)*W+(x0+x))*3;if(di>=0&&di<rgb.length-3){rgb[di]=b[si];rgb[di+1]=b[si+1];rgb[di+2]=b[si+2];}}}

let ents=[],deadStack=[],winStats={},state="PLAY",timer=0,lastWin="NONE",winner=null;
const countries=JSON.parse(fs.readFileSync('countries.json','utf8'));
function init(){ents=countries.sort(()=>0.5-Math.random()).map(c=>({n:c.name,i:c.iso2.toLowerCase(),x:CX,y:CY,vx:(Math.random()-0.5)*1000,vy:(Math.random()-0.5)*1000,f:false}));deadStack=[];state="PLAY";}

function loop(){
  rgb.fill(0); // Clear screen
  for(let i=0;i<rgb.length;i+=3){rgb[i]=165;rgb[i+1]=110;rgb[i+2]=85;}
  const hDeg=(Date.now()/1000*90)%360;
  // UI Boxes
  const statsY = 580;
  for(let y=statsY;y<statsY+140;y++)for(let x=100;x<W-100;x++){const i=(y*W+x)*3;rgb[i]=25;rgb[i+1]=25;rgb[i+2]=30;}
  drawT("ALIVE",580,statsY+20,2,[150,150,150]);
  drawT(ents.filter(e=>!e.f).length.toString(),580,statsY+70,3,[255,255,255]);
  drawT("!67=BAN",820,statsY+45,4,[255,50,50]);

  if(state==="PLAY"){
    // Arena & Balls logic
    ents.forEach(e=>{
       if(e.f){ 
         const ti=deadStack.indexOf(e);
         const tx=70+(ti%18)*54, ty=1300+Math.floor(ti/18)*45;
         e.x+=(tx-e.x)*0.2; e.y+=(ty-e.y)*0.2; blit(e.x,e.y,e.i,24,12);
       } else {
         e.x+=e.vx*DT; e.y+=e.vy*DT;
         let dx=e.x-CX, dy=e.y-CY, dist=Math.sqrt(dx*dx+dy*dy);
         if(dist>RING_R-R){
            const ang=(Math.atan2(dy,dx)*180/Math.PI+360)%360;
            if(Math.abs(((ang-hDeg+180)%360)-180)<22){ e.f=true; deadStack.push(e); }
            else { e.vx*=-1.02; e.vy*=-1.02; e.x=CX+((e.x-CX)/dist)*(RING_R-R); e.y=CY+((e.y-CY)/dist)*(RING_R-R); }
         }
         blit(e.x,e.y,e.i,40,R);
       }
    });
    if(ents.filter(e=>!e.f).length===1){state="WIN"; winner=ents.find(e=>!e.f); lastWin=winner.n; timer=0;}
  } else {
    drawT("WINNER!",CX-140,740,5,[255,255,255]);
    if(winner) blit(CX, 930, winner.i, 240, 110);
    if(++timer>300) init();
  }
  process.stdout.write(rgb);
}
init(); setInterval(loop, 1000/FPS);
JS

# --- 3. THE HANDSHAKE & STREAM ---
while true; do
  echo "--- RULE: CHECKING STREAM READINESS ---"
  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/a.rtmp.youtube.com/1935" 2>/dev/null; then
    echo "✅ CONNECTION OK. STARTING STREAM..."
    node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel error -y \
      -f rawvideo -pixel_format rgb24 -video_size 1080x1920 -framerate 60 -i - \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
      -g 120 -b:v 8000k -minrate 8000k -maxrate 8000k -bufsize 16000k \
      -f flv "$YOUTUBE_URL" || echo "FFmpeg pipe broken. Restarting..."
  else
    echo "❌ YOUTUBE UNREACHABLE. Re-checking in 5s..."
  fi
  sleep 5
done
