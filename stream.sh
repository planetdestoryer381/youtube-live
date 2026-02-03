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

# --- High-Speed Asset Loader with Timeout ---
download_flag () {
  local iso=$(echo "$1" | tr 'A-Z' 'a-z')
  local png="$FLAGS_DIR/${iso}.png"
  # If the render exists, skip
  [ -s "$FLAGS_DIR/${iso}_70.rgb" ] && return 0
  
  # Fetch with a 5-second timeout so it doesn't get stuck forever
  if curl -m 5 -fsSL "https://flagcdn.com/w160/${iso}.png" -o "$png"; then
    ffmpeg -loglevel error -y -i "$png" -vf "scale=70:70" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_70.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=50:50" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_50.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=40:40" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_40.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=240:240" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_240.rgb" || true
    rm -f "$png" # Save space
  else
    echo "Skipping $iso - download failed"
  fi
}

echo "--- Loading Assets (Fast Mode) ---"
# Only grab a subset initially to get the stream live faster
ISO_LIST=$(grep -oE '"iso2"[[:space:]]*:[[:space:]]*"[^"]+"' "./countries.json" | head -n 50 | cut -d'"' -f4 | tr 'A-Z' 'a-z')
for iso in $ISO_LIST; do download_flag "$iso"; done

# --- Node.js Engine ---
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');
const W=1080, H=1920, FPS=60, R=35, RING_R=420, DT=1/60;
const CX=W/2, CY=H/2, FLAGS_DIR="/tmp/flags";
const rgb = Buffer.alloc(W * H * 3);

// Fast text drawing
const FONT={'A':[14,17,17,31,17,17,17],'B':[30,17,30,17,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],'E':[31,16,30,16,16,16,31],'F':[31,16,30,16,16,16,16],'G':[14,17,16,23,17,17,14],'H':[17,17,17,31,17,17,17],'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],'M':[17,27,21,17,17,17,17],'N':[17,25,21,19,17,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,18,17,17],'S':[15,16,14,1,1,17,14],'T':[31,4,4,4,4,4,4],'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,27,17],'X':[17,17,10,4,10,17,17],'Y':[17,17,10,4,4,4,4],'Z':[31,1,2,4,8,16,31],'0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,6,8,16,31],'3':[30,1,1,14,1,1,30],'4':[2,6,10,18,31,2,2],'5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],' ':[0,0,0,0,0,0,0],'!':[4,4,4,4,0,0,4],'=':[0,0,31,0,31,0,0],':':[0,0,4,0,4,0,0],'.':[0,0,0,0,0,0,4]};
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
function blit(cx,cy,rad,iso,sz){
  const k=`${iso}_${sz}`; if(!flagCache[k]) try{flagCache[k]=fs.readFileSync(`${FLAGS_DIR}/${iso}_${sz}.rgb`)}catch(e){return};
  const b=flagCache[k], x0=Math.floor(cx-sz/2), y0=Math.floor(cy-sz/2);
  for(let y=0;y<sz;y++) for(let x=0;x<sz;x++){
    if((x-sz/2)**2+(y-sz/2)**2 > rad**2) continue;
    const si=(y*sz+x)*3, di=((y0+y)*W+(x0+x))*3;
    if(di>=0 && di<rgb.length-3){ rgb[di]=b[si]; rgb[di+1]=b[si+1]; rgb[di+2]=b[si+2]; }
  }
}

let ents=[], deadStack=[], winStats={}, state="PLAY", timer=0, lastWin="NONE", lastIso="un";
const countries=JSON.parse(fs.readFileSync("./countries.json","utf8"));

function init(){
  ents=countries.sort(()=>0.5-Math.random()).slice(0,25).map(c=>({
    n:c.name, i:c.iso2.toLowerCase(), x:CX, y:CY, vx:(Math.random()-0.5)*900, vy:(Math.random()-0.5)*900, a:true, f:false
  }));
  deadStack=[]; state="PLAY";
}

function drawUI(){
  // Top Row Background
  for(let i=0;i<3;i++) {
    const c = (i===0)? [25,25,30] : [40,40,45];
    for(let y=60;y<180;y++) for(let x=40+i*340;x<340+i*340;x++){
      const idx=(y*W+x)*3; rgb[idx]=c[0]; rgb[idx+1]=c[1]; rgb[idx+2]=c[2];
    }
  }
  drawT("LAST WINNER", 60, 80, 1, [180,180,180]);
  drawT(lastWin.substring(0,12), 60, 110, 2, [255,255,255]);
  drawT("MODE", 400, 80, 1, [180,180,180]);
  drawT("LAST ONE WINS", 400, 110, 2, [255,255,255]);
  drawT("!67 = BAN", 760, 105, 4, [255, 50, 50]);

  // Win Leaderboard
  drawT("WIN LEADERBOARD", 40, 210, 2, [255,255,255]);
  Object.entries(winStats).sort((a,b)=>b[1]-a[1]).slice(0,5).forEach(([name, count], i) => {
    drawT(`${i+1}. ${name.substring(0,10)}: ${count}`, 40, 250 + i*35, 2, [255,255,200]);
  });

  // Empty Lose Area
  for(let y=1500;y<1850;y++) for(let x=0;x<W;x++){
    const idx=(y*W+x)*3; rgb[idx]=15; rgb[idx+1]=15; rgb[idx+2]=20;
  }
  deadStack.forEach((e, idx) => {
    const col=idx%12, row=Math.floor(idx/12);
    blit(80+col*85, 1560+row*90, 22, e.i, 50);
  });
}

