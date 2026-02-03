#!/usr/bin/env bash
set -e

# Run from script directory so countries.json and generate_flags.js are found
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# --- Generate flag images (download + convert to .rgb) ---
echo "--- Loading flag images ---"
node generate_flags.js

# --- 🛑 MANDATORY CONNECTION CHECK 🛑 ---
verify_stream_path() {
  echo "--- RULE: CHECKING IF STREAM WORKS ---"
  # Try to open a TCP connection to the YouTube RTMP port (1935)
  if ! timeout 3 bash -c "cat < /dev/null > /dev/tcp/a.rtmp.youtube.com/1935" 2>/dev/null; then
    echo "❌ ERROR: Cannot reach YouTube RTMP server. Check firewall/internet."
    return 1
  fi
  echo "✅ SUCCESS: YouTube Ingest is reachable."
  return 0
}

# --- Graphics Engine ---
cat > /tmp/yt_sim.js <<'JS'
const fs=require('fs');const W=1080,H=1920,FPS=60,DT=1/60;
const R=16, RING_R=125, CX=W/2;
const CY=880, UI_TOP=280; 
const FLAGS_DIR=process.env.FLAGS_DIR||"/tmp/flags";
JS
const rgb=Buffer.alloc(W*H*3);

const FONT={'A':[14,17,17,31,17,17,17],'B':[30,17,30,17,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],'E':[31,16,30,16,16,16,31],'F':[31,16,30,16,16,16,16],'G':[14,17,16,23,17,17,14],'H':[17,17,17,31,17,17,17],'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],'M':[17,27,21,17,17,17,17],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'X':[17,17,10,4,10,17,17],'Y':[17,17,10,4,4,4,4],'Z':[31,1,2,4,8,16,31],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],'!':[4,4,4,4,0,0,4],':':[0,0,4,0,4,0,0],'.':[0,0,0,0,0,0,4],'=':[0,0,31,0,31,0,0]};
function drawT(t,x,y,s,c){let cx=x;for(let char of (t||"").toString().toUpperCase()){const rows=FONT[char]||FONT[' '];for(let r=0;r<7;r++)for(let col=0;col<5;col++)if(rows[r]&(1<<(4-col)))for(let sy=0;sy<s;sy++)for(let sx=0;sx<s;sx++){let px=cx+col*s+sx,py=y+r*s+sy;if(px>=0&&px<W&&py>=0&&py<H){const i=(py*W+px)*3;rgb[i]=c[0];rgb[i+1]=c[1];rgb[i+2]=c[2];}}cx+=6*s;}}
const flagCache={};function blit(cx,cy,iso,sz,clipRad){const k=`${iso}_${sz}`;if(!flagCache[k])try{flagCache[k]=fs.readFileSync(`${FLAGS_DIR}/${iso}_${sz}.rgb`)}catch(e){return};const b=flagCache[k],x0=Math.floor(cx-sz/2),y0=Math.floor(cy-sz/2);for(let y=0;y<sz;y++)for(let x=0;x<sz;x++){if((x-sz/2)**2+(y-sz/2)**2 > clipRad**2) continue;const si=(y*sz+x)*3,di=((y0+y)*W+(x0+x))*3;if(di>=0&&di<rgb.length-3){rgb[di]=b[si];rgb[di+1]=b[si+1];rgb[di+2]=b[si+2];}}}

let ents=[],deadStack=[],winStats={},state="PLAY",timer=0,lastWin="NONE",winner=null;
const countries=JSON.parse(fs.readFileSync('countries.json','utf8'));

function init(){
  ents=countries.sort(()=>0.5-Math.random()).map(c=>({n:c.name,i:c.iso2.toLowerCase(),x:CX,y:CY,vx:(Math.random()-0.5)*1000,vy:(Math.random()-0.5)*1000,f:false}));
  deadStack=[];state="PLAY";
}

function drawUI(){
  const statsY = 580;
  for(let y=statsY;y<statsY+140;y++)for(let x=100;x<W-100;x++){const idx=(y*W+x)*3;rgb[idx]=25;rgb[idx+1]=25;rgb[idx+2]=30;}
  // Labels made scale 2 (Bigger) per your request
  drawT("LAST WINNER",140,statsY+20,2,[150,150,150]); 
  drawT(lastWin.substring(0,14),140,statsY+70,3,[255,255,255]);
  drawT("ALIVE",580,statsY+20,2,[150,150,150]); // Font scale increased
  drawT(ents.filter(e=>!e.f).length.toString(),580,statsY+70,3,[255,255,255]);
  drawT("!67=BAN",820,statsY+45,4,[255,50,50]);

  for(let y=UI_TOP;y<UI_TOP+280;y++)for(let x=100;x<W-100;x++){const idx=(y*W+x)*3;rgb[idx]=15;rgb[idx+1]=15;rgb[idx+2]=20;}
  drawT("LEADERBOARD",140,UI_TOP+20,3,[255,255,100]);
  const l=Object.entries(winStats).sort((a,b)=>b[1]-a[1]).slice(0,5);
  l.forEach(([n,w],i)=>{
    drawT(`${i+1}.${n.substring(0,14)}`,140,UI_TOP+85+i*38,2,[220,220,220]);
    drawT(w.toString(),850,UI_TOP+85+i*38,2,[255,255,255]);
  });

  // Lose Table (Dead Grid) Optimization
  for(let y=1250;y<1920;y++)for(let x=0;x<W;x++){const idx=(y*W+x)*3;rgb[idx]=10;rgb[idx+1]=10;rgb[idx+2]=15;}
  deadStack.forEach((e,idx)=>{
    const col=idx%18, row=Math.floor(idx/18);
    blit(70+col*54, 1300+row*45, e.i, 24, 12);
  });
}

function loop(){
  for(let i=0;i<rgb.length;i+=3){rgb[i]=165;rgb[i+1]=110;rgb[i+2]=85;}
  const hDeg=(Date.now()/1000*1.5*60)%360;drawUI();
  if(state==="PLAY"){
    for(let a=0;a<360;a+=0.5){let diff=Math.abs(((a-hDeg+180)%360)-180);if(diff<22)continue;const r=a*Math.PI/180;for(let t=-6;t<6;t++){const px=Math.floor(CX+(RING_R+t)*Math.cos(r)),py=Math.floor(CY+(RING_R+t)*Math.sin(r));if(px>=0&&px<W&&py>=0&&py<H){const idx=(py*W+px)*3;rgb[idx]=255;rgb[idx+1]=255;rgb[idx+2]=255;}}}
    ents.forEach((e,i)=>{
      if(e.f){
        const ti=deadStack.indexOf(e);
        const tx=70+(ti%18)*54, ty=1300+Math.floor(ti/18)*45;
        e.x+=(tx-e.x)*0.2;e.y+=(ty-e.y)*0.2;blit(e.x,e.y,e.i,24,12);return;
      }
      for(let j=i+1;j<ents.length;j++){
        let b=ents[j];if(b.f)continue;
        let dx=b.x-e.x,dy=b.y-e.y,d=Math.sqrt(dx*dx+dy*dy);
        if(d<R*2&&d>0){
          let nx=dx/d,ny=dy/d,ov=(R*2-d)+1;
          e.x-=nx*(ov/2);e.y-=ny*(ov/2);b.x+=nx*(ov/2);b.y+=ny*(ov/2);
          let p=(e.vx*nx+e.vy*ny-(b.vx*nx+b.vy*ny));e.vx-=p*nx;e.vy-=p*ny;b.vx+=p*nx;b.vy+=p*ny;
        }
      }
      e.x+=e.vx*DT;e.y+=e.vy*DT;
      let dx=e.x-CX,dy=e.y-CY,dist=Math.sqrt(dx*dx+dy*dy);
      if(dist>RING_R-R){
        const ang=(Math.atan2(dy,dx)*180/Math.PI+360)%360;
        if(Math.abs(((ang-hDeg+180)%360)-180)<22){ e.f=true;deadStack.push(e); }
        else {
          let nx=dx/dist,ny=dy/dist,dot=e.vx*nx+e.vy*ny;
          e.vx=(e.vx-2*dot*nx)*1.02;e.vy=(e.vy-2*dot*ny)*1.02;
          e.x=CX+nx*(RING_R-R);e.y=CY+ny*(RING_R-R);
        }
      }
      blit(e.x,e.y,e.i,40,R);
    });
    let alive=ents.filter(e=>!e.f);
    if(alive.length===1){state="WIN";winner=alive[0];lastWin=winner.n;timer=0;winStats[winner.n]=(winStats[winner.n]||0)+1;}
  } else {
    for(let y=700;y<1150;y++)for(let x=150;x<W-150;x++){const idx=(y*W+x)*3;rgb[idx]=30;rgb[idx+1]=40;rgb[idx+2]=100;}
    drawT("WINNER!",CX-140,740,5,[255,255,255]);
    if(winner) blit(CX, 930, winner.i, 240, 110); 
    drawT(winner ? winner.n : "",CX-200,1080,3,[255,255,255]);
    if(++timer>300)init();
  }process.stdout.write(rgb);
}
init();setInterval(loop,1000/FPS);
JS

# --- THE START ---
while true; do
  if verify_stream_path; then
    FLAGS_DIR="$FLAGS_DIR" node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel warning -y \
      -f rawvideo -pixel_format rgb24 -video_size 1080x1920 -framerate 60 -i - \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
      -g 120 -b:v 8000k -minrate 8000k -maxrate 8000k -bufsize 16000k \
      -f flv "$YOUTUBE_URL"
  fi
  echo "Retrying stream handshake in 5s..."
  sleep 5
done
