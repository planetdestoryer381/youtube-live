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

// --- tiny 5