function loop(){
  // Main Background
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=158; rgb[i+1]=100; rgb[i+2]=75; }
  const hDeg=(Date.now()/1000*1.1*60)%360;
  drawUI();
  
  if(state==="PLAY"){
    // 2x Thicker Ring
    for(let a=0;a<360;a+=0.3){
      let diff=Math.abs(((a-hDeg+180)%360)-180);
      if(diff<25)continue;
      const r=a*Math.PI/180;
      for(let t=-10;t<10;t++){
        const px=Math.floor(CX+(RING_R+t)*Math.cos(r)), py=Math.floor(CY+(RING_R+t)*Math.sin(r));
        if(px>=0&&px<W&&py>=0&&py<H){ const idx=(py*W+px)*3; rgb[idx]=255; rgb[idx+1]=255; rgb[idx+2]=255; }
      }
    }

    ents.forEach((e, i) => {
      if(e.f){ 
        const targetIdx = deadStack.indexOf(e);
        const tx = 80 + (targetIdx%12)*85, ty = 1560 + Math.floor(targetIdx/12)*90;
        e.x += (tx - e.x) * 0.1; e.y += (ty - e.y) * 0.1;
        blit(e.x, e.y, R, e.i, 70);
        return;
      }
      if(!e.a) return;

      for(let j=i+1;j<ents.length;j++){
        let b=ents[j]; if(!b.a || b.f) continue;
        let dx=b.x-e.x, dy=b.y-e.y, d=Math.sqrt(dx*dx+dy*dy);
        if(d < R*2 && d>0){
          let nx=dx/d, ny=dy/d, overlap=(R*2-d)+2;
          e.x-=nx*(overlap/2); e.y-=ny*(overlap/2); b.x+=nx*(overlap/2); b.y+=ny*(overlap/2);
          let p=(e.vx*nx+e.vy*ny-(b.vx*nx+b.vy*ny));
          e.vx-=p*nx; e.vy-=p*ny; b.vx+=p*nx; b.vy+=p*ny;
        }
      }
      e.x+=e.vx*DT; e.y+=e.vy*DT;
      let dx=e.x-CX, dy=e.y-CY, dist=Math.sqrt(dx*dx+dy*dy);
      if(dist > RING_R-R){
        const ang=(Math.atan2(dy,dx)*180/Math.PI+360)%360;
        if(Math.abs(((ang-hDeg+180)%360)-180) < 25){
          e.f=true; deadStack.push(e);
        } else {
          let nx=dx/dist, ny=dy/dist, dot=e.vx*nx+e.vy*ny;
          e.vx=(e.vx-2*dot*nx)*1.02; e.vy=(e.vy-2*dot*ny)*1.02;
          e.x=CX+nx*(RING_R-R); e.y=CY+ny*(RING_R-R);
        }
      }
      blit(e.x,e.y,R,e.i,70);
    });

    let alive=ents.filter(e=>e.a && !e.f);
    if(alive.length===1){ 
      state="WIN"; winner=alive[0]; lastWin=winner.n; lastIso=winner.i; timer=0;
      winStats[winner.n] = (winStats[winner.n]||0) + 1;
    }
  } else {
    // Round Summary
    for(let y=400;y<1300;y++) for(let x=100;x<980;x++){
      const idx=(y*W+x)*3; rgb[idx]=30; rgb[idx+1]=45; rgb[idx+2]=95;
    }
    drawT("ROUND SUMMARY", 320, 430, 5, [255,255,255]);
    blit(W/2, 900, 120, winner.i, 240);
    drawT(winner.n, 350, 1100, 4, [255,255,255]);
    if(++timer > 300) init();
  }
  process.stdout.write(rgb);
}
init();
setInterval(loop, 1000/FPS);
JS

# --- Start Stream Immediately ---
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel error -y \
    -f rawvideo -pixel_format rgb24 -video_size 1080x1920 -framerate 60 -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -g 120 -b:v 4000k -f flv "$YOUTUBE_URL"
  sleep 2
done
