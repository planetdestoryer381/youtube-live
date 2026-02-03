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

# --- Pre-Render Engine (Full Speed) ---
download_flag () {
  local iso=$(echo "$1" | tr 'A-Z' 'a-z')
  [ -s "$FLAGS_DIR/${iso}_70.rgb" ] && return 0
  local png="$FLAGS_DIR/${iso}.png"
  if curl -m 3 -fsSL "https://flagcdn.com/w160/${iso}.png" -o "$png"; then
    ffmpeg -loglevel error -y -i "$png" -vf "scale=70:70" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_70.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=50:50" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_50.rgb" || true
    ffmpeg -loglevel error -y -i "$png" -vf "scale=240:240" -f rawvideo -pix_fmt rgb24 "$FLAGS_DIR/${iso}_240.rgb" || true
    rm -f "$png"
  fi
}

# --- Standalone Node.js Physics & Graphics Engine ---
cat > /tmp/yt_sim.js <<'JS'
const fs = require('fs');
const W=1080, H=1920, FPS=60, R=35, RING_R=420, DT=1/60;
const CX=W/2, CY=H/2, FLAGS_DIR="/tmp/flags";
const rgb = Buffer.alloc(W * H * 3);

// FULL LIST FROM YOUR JSON
const countries = [{"name":"Afghanistan","iso2":"af"},{"name":"Albania","iso2":"al"},{"name":"Algeria","iso2":"dz"},{"name":"Andorra","iso2":"ad"},{"name":"Angola","iso2":"ao"},{"name":"Antigua and Barbuda","iso2":"ag"},{"name":"Argentina","iso2":"ar"},{"name":"Armenia","iso2":"am"},{"name":"Australia","iso2":"au"},{"name":"Austria","iso2":"at"},{"name":"Azerbaijan","iso2":"az"},{"name":"Bahamas","iso2":"bs"},{"name":"Bahrain","iso2":"bh"},{"name":"Bangladesh","iso2":"bd"},{"name":"Barbados","iso2":"bb"},{"name":"Belarus","iso2":"by"},{"name":"Belgium","iso2":"be"},{"name":"Belize","iso2":"bz"},{"name":"Benin","iso2":"bj"},{"name":"Bhutan","iso2":"bt"},{"name":"Bolivia","iso2":"bo"},{"name":"Bosnia and Herzegovina","iso2":"ba"},{"name":"Botswana","iso2":"bw"},{"name":"Brazil","iso2":"br"},{"name":"Brunei","iso2":"bn"},{"name":"Bulgaria","iso2":"bg"},{"name":"Burkina Faso","iso2":"bf"},{"name":"Burundi","iso2":"bi"},{"name":"Cambodia","iso2":"kh"},{"name":"Cameroon","iso2":"cm"},{"name":"Canada","iso2":"ca"},{"name":"Cape Verde","iso2":"cv"},{"name":"Central African Republic","iso2":"cf"},{"name":"Chad","iso2":"td"},{"name":"Chile","iso2":"cl"},{"name":"China","iso2":"cn"},{"name":"Colombia","iso2":"co"},{"name":"Comoros","iso2":"km"},{"name":"Congo","iso2":"cg"},{"name":"Costa Rica","iso2":"cr"},{"name":"Croatia","iso2":"hr"},{"name":"Cuba","iso2":"cu"},{"name":"Cyprus","iso2":"cy"},{"name":"Czech Republic","iso2":"cz"},{"name":"Denmark","iso2":"dk"},{"name":"Djibouti","iso2":"dj"},{"name":"Dominica","iso2":"dm"},{"name":"Dominican Republic","iso2":"do"},{"name":"Ecuador","iso2":"ec"},{"name":"Egypt","iso2":"eg"},{"name":"El Salvador","iso2":"sv"},{"name":"Equatorial Guinea","iso2":"gq"},{"name":"Eritrea","iso2":"er"},{"name":"Estonia","iso2":"ee"},{"name":"Eswatini","iso2":"sz"},{"name":"Ethiopia","iso2":"et"},{"name":"Fiji","iso2":"fj"},{"name":"Finland","iso2":"fi"},{"name":"France","iso2":"fr"},{"name":"Gabon","iso2":"ga"},{"name":"Gambia","iso2":"gm"},{"name":"Georgia","iso2":"ge"},{"name":"Germany","iso2":"de"},{"name":"Ghana","iso2":"gh"},{"name":"Greece","iso2":"gr"},{"name":"Grenada","iso2":"gd"},{"name":"Guatemala","iso2":"gt"},{"name":"Guinea","iso2":"gn"},{"name":"Guinea-Bissau","iso2":"gw"},{"name":"Guyana","iso2":"gy"},{"name":"Haiti","iso2":"ht"},{"name":"Honduras","iso2":"hn"},{"name":"Hungary","iso2":"hu"},{"name":"Iceland","iso2":"is"},{"name":"India","iso2":"in"},{"name":"Indonesia","iso2":"id"},{"name":"Iran","iso2":"ir"},{"name":"Iraq","iso2":"iq"},{"name":"Ireland","iso2":"ie"},{"name":"Israel","iso2":"il"},{"name":"Italy","iso2":"it"},{"name":"Jamaica","iso2":"jm"},{"name":"Japan","iso2":"jp"},{"name":"Jordan","iso2":"jo"},{"name":"Kazakhstan","iso2":"kz"},{"name":"Kenya","iso2":"ke"},{"name":"Kiribati","iso2":"ki"},{"name":"Kuwait","iso2":"kw"},{"name":"Kyrgyzstan","iso2":"kg"},{"name":"Laos","iso2":"la"},{"name":"Latvia","iso2":"lv"},{"name":"Lebanon","iso2":"lb"},{"name":"Lesotho","iso2":"ls"},{"name":"Liberia","iso2":"lr"},{"name":"Libya","iso2":"ly"},{"name":"Liechtenstein","iso2":"li"},{"name":"Lithuania","iso2":"lt"},{"name":"Luxembourg","iso2":"lu"},{"name":"Madagascar","iso2":"mg"},{"name":"Malawi","iso2":"mw"},{"name":"Malaysia","iso2":"my"},{"name":"Maldives","iso2":"mv"},{"name":"Mali","iso2":"ml"},{"name":"Malta","iso2":"mt"},{"name":"Marshall Islands","iso2":"mh"},{"name":"Mauritania","iso2":"mr"},{"name":"Mauritius","iso2":"mu"},{"name":"Mexico","iso2":"mx"},{"name":"Micronesia","iso2":"fm"},{"name":"Moldova","iso2":"md"},{"name":"Monaco","iso2":"mc"},{"name":"Mongolia","iso2":"mn"},{"name":"Montenegro","iso2":"me"},{"name":"Morocco","iso2":"ma"},{"name":"Mozambique","iso2":"mz"},{"name":"Myanmar","iso2":"mm"},{"name":"Namibia","iso2":"na"},{"name":"Nauru","iso2":"nr"},{"name":"Nepal","iso2":"np"},{"name":"Netherlands","iso2":"nl"},{"name":"New Zealand","iso2":"nz"},{"name":"Nicaragua","iso2":"ni"},{"name":"Niger","iso2":"ne"},{"name":"Nigeria","iso2":"ng"},{"name":"North Korea","iso2":"kp"},{"name":"North Macedonia","iso2":"mk"},{"name":"Norway","iso2":"no"},{"name":"Oman","iso2":"om"},{"name":"Pakistan","iso2":"pk"},{"name":"Palau","iso2":"pw"},{"name":"Palestine","iso2":"ps"},{"name":"Panama","iso2":"pa"},{"name":"Papua New Guinea","iso2":"pg"},{"name":"Paraguay","iso2":"py"},{"name":"Peru","iso2":"pe"},{"name":"Philippines","iso2":"ph"},{"name":"Poland","iso2":"pl"},{"name":"Portugal","iso2":"pt"},{"name":"Qatar","iso2":"qa"},{"name":"Romania","iso2":"ro"},{"name":"Russia","iso2":"ru"},{"name":"Rwanda","iso2":"rw"},{"name":"Saint Kitts and Nevis","iso2":"kn"},{"name":"Saint Lucia","iso2":"lc"},{"name":"Saint Vincent and the Grenadines","iso2":"vc"},{"name":"Samoa","iso2":"ws"},{"name":"San Marino","iso2":"sm"},{"name":"Sao Tome and Principe","iso2":"st"},{"name":"Saudi Arabia","iso2":"sa"},{"name":"Senegal","iso2":"sn"},{"name":"Serbia","iso2":"rs"},{"name":"Seychelles","iso2":"sc"},{"name":"Sierra Leone","iso2":"sl"},{"name":"Singapore","iso2":"sg"},{"name":"Slovakia","iso2":"sk"},{"name":"Slovenia","iso2":"si"},{"name":"Solomon Islands","iso2":"sb"},{"name":"Somalia","iso2":"so"},{"name":"South Africa","iso2":"za"},{"name":"South Korea","iso2":"kr"},{"name":"South Sudan","iso2":"ss"},{"name":"Spain","iso2":"es"},{"name":"Sri Lanka","iso2":"lk"},{"name":"Sudan","iso2":"sd"},{"name":"Suriname","iso2":"sr"},{"name":"Sweden","iso2":"se"},{"name":"Switzerland","iso2":"ch"},{"name":"Syria","iso2":"sy"},{"name":"Tajikistan","iso2":"tj"},{"name":"Tanzania","iso2":"tz"},{"name":"Thailand","iso2":"th"},{"name":"Timor-Leste","iso2":"tl"},{"name":"Togo","iso2":"tg"},{"name":"Tonga","iso2":"to"},{"name":"Trinidad and Tobago","iso2":"tt"},{"name":"Tunisia","iso2":"tn"},{"name":"Turkey","iso2":"tr"},{"name":"Turkmenistan","iso2":"tm"},{"name":"Tuvalu","iso2":"tv"},{"name":"Uganda","iso2":"ug"},{"name":"Ukraine","iso2":"ua"},{"name":"United Arab Emirates","iso2":"ae"},{"name":"United Kingdom","iso2":"gb"},{"name":"United States","iso2":"us"},{"name":"Uruguay","iso2":"uy"},{"name":"Uzbekistan","iso2":"uz"},{"name":"Vanuatu","iso2":"vu"},{"name":"Vatican City","iso2":"va"},{"name":"Venezuela","iso2":"ve"},{"name":"Vietnam","iso2":"vn"},{"name":"Yemen","iso2":"ye"},{"name":"Zambia","iso2":"zm"},{"name":"Zimbabwe","iso2":"zw"}];

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

