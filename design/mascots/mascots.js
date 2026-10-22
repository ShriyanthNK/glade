// Procedural 32x32 pixel mascots in the style of Mochi: plum outline, light from the top-left, five moods.
// Each draw function returns {px: Uint8Array(32*32) of palette indexes, pal: [css colors]}.
const N = 32;

function hexToRgb(h) { return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]; }
function rgbToHex(r, g, b) { return '#' + [r, g, b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join(''); }
function mix(a, b, t) { const A = hexToRgb(a), B = hexToRgb(b); return rgbToHex(A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t); }

class Canvas32 {
  constructor() { this.px = new Uint8Array(N * N); }
  get(x, y) { return x < 0 || x >= N || y < 0 || y >= N ? 0 : this.px[y * N + x]; }
  set(x, y, c) { if (x >= 0 && x < N && y >= 0 && y < N) this.px[y * N + x] = c; }
  rect(x, y, w, h, c) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, c); }
  inEllipse(x, y, cx, cy, rx, ry) { const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry; return dx * dx + dy * dy <= 1; }
  ellipse(cx, cy, rx, ry, c) { for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (this.inEllipse(x, y, cx, cy, rx, ry)) this.set(x, y, c); }
  // a filled ellipse with a 1px outline drawn over whatever is behind it
  blob(cx, cy, rx, ry, fill, ink) {
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      if (this.inEllipse(x, y, cx, cy, rx, ry)) this.set(x, y, fill);
      else if (this.inEllipse(x, y, cx, cy, rx + 1, ry + 1)) this.set(x, y, ink);
    }
  }
  line(x0, y0, x1, y1, c) {
    const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) { this.set(x0, y0, c); if (x0 === x1 && y0 === y1) break; const e2 = 2 * err; if (e2 >= dy) { err += dy; x0 += sx; } if (e2 <= dx) { err += dx; y0 += sy; } }
  }
  poly(pts, c) {   // scanline fill of a small convex polygon
    const ys = pts.map(p => p[1]); const y0 = Math.min(...ys), y1 = Math.max(...ys);
    for (let y = y0; y <= y1; y++) {
      const xs = [];
      for (let i = 0; i < pts.length; i++) {
        const [ax, ay] = pts[i], [bx, by] = pts[(i + 1) % pts.length];
        if ((ay <= y + 0.5 && by > y + 0.5) || (by <= y + 0.5 && ay > y + 0.5)) xs.push(ax + (y + 0.5 - ay) / (by - ay) * (bx - ax));
      }
      xs.sort((a, b) => a - b);
      for (let i = 0; i + 1 < xs.length; i += 2) for (let x = Math.round(xs[i]); x < Math.round(xs[i + 1]); x++) this.set(x, y, c);
    }
  }
  outlineAll(ink) {
    const add = [];
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (this.get(x, y) === 0)
      if (this.get(x + 1, y) || this.get(x - 1, y) || this.get(x, y + 1) || this.get(x, y - 1)) add.push([x, y]);
    add.forEach(([x, y]) => this.set(x, y, ink));
  }
  // 3-wide x 5-tall exclamation / question marks, as in Mochi's signs
  glyph(ch, x, y, c) {
    const rows = ch === '!' ? ['010', '010', '010', '000', '010'] : ['110', '001', '010', '000', '010'];
    rows.forEach((r, j) => [...r].forEach((b, i) => { if (b === '1') this.set(x + i, y + j, c); }));
  }
  plus(x, y, c) { this.set(x, y, c); this.set(x - 1, y, c); this.set(x + 1, y, c); this.set(x, y - 1, c); this.set(x, y + 1, c); }
  sweat(x, y, c, hi) { this.set(x, y, c); this.set(x, y + 1, c); this.set(x - 1, y + 2, c); this.set(x, y + 2, c); this.set(x + 1, y + 2, c); this.set(x, y + 3, c); this.set(x, y + 1, hi); }
  puff(x, y, c) { this.rect(x, y, 3, 2, c); this.rect(x + 1, y - 1, 2, 1, c); this.rect(x - 1, y + 1, 1, 1, c); }
}