function init(){
  ents=countries.sort(()=>0.5-Math.random()).slice(0,30).map(c=>({
    n:c.name, i:c.iso2.toLowerCase(), x:CX, y:CY, vx:(Math.random()-0.5)*1100, vy:(Math.random()-0.5)*1100, a:true, f:false
  }));
  deadStack=[]; state="PLAY";
}

function drawUI(){
  // Top Header Row
  for(let i=0;i<3;i++) {
    const c = (i===0)? [25,25,30] : [40,40,45];
    for(let y=60;y<180;y++) for(let x=40+i*340;x<340+i*340;x++){
      const idx=(y*W+x)*3; rgb[idx]=c[0]; rgb[idx+1]=c[1]; rgb[idx+2]=c[2];
    }
  }
  drawT("LAST WINNER", 60, 80, 1, [180,180,180]);
  drawT(lastWin.substring(0,14), 60, 110, 2, [255,255,255]);
  drawT("MODE", 400, 80, 1, [180,180,180]);
  drawT("LAST ONE WINS", 400, 110, 2, [255,255,255]);
  drawT("!67 = BAN", 760, 105, 4, [255, 50, 50]);

  // Leaderboard
  drawT("SESSION WINS", 40, 210, 2, [255,255,255]);
  Object.entries(winStats).sort((a,b)=>b[1]-a[1]).slice(0,5).forEach(([name, count], i) => {
    drawT(`${i+1}. ${name.substring(0,12)}: ${count}`, 40, 250 + i*35, 2, [255,255,200]);
  });

  // Empty Lose Area Grid
  for(let y=1500;y<1880;y++) for(let x=0;x<W;x++){
    const idx=(y*W+x)*3; rgb[idx]=15; rgb[idx+1]=15; rgb[idx+2]=20;
  }
  deadStack.forEach((e, idx) => {
    const col=idx%11, row=Math.floor(idx/11);
    blit(95+col*90, 1560+row*95, 23, e.i, 50);
  });
}