// ------------------------------------------------------------------ shared moods
// tier: 0 calm, 1 waiting, 2 annoyed, 3 angry, 4 done
const MOODS = ['calm', 'waiting', 'annoyed', 'angry', 'done'];
function blinkAt(t, period, len = 0.14) { return (t % period) < len; }

// ------------------------------------------------------------------ FIREFLY ("Glim")
// Pale round face with big eyes, a small dark thorax, a dark abdomen whose bottom half is the glowing lamp,
// slim wings, and antennae with glowing tips. Light stalks so they show against the dark scene.
const FIREFLY_GLOW = { calm: '#d4f55e', waiting: '#ffe45c', annoyed: '#ffa83a', angry: '#ff5a3c', done: '#fff2a8' };

Canvas32.prototype.inRot = function (x, y, cx, cy, rx, ry, deg) {
  const a = deg * Math.PI / 180, dx = x + 0.5 - cx, dy = y + 0.5 - cy;
  const u = dx * Math.cos(a) + dy * Math.sin(a), v = -dx * Math.sin(a) + dy * Math.cos(a);
  return (u / rx) * (u / rx) + (v / ry) * (v / ry) <= 1;
};

function drawFirefly(mood, t) {
  const c = new Canvas32();
  const glow = FIREFLY_GLOW[mood];
  const rate = { calm: 1.3, waiting: 3.6, annoyed: 6.5, angry: 11, done: 5 }[mood];
  const pulse = 0.5 + 0.5 * Math.sin(t * rate);
  const done = mood === 'done', angry = mood === 'angry', annoyed = mood === 'annoyed', waiting = mood === 'waiting';
  const lamp = mix('#6a6238', glow, done ? 1 : waiting ? 0.8 + 0.2 * pulse : 0.3 + 0.7 * pulse);
  const pal = [
    null, '#3d2236',
    '#cdeee6', '#ffffff', '#98cbc6',                    // 2 face, 3 face hi, 4 face shade
    '#e6f6ff', '#a9cfe6',                               // 5 wing, 6 wing shade
    lamp, mix(lamp, '#ffffff', 0.6), mix(lamp, '#8a3a1a', 0.5),   // 7 lamp, 8 hi, 9 dk
    '#ffffff', '#ff8fa3', '#6ec6ff', '#ffd23f', '#ff5a3c', '#b8c6d4', // 10 white, 11 cheek, 12 sweat, 13 gold, 14 red, 15 puff
    '#5a3a58', '#7a5278', '#ff8a4c',                    // 16 thorax, 17 thorax hi, 18 orange mark
    '#34505a', '#4d7480', '#25394a',                    // 19 abdomen, 20 hi, 21 dk
    mix(glow, '#2a1a26', 0.3),                          // 22 halo tone
    '#bfe6ea',                                          // 23 antenna stalk (light, shows on dark)
  ];
  const ink = 1, cx = 16;
  const bob = done ? -Math.round(Math.abs(Math.sin(t * 5)) * 2) : angry ? 0 : (Math.sin(t * 2.4) > 0.3 ? -1 : 0);
  const sh = angry ? (Math.floor(t * 16) % 2 ? 1 : 0) : 0;
  const oy = bob, X = cx + sh;
  const hx = waiting ? 1 : 0;
  const headCy = 11 + oy, thoraxCy = 16.4 + oy, absCy = 23 + oy;

  // ---- wings (behind). waiting: lifted and flared.
  const flap = Math.sin(t * (angry ? 46 : done ? 24 : mood === 'calm' ? 8 : 15)) > 0;
  for (const side of [-1, 1]) {
    const tilt = side * ((done ? 30 : 20) + (flap ? 4 : -2) + (waiting ? 8 : 0));
    const wcx = X + side * (done ? 8.8 : waiting ? 9.6 : 8.4), wcy = 12 + oy - (done ? 0.5 : 0) - (waiting ? 2 : 0) + (mood === 'calm' ? 1 : 0);
    const rx = 2.7, ry = done ? 6.1 : 6.6;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      if (c.inRot(x, y, wcx, wcy, rx, ry, tilt)) c.set(x, y, 5);
      else if (c.inRot(x, y, wcx, wcy, rx + 1, ry + 1, tilt)) c.set(x, y, ink);
    }
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 5 && !c.inRot(x, y, wcx - side * 0.7, wcy - 0.7, rx - 0.6, ry - 0.8, tilt)) c.set(x, y, 6);
  }

  // ---- abdomen: dark top, glowing bottom, one outline all the way round
  const arx = 7, ary = 6.6;
  c.blob(X, absCy, arx, ary, 19, ink);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 19) {
    const dx = (x + 0.5 - X) / arx, dy = (y + 0.5 - absCy) / ary;
    const edge = absCy - 1.6 + 0.085 * Math.pow(x + 0.5 - X, 2);     // bowl-shaped lamp boundary: the lamp is the bottom ~60% of the abdomen
    if (y + 0.5 > edge + 0.8) {
      // inside the lamp: bright core to the upper left, darker rim to the lower right
      if (dx * 0.6 + dy * 0.8 > 0.6) c.set(x, y, 9);
      else if (c.inEllipse(x, y, X - 1.8, absCy + 2.2, 3.4, 2.2)) c.set(x, y, 8);
      else c.set(x, y, 7);
    } else if (y + 0.5 > edge) c.set(x, y, (x + y) % 2 ? 7 : 21);         // dithered edge where body melts into glow
    else if (dx * 0.6 + dy * 0.8 > 0.6) c.set(x, y, 21);
    else if (dx * -0.6 + dy * -0.8 > 0.62) c.set(x, y, 20);
  }
  c.set(Math.round(X - 4), Math.round(absCy + 2), 10); c.set(Math.round(X - 3), Math.round(absCy + 1), 10);

  // ---- thorax: a slim plum collar with two orange marks
  c.blob(X, thoraxCy, 4.6, 2.0, 16, ink);
  c.set(Math.round(X - 2), Math.round(thoraxCy), 18); c.set(Math.round(X + 1), Math.round(thoraxCy), 18); c.set(Math.round(X - 3), Math.round(thoraxCy - 1), 17);

  // ---- head: pale and round
  const hcx = X + hx;
  c.blob(hcx, headCy, 5.9, 5.3, 2, ink);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 2) {
    const dx = (x + 0.5 - hcx) / 5.9, dy = (y + 0.5 - headCy) / 5.3;
    if (dx * 0.6 + dy * 0.8 > 0.58) c.set(x, y, 4);
  }
  c.rect(Math.round(hcx - 4), Math.round(headCy - 4), 3, 1, 3); c.set(Math.round(hcx - 5), Math.round(headCy - 3), 3);

  // ---- antennae: light stalks from the top of the head to glowing tips
  const sway = Math.sin(t * 2.6) > 0.25 ? 1 : 0;
  const up = waiting ? 2 : 0, droop = mood === 'calm' ? 1 : 0, back = angry ? 2 : 0;
  for (const side of [-1, 1]) {
    const x0 = Math.round(hcx + side * 2.4), y0 = Math.round(headCy - 5.2);
    const x1 = Math.round(hcx + side * (5.6 + sway + back)), y1 = 5 + oy + back - up + droop;
    c.line(x0, y0, x1, y1, 23);
    const tx = side < 0 ? x1 - 1 : x1;
    c.rect(tx, y1 - 1, 2, 2, 7); c.set(tx, y1 - 1, pulse > 0.4 || done ? 8 : 7);
    c.set(x1 + (side < 0 ? 1 : 0), y1 - 1, 23);   // stalk runs right into the tip
  }

  // ---- face: big dark eyes on the pale face
  const ey = Math.round(headCy - 3);
  const eyeL = Math.round(hcx - 5), eyeR = Math.round(hcx + 1);
  const blink = (mood === 'calm' && ((t % 3.6) < 0.14)) || (waiting && ((t % 2.6) < 0.12));
  function eye(x, h) {
    c.rect(x, ey, 4, h, ink); c.set(x, ey, 2); c.set(x + 3, ey, 2); c.set(x, ey + h - 1, 2); c.set(x + 3, ey + h - 1, 2);
    c.set(x + 1, ey + 1, 10); c.set(x + 2, ey + 2, 12);
    if (h > 4) c.set(x + 1, ey + 2, 10);
  }
  for (const x of [eyeL, eyeR]) {
    if (done) { c.set(x, ey + 3, ink); c.set(x + 1, ey + 2, ink); c.set(x + 2, ey + 2, ink); c.set(x + 3, ey + 3, ink); c.set(x + 1, ey + 3, ink); c.set(x + 2, ey + 3, 0); }
    else if (blink) c.rect(x, ey + 2, 4, 1, ink);
    else if (annoyed) { c.rect(x, ey + 2, 4, 2, ink); c.set(x, ey + 2, 10); c.rect(x - 0, ey + 1, 4, 1, 4); }
    else if (angry) { c.rect(x, ey + 1, 4, 3, ink); c.set(x + 1, ey + 2, 14); c.set(x, ey + 1, 2); c.set(x + 3, ey + 1, 2); }
    else eye(x, waiting ? 5 : 4);
  }
  if (angry) { c.line(eyeL - 1, ey - 1, eyeL + 4, ey + 1, ink); c.line(eyeL - 1, ey, eyeL + 4, ey + 2, ink); c.line(eyeR + 4, ey - 1, eyeR - 1, ey + 1, ink); c.line(eyeR + 4, ey, eyeR - 1, ey + 2, ink); }
  if (annoyed) { c.line(eyeL + 3, ey, eyeL, ey + 1, ink); c.line(eyeR, ey, eyeR + 3, ey + 1, ink); }
  const cheek = done || mood === 'calm' || waiting ? 11 : angry ? 14 : 0;
  if (cheek) { c.rect(Math.round(hcx - 5), ey + 5, 2, 1, cheek); c.rect(Math.round(hcx + 4), ey + 5, 2, 1, cheek); }
  const my = ey + 5, mx = Math.round(hcx);
  if (done) { c.rect(mx - 2, my, 4, 1, ink); c.rect(mx - 1, my + 1, 2, 1, 14); }
  else if (angry) { c.set(mx - 1, my + 1, ink); c.set(mx, my + 1, ink); c.set(mx - 2, my + 2, ink); c.set(mx + 1, my + 2, ink); }
  else if (annoyed) { c.rect(mx - 1, my + 1, 3, 1, ink); }
  else { c.set(mx - 2, my, ink); c.set(mx - 1, my + 1, ink); c.set(mx, my + 1, ink); c.set(mx + 1, my, ink); }

  // ---- halo: a 1px glow rim right outside the abdomen's lower half, plus sparse outer sparks when bright
  const haloR = (done ? 3.4 : 0.9 + 2.2 * pulse) + (angry ? 0.7 : 0);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if (y < absCy + 1 || y > 30 || c.get(x, y) !== 0) continue;
    const d = (Math.hypot((x + 0.5 - X) / arx, (y + 0.5 - absCy) / ary) - 1) * 6.8;
    if (d > 0 && d < 1.9 && pulse > 0.25) c.set(x, y, 7);                                   // solid rim
    else if (d >= 1.9 && d < haloR + 1 && (x * 3 + y * 5) % 7 === 0) c.set(x, y, 22);       // sparks
  }

  // ---- extras, kept off the wings and at least 1px inside the frame
  if (annoyed) { c.sweat(26, 18 + (Math.sin(t * 2) > 0 ? 1 : 0), 12, 10); c.glyph('?', 2, 18, 13); }
  if (angry) { c.glyph('!', 2, 18 + (Math.floor(t * 8) % 2), 14); c.glyph('!', 6, 18 + (Math.floor(t * 8 + 1) % 2), 14); const s = Math.floor(t * 6) % 2; c.puff(25, 23 - s, 15); c.puff(3, 25 - s, 15); }
  if (done) { const k = Math.floor(t * 6); [[3, 20], [28, 19], [4, 26], [27, 26], [2, 12], [29, 12]].forEach(([x, y], i) => { if ((k + i) % 3 !== 0) c.plus(x, y + ((k + i) % 2), 13); }); }
  if (mood === 'calm' || waiting) { [[3, 22, 0], [28, 23, 1.7], [4, 27, 3.1], [27, 28, 4.6]].forEach(([x, y, ph]) => { if (Math.sin(t * 2 + ph) > 0.1) c.set(x, y - (Math.round(Math.sin(t + ph) + 1)), 22); }); }
  return { px: c.px, pal };
}

// ------------------------------------------------------------------ OWL ("Hoot")
function drawOwl(mood, t) {
  const c = new Canvas32();
  const pal = [
    null, '#3d2236',                          // 1 ink
    '#a0704f', '#6f4733', '#c99872',          // 2 feather, 3 feather dk, 4 feather hi
    '#ffe9c8', '#e0b98f',                     // 5 belly, 6 belly mark
    '#fff6dc', '#ffc83d',                     // 7 eye ring, 8 iris
    '#ff9a3c', '#d9741f',                     // 9 beak/feet, 10 beak dk
    '#ff8fa3', '#6ec6ff', '#ffd23f', '#ff5a3c', '#b8c6d4', '#ffffff', // 11 cheek, 12 sweat, 13 gold, 14 red, 15 puff, 16 white
  ];
  const ink = 1;
  const done = mood === 'done', angry = mood === 'angry', annoyed = mood === 'annoyed', waiting = mood === 'waiting';
  const bob = done ? 0 : angry ? 0 : (Math.sin(t * 2) > 0.5 ? -1 : 0);
  const oy = bob, puff = angry ? 1 : 0;
  const lean = waiting ? 1 : angry ? (Math.floor(t * 14) % 2 ? 1 : 0) : 0;
  const ruffle = angry ? (Math.floor(t * 9) % 2) : 0;

  // ear tufts
  const tuft = (side) => {
    const cx = 16 + side * 7.5;
    c.poly([[cx - side * 3.5, 10 + oy], [cx + side * (done ? 2.5 : waiting ? 1.5 : 0.5), 3 + oy - (angry ? ruffle : 0) + (annoyed ? 1 : 0) - (waiting ? 1 : 0)], [cx + side * 3, 10 + oy]], 2);
    // outline the tuft
    const keep = c.px.slice();
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (keep[y * N + x] === 0 && (keep[(y) * N + x + 1] === 2 || keep[(y) * N + x - 1] === 2 || keep[(y + 1) * N + x] === 2 || keep[(y - 1) * N + x] === 2)) c.set(x, y, ink);
  };
  tuft(-1); tuft(1);

  // wings behind: lit from the top left, so the left wing is lighter; tips lift away from the body when waiting
  const wy = done ? 16 : 21;
  for (const side of [-1, 1]) {
    const cx = 16 + side * (done ? 9.6 : 10 + puff * 0.4 + (waiting ? 0.2 : 0)), cy = wy + oy;
    const shear = waiting ? 0.36 : 0.2, ry = done ? 7.0 : 7.2;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const lean2 = (y - cy) * shear * side * (done ? -1.3 : 1);
      if (c.inEllipse(x - lean2, y, cx, cy, 3.6, ry)) c.set(x, y, side < 0 ? 2 : 3);
      else if (c.inEllipse(x - lean2, y, cx, cy, 4.6, ry + 1)) c.set(x, y, ink);
    }
    if (side < 0) for (let k = 0; k < 4; k++) c.set(Math.round(cx - 1 - (waiting ? 0 : 0)), Math.round(cy - 4 + k), 4);
  }

  // body
  const bx = 16 + lean, by = 18 + oy;
  c.blob(bx, by, 10 + puff, 11.5 + puff * 0.5, 2, ink);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 2) {
    const dx = (x + 0.5 - bx) / 10, dy = (y + 0.5 - by) / 11.5;
    if (dx * 0.6 + dy * 0.8 > 0.6) c.set(x, y, 3);
  }
  c.rect(bx - 7, by - 9, 3, 1, 4); c.rect(bx - 8, by - 8, 2, 2, 4);
  // forehead feather marks
  [[bx - 3, by - 9], [bx, by - 10], [bx + 3, by - 9]].forEach(([x, y]) => { c.set(x, y, 3); c.set(x, y + 1, 3); });

  // belly
  c.ellipse(bx, by + 4.5, 6.3 + puff * 0.6, 7.3, 5);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 5 && c.inEllipse(x, y, bx, by + 4.5, 7.3 + puff * 0.6, 8.3) && !c.inEllipse(x, y, bx, by + 4.5, 5.4 + puff * 0.6, 6.4)) c.set(x, y, 6);
  const mk = (x, y) => { c.set(x - 1, y, 6); c.set(x, y + 1, 6); c.set(x + 1, y, 6); };
  mk(bx - 2, by + 2); mk(bx + 2, by + 2); mk(bx, by + 5); mk(bx, by + 8);

  // feet
  const tap = waiting && Math.sin(t * 7) > 0 ? -2 : 0;
  c.rect(bx - 5, by + 11, 4, 1, 9); c.rect(bx + 1, by + 11 + tap, 4, 1, 9);
  [bx - 5, bx - 3].forEach(x => c.set(x, by + 12, 10)); [bx + 1, bx + 3].forEach(x => c.set(x, by + 12 + tap, 10));
  c.rect(bx - 6, by + 11, 1, 1, ink); c.rect(bx + 5, by + 11, 1, 1, ink);

  // eyes: big rings
  const ey = by - 5, exL = bx - 4.2, exR = bx + 4.2;
  const ringR = 4.1;
  const ring = (cx) => {
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      if (c.inEllipse(x, y, cx, ey, ringR, ringR)) c.set(x, y, 7);
      else if (c.inEllipse(x, y, cx, ey, ringR + 1, ringR + 1)) c.set(x, y, 3);
    }
  };
  ring(exL); ring(exR);
  const lid = (mood === 'calm' && blinkAt(t, 4.2, 0.16)) || (waiting && blinkAt(t, 2.8, 0.14)) || false;
  const look = waiting ? (Math.sin(t * 1.2) > 0 ? 1 : 0) : mood === 'calm' ? (Math.sin(t * 1.9) > 0.45 ? 1 : Math.sin(t * 1.9) < -0.45 ? -1 : 0) : 0;
  const eye = (cx, side) => {
    const ix = Math.round(cx), iy = Math.round(ey);
    if (done) { // happy arcs
      for (let k = -2; k <= 2; k++) c.set(ix + k, iy + (Math.abs(k) === 2 ? 1 : Math.abs(k) === 1 ? 0 : -1) + 1, ink);
      return;
    }
    if (lid) { c.rect(ix - 3, iy, 6, 1, ink); c.rect(ix - 3, iy - 3, 6, 3, 2); c.set(ix - 3, iy - 3, 3); c.set(ix + 2, iy - 3, 3); return; }
    const r = annoyed || angry ? 1.9 : mood === 'calm' ? 2.2 : 2.7;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.inEllipse(x, y, cx + look * 0.8, ey + (angry ? 0.5 : 0), r, r)) c.set(x, y, 8);
    const px = Math.round(cx + look * 0.8) - 1, py = Math.round(ey + (angry ? 0.5 : 0)) - 1;
    c.rect(px, py, 2, 2, ink); c.set(px, py, 16);                                   // pupil + glint
    if (angry) { c.set(px + 1, py + 1, 14); }
    if (annoyed) { // flat lid over the top, pupil still showing underneath, brow slanting down at the inner corner
      c.rect(ix - 4, iy - 4, 9, 3, 2); for (let k = -3; k <= 3; k++) c.set(ix + k, iy - 1, ink); c.set(ix - 4, iy - 2, 3); c.set(ix + 4, iy - 2, 3);
      c.set(ix - side * 3, iy - 5, ink); c.set(ix - side * 2, iy - 4, ink);
      c.rect(px, py + 1, 2, 2, ink); c.set(px, py + 1, 16);
    }
    if (angry) { // thick slanted brows, low on the inside
      const ox = Math.round(cx) + side * 4, oyb = Math.round(ey) - 6, ix2 = Math.round(cx) - side * 3, iyb = Math.round(ey) - 3;
      c.line(ox, oyb, ix2, iyb, ink); c.line(ox, oyb + 1, ix2, iyb + 1, ink); c.line(ox, oyb + 2, ix2, iyb + 2, 3);
    }
  };
  eye(exL, -1); eye(exR, 1);

  if (waiting) { // eyebrows up, listening
    for (const cx2 of [exL, exR]) { const ix = Math.round(cx2), iy = Math.round(ey) - 6; c.set(ix - 2, iy + 1, 3); c.set(ix - 1, iy, 3); c.set(ix, iy, 3); c.set(ix + 1, iy, 3); c.set(ix + 2, iy + 1, 3); }
  }

  // beak
  const kx = Math.round(bx), ky = Math.round(by - 1);
  c.rect(kx - 1, ky, 2, 2, 9); c.set(kx - 1, ky + 2, 10); c.set(kx, ky + 2, 10); c.set(kx - 2, ky, ink); c.set(kx + 1, ky, ink); c.set(kx - 2, ky + 1, ink); c.set(kx + 1, ky + 1, ink); c.set(kx - 1, ky + 3, ink); c.set(kx, ky + 3, ink);
  if (done) { c.rect(kx - 1, ky + 2, 2, 1, 14); }
  // cheeks
  const cc = done || mood === 'calm' || waiting ? 11 : angry ? 14 : 0;
  if (cc) { c.rect(bx - 9, by + 0, 2, 1, cc); c.rect(bx + 7, by + 0, 2, 1, cc); }

  // extras
  if (annoyed) { c.sweat(bx + 10, by - 14 + (Math.sin(t * 2) > 0 ? 1 : 0), 12, 16); c.glyph('?', 1, 1, 13); }
  if (angry) { c.glyph('!', 1, 1 + (Math.floor(t * 8) % 2), 14); c.glyph('!', 5, 1 + (Math.floor(t * 8 + 1) % 2), 14); const s = Math.floor(t * 6) % 2; c.puff(bx + 8, 5 - s, 15); c.puff(2, 9 - s, 15); }
  if (done) { const k = Math.floor(t * 6); [[3, 8], [28, 9], [4, 20], [28, 21], [24, 6]].forEach(([x, y], i) => { if ((k + i) % 3 !== 0) c.plus(x, y + ((k + i) % 2), 13); }); }
  return { px: c.px, pal };
}

if (typeof window !== 'undefined') window.MASCOTS = { drawFirefly, drawOwl, MOODS, N };
if (typeof module !== 'undefined') module.exports = { drawFirefly, drawOwl, MOODS, N };