function loop(){
  // Main Background
  for(let i=0;i<rgb.length;i+=3){ rgb[i]=158; rgb[i+1]=100; rgb[i+2]=75; }
  const hDeg=(Date.now()/1000*1.2*60)%360;
  drawUI();
  
  if(state==="PLAY"){
    // Thick Arena Ring
    for(let a=0;a<360;a+=0.3){
      let diff=Math.abs(((a-hDeg+180)%360)-180);
      if(diff<25)continue;
      const r=a*Math.PI/180;
      for(let t=-14;t<14;t++){
        const px=Math.floor(CX+(RING_R+t)*Math.cos(r)), py=Math.floor(CY+(RING_R+t)*Math.sin(r));
        if(px>=0&&px<W&&py>=0&&py<H){ const idx=(py*W+px)*3; rgb[idx]=255; rgb[idx+1]=255; rgb[idx+2]=255; }
      }
    }

    ents.forEach((e, i) => {
      if(e.f){ 
        const targetIdx = deadStack.indexOf(e);
        const tx = 95 + (targetIdx%11)*90, ty = 1560 + Math.floor(targetIdx/11)*95;
        e.x += (tx - e.x) * 0.12; e.y += (ty - e.y) * 0.12;
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
    // Summary Card
    for(let y=400;y<1300;y++) for(let x=100;x<980;x++){
      const idx=(y*W+x)*3; rgb[idx]=30; rgb[idx+1]=45; rgb[idx+2][idx+2]=95;
    }
    drawT("ROUND SUMMARY", 320, 430, 5, [255,255,255]);
    blit(W/2, 900, 120, winner.i, 240);
    drawT(winner.n, 300, 1100, 4, [255,255,255]);
    if(++timer > 300) init();
  }
  process.stdout.write(rgb);
}
init();
setInterval(loop, 1000/FPS);
JS

# --- Asset Prep & Loop ---
echo "--- Fast Flag Setup ---"
# Trigger background download for all integrated countries
echo 'const c=[{"iso2":"af"},{"iso2":"al"},{"iso2":"dz"},{"iso2":"ad"},{"iso2":"ao"},{"iso2":"ag"},{"iso2":"ar"},{"iso2":"am"},{"iso2":"au"},{"iso2":"at"},{"iso2":"az"},{"iso2":"bs"},{"iso2":"bh"},{"iso2":"bd"},{"iso2":"bb"},{"iso2":"by"},{"iso2":"be"},{"iso2":"bz"},{"iso2":"bj"},{"iso2":"bt"},{"iso2":"bo"},{"iso2":"ba"},{"iso2":"bw"},{"iso2":"br"},{"iso2":"bn"},{"iso2":"bg"},{"iso2":"bf"},{"iso2":"bi"},{"iso2":"kh"},{"iso2":"cm"},{"iso2":"ca"},{"iso2":"cv"},{"iso2":"cf"},{"iso2":"td"},{"iso2":"cl"},{"iso2":"cn"},{"iso2":"co"},{"iso2":"km"},{"iso2":"cg"},{"iso2":"cr"},{"iso2":"hr"},{"iso2":"cu"},{"iso2":"cy"},{"iso2":"cz"},{"iso2":"dk"},{"iso2":"dj"},{"iso2":"dm"},{"iso2":"do"},{"iso2":"ec"},{"iso2":"eg"},{"iso2":"sv"},{"name":"Equatorial Guinea","iso2":"gq"},{"iso2":"er"},{"iso2":"ee"},{"iso2":"sz"},{"iso2":"et"},{"iso2":"fj"},{"iso2":"fi"},{"iso2":"fr"},{"iso2":"ga"},{"iso2":"gm"},{"iso2":"ge"},{"iso2":"de"},{"iso2":"gh"},{"iso2":"gr"},{"iso2":"gd"},{"iso2":"gt"},{"iso2":"gn"},{"iso2":"gw"},{"iso2":"gy"},{"iso2":"ht"},{"iso2":"hn"},{"iso2":"hu"},{"iso2":"is"},{"iso2":"in"},{"iso2":"id"},{"iso2":"ir"},{"iso2":"iq"},{"iso2":"ie"},{"iso2":"il"},{"iso2":"it"},{"iso2":"jm"},{"iso2":"jp"},{"iso2":"jo"},{"iso2":"kz"},{"iso2":"ke"},{"iso2":"ki"},{"iso2":"kw"},{"iso2":"kg"},{"iso2":"la"},{"iso2":"lv"},{"iso2":"lb"},{"iso2":"ls"},{"iso2":"lr"},{"iso2":"ly"},{"iso2":"li"},{"iso2":"lt"},{"iso2":"lu"},{"iso2":"mg"},{"iso2":"mw"},{"iso2":"my"},{"iso2":"mv"},{"iso2":"ml"},{"iso2":"mt"},{"iso2":"mh"},{"iso2":"mr"},{"iso2":"mu"},{"iso2":"mx"},{"iso2":"fm"},{"iso2":"md"},{"iso2":"mc"},{"iso2":"mn"},{"iso2":"me"},{"iso2":"ma"},{"iso2":"mz"},{"iso2":"mm"},{"iso2":"na"},{"iso2":"nr"},{"iso2":"np"},{"iso2":"nl"},{"iso2":"nz"},{"iso2":"ni"},{"iso2":"ne"},{"iso2":"ng"},{"iso2":"kp"},{"iso2":"mk"},{"iso2":"no"},{"iso2":"om"},{"iso2":"pk"},{"iso2":"pw"},{"iso2":"ps"},{"iso2":"pa"},{"iso2":"pg"},{"iso2":"py"},{"iso2":"pe"},{"iso2":"ph"},{"iso2":"pl"},{"iso2":"pt"},{"iso2":"qa"},{"iso2":"ro"},{"iso2":"ru"},{"iso2":"rw"},{"iso2":"kn"},{"iso2":"lc"},{"iso2":"vc"},{"iso2":"ws"},{"iso2":"sm"},{"iso2":"st"},{"iso2":"sa"},{"iso2":"sn"},{"iso2":"rs"},{"iso2":"sc"},{"iso2":"sl"},{"iso2":"sg"},{"iso2":"sk"},{"iso2":"si"},{"iso2":"sb"},{"iso2":"so"},{"iso2":"za"},{"iso2":"kr"},{"iso2":"ss"},{"iso2":"es"},{"iso2":"lk"},{"iso2":"sd"},{"iso2":"sr"},{"iso2":"se"},{"iso2":"ch"},{"iso2":"sy"},{"iso2":"tj"},{"iso2":"tz"},{"iso2":"th"},{"iso2":"tl"},{"iso2":"tg"},{"iso2":"to"},{"iso2":"tt"},{"iso2":"tn"},{"iso2":"tr"},{"iso2":"tm"},{"iso2":"tv"},{"iso2":"ug"},{"iso2":"ua"},{"iso2":"ae"},{"iso2":"gb"},{"iso2":"us"},{"iso2":"uy"},{"iso2":"uz"},{"iso2":"vu"},{"iso2":"va"},{"iso2":"ve"},{"iso2":"vn"},{"iso2":"ye"},{"iso2":"zm"},{"iso2":"zw"}]; c.forEach(x=>console.log(x.iso2))' | node | xargs -P 4 -I {} bash -c 'download_flag "{}"'

# --- Final FFmpeg Loop ---
while true; do
  node /tmp/yt_sim.js | ffmpeg -hide_banner -loglevel error -y \
    -f rawvideo -pixel_format rgb24 -video_size 1080x1920 -framerate 60 -i - \
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -g 120 -b:v 4500k -f flv "$YOUTUBE_URL"
  sleep 2
done
