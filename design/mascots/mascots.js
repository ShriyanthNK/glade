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
const FIREFLY_GLOW = { calm: '#d4f55e', waiting: '#ffe45c', annoyed: '#ffa83a', angry: '#ff5a3c', done: '#fff2a8' };

Canvas32.prototype.inRot = function (x, y, cx, cy, rx, ry, deg) {
  const a = deg * Math.PI / 180, dx = x + 0.5 - cx, dy = y + 0.5 - cy;
  const u = dx * Math.cos(a) + dy * Math.sin(a), v = -dx * Math.sin(a) + dy * Math.cos(a);
  return (u / rx) * (u / rx) + (v / ry) * (v / ry) <= 1;
};

function drawFirefly(mood, t) {
  const c = new Canvas32();
  const glow = FIREFLY_GLOW[mood];
  const rate = { calm: 1.5, waiting: 3.4, annoyed: 6, angry: 10, done: 5 }[mood];
  const pulse = 0.5 + 0.5 * Math.sin(t * rate);                 // 0..1, how bright the lamp is right now
  const done = mood === 'done', angry = mood === 'angry', annoyed = mood === 'annoyed', waiting = mood === 'waiting';
  const lamp = mix('#7a6a3a', glow, done ? 1 : 0.4 + 0.6 * pulse);   // dim -> full glow
  const pal = [
    null, '#3d2236',                                   // 1 ink
    '#5b8c97', '#9fd0d6', '#3d6671',                   // 2 head/thorax, 3 hi, 4 dk
    '#e6f6ff', '#a9cfe6',                              // 5 wing, 6 wing shade
    lamp, mix(lamp, '#ffffff', 0.6), mix(lamp, '#8a3a1a', 0.5),   // 7 lamp, 8 lamp hi, 9 lamp dk
    '#ffffff', '#ff8fa3', '#6ec6ff', '#ffd23f', '#ff5a3c', '#b8c6d4', // 10 white, 11 cheek, 12 sweat, 13 gold, 14 red, 15 puff
    '#ff8a4c', '#c4532c',                              // 16 collar, 17 collar dk
    mix(glow, '#2a1a26', 0.25),                        // 18 halo tone
  ];
  const ink = 1;
  const bob = done ? -Math.round(Math.abs(Math.sin(t * 5)) * 3) : angry ? (Math.floor(t * 16) % 2) : Math.round(Math.sin(t * 2.4) * 1.2);
  const oy = bob, cx = 16;
  const headY = 12 + oy, absY = 24 + oy;

  // ---- halo (painted last into empty cells): a thin dithered glow hugging the lamp, bigger when brighter
  const haloR = (done ? 3.4 : 1.2 + 1.8 * pulse) + (angry ? 0.6 : 0);
  const haloCells = [];
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if (y < absY - 3) continue;
    const e = Math.hypot((x + 0.5 - cx) / 9.2, (y + 0.5 - absY) / 8.4) - 1;       // 0 at the lamp's outline
    const d = e * 8.6;
    if (d > 0 && d < haloR && ((x + y) % 2 === 0) && (d < haloR * 0.5 || (x + 2 * y) % 4 === 0)) haloCells.push([x, y, d < haloR * 0.5 ? 7 : 18]);
  }

  // ---- wings (behind body): slim, tilted outward, translucent
  const flap = Math.sin(t * (angry ? 46 : done ? 24 : mood === 'calm' ? 9 : 15)) > 0;
  for (const side of [-1, 1]) {
    const tilt = side * ((done ? 38 : 24) + (flap ? 4 : -2));
    const wcx = cx + side * (done ? 11.2 : 10), wcy = 14.2 + oy - (done ? 1.5 : 0);
    const ry = done ? 9.2 : 7.8, rx = 3.1;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      if (c.inRot(x, y, wcx, wcy, rx, ry, tilt)) c.set(x, y, 5);
      else if (c.inRot(x, y, wcx, wcy, rx + 1, ry + 1, tilt)) c.set(x, y, ink);
    }
    // shading along the lower edge + a vein
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 5 && !c.inRot(x, y, wcx - side * 0.8, wcy - 0.8, rx - 0.7, ry - 0.9, tilt)) c.set(x, y, 6);
    for (let k = 0; k < 5; k++) c.set(Math.round(wcx + side * (k * 0.35 - 0.6) - side * Math.sin(Math.abs(tilt) * Math.PI / 180) * (k - 2) * 0.1), Math.round(wcy - 4 + k * 1.6), 10);
  }

  // ---- abdomen: the lamp
  const lrx = 8.2, lry = 7.4;
  c.blob(cx, absY, lrx, lry, 7, ink);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 7) {
    const dx = (x + 0.5 - cx) / lrx, dy = (y + 0.5 - absY) / lry;
    if (dx * 0.6 + dy * 0.8 > 0.58) c.set(x, y, 9);                              // shaded lower right
    else if (c.inEllipse(x, y, cx - 2.6, absY - 1.6, 3.4, 2.6)) c.set(x, y, 8);  // bright core top left
  }
  // segment lines
  for (const sy of [absY + 1, absY + 4]) for (let x = 0; x < N; x++) if (c.get(x, Math.round(sy)) === 9 || c.get(x, Math.round(sy)) === 7) if (Math.abs(x + 0.5 - cx) < lrx - 1.2 - (sy > absY + 3 ? 1.5 : 0)) c.set(x, Math.round(sy), 9);
  c.rect(Math.round(cx - 5), Math.round(absY - 3), 2, 1, 10);                   // glint

  // ---- collar (the orange shield real fireflies have) + head
  c.ellipse(cx, 19.2 + oy, 6.2, 2.4, ink); c.ellipse(cx, 19 + oy, 5.4, 1.7, 16);
  c.set(cx - 2, 19 + oy, 17); c.set(cx + 1, 19 + oy, 17); c.rect(cx - 1, 20 + oy, 2, 1, 17);
  c.blob(cx, headY, 6.8, 6.3, 2, ink);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (c.get(x, y) === 2) {
    const dx = (x + 0.5 - cx) / 6.8, dy = (y + 0.5 - headY) / 6.3;
    if (dx * 0.6 + dy * 0.8 > 0.55) c.set(x, y, 4);
  }
  c.rect(cx - 4, headY - 5, 3, 1, 3); c.rect(cx - 5, headY - 4, 2, 1, 3);

  // ---- antennae with glowing tips
  const sway = Math.sin(t * 2.6) > 0.25 ? 1 : 0;
  const back = angry ? 2 : 0;
  c.line(cx - 3, headY - 6, cx - 6 - sway - back, 4 + oy + back, ink); c.line(cx + 3, headY - 6, cx + 6 + sway + back, 4 + oy + back, ink);
  const tipL = [cx - 7 - sway - back, 2 + oy + back], tipR = [cx + 5 + sway + back, 2 + oy + back];
  [tipL, tipR].forEach(([x, y]) => { c.rect(x - 0, y, 3, 3, ink); c.set(x + 1, y + 1, pulse > 0.4 || done ? 8 : 7); c.set(x + 1, y, 7); c.set(x, y + 1, 7); });

  // ---- face: big white eyes read against the dark head
  const ey = headY - 3;
  const lookX = waiting ? (Math.sin(t * 1.3) > 0 ? 1 : 0) : 0;
  const blink = (mood === 'calm' && ((t % 3.6) < 0.14)) || (waiting && ((t % 2.4) < 0.13)) || (annoyed && ((t % 5) < 0.3));
  const eyeL = cx - 6, eyeR = cx + 2;
  function eyeBase(x, y, w, h) { c.rect(x - 1, y - 1, w + 2, h + 2, ink); c.rect(x, y, w, h, 10); c.set(x - 1, y - 1, 0); c.set(x + w, y - 1, 0); c.set(x - 1, y + h, 0); c.set(x + w, y + h, 0); }
  for (const x of [eyeL, eyeR]) {
    if (done) { for (const [dx, dy] of [[0, 3], [1, 2], [2, 2], [3, 3], [1, 1], [2, 1]]) c.set(x + dx, ey + dy, 10); c.set(x, ey + 4, 10); c.set(x + 3, ey + 4, 10); }
    else if (blink) { c.rect(x, ey + 3, 4, 1, ink); }
    else if (annoyed) { eyeBase(x, ey + 1, 4, 4); c.rect(x, ey + 1, 4, 2, 4); c.rect(x + 1, ey + 3, 2, 2, ink); c.set(x + 2, ey + 3, 10); c.rect(x, ey + 3, 4, 0, 4); }
    else if (angry) { eyeBase(x, ey + 2, 4, 3); c.rect(x + 1, ey + 3, 2, 2, 14); c.set(x + 1, ey + 3, 10); }
    else { const h = waiting ? 5 : 4; eyeBase(x, ey, 4, h); c.rect(x + 1 + lookX, ey + 1, 2, 2, ink); c.set(x + 2 + lookX, ey + 1, 10); }
  }
  if (angry) { c.line(eyeL - 1, ey - 1, eyeL + 4, ey + 1, ink); c.line(eyeL - 1, ey, eyeL + 4, ey + 2, ink); c.line(eyeR + 4, ey - 1, eyeR - 1, ey + 1, ink); c.line(eyeR + 4, ey, eyeR - 1, ey + 2, ink); }
  const cheek = done || mood === 'calm' || waiting ? 11 : angry ? 14 : 0;
  if (cheek) { c.rect(cx - 6, ey + 6, 2, 1, cheek); c.rect(cx + 4, ey + 6, 2, 1, cheek); }
  const my = ey + 6;
  if (done) { c.rect(cx - 2, my, 4, 1, ink); c.rect(cx - 1, my + 1, 2, 1, 14); }
  else if (angry) { c.set(cx - 1, my + 1, ink); c.set(cx, my + 1, ink); c.set(cx - 2, my + 2, ink); c.set(cx + 1, my + 2, ink); }
  else if (annoyed) { c.rect(cx - 1, my + 1, 3, 1, ink); }
  else { c.set(cx - 1, my, ink); c.set(cx, my + 1, ink); c.set(cx + 1, my, ink); }

  // legs
  c.rect(cx - 4, 31 > absY + 7 ? absY + 7 : 30, 0, 0, ink);

  // ---- paint halo last, only into empty cells
  haloCells.forEach(([x, y, col]) => { if (c.get(x, y) === 0) c.set(x, y, col); });

  // ---- extras
  if (annoyed) { c.sweat(cx + 8, 4 + oy + (Math.sin(t * 2) > 0 ? 1 : 0), 12, 10); c.glyph('?', 1, 1, 13); }
  if (angry) { c.glyph('!', 1, 1 + (Math.floor(t * 8) % 2), 14); c.glyph('!', 5, 1 + (Math.floor(t * 8 + 1) % 2), 14); const s = Math.floor(t * 6) % 2; c.puff(24, 2 - s, 15); c.puff(2, 9 - s, 15); }
  if (done) { const k = Math.floor(t * 6); [[3, 3], [28, 5], [3, 19], [28, 17], [15, 0], [25, 10], [8, 26]].forEach(([x, y], i) => { if ((k + i) % 3 !== 0) c.plus(x, y + ((k + i) % 2), 13); }); }
  if (mood === 'calm' || waiting) { [[3, 5, 0], [28, 8, 1.7], [4, 24, 3.1], [27, 27, 4.6]].forEach(([x, y, ph]) => { if (Math.sin(t * 2 + ph) > 0.1) c.set(x, y + Math.round(Math.sin(t + ph)), 18); }); }
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
  const bob = done ? -Math.round(Math.abs(Math.sin(t * 5)) * 3) : angry ? 0 : (Math.sin(t * 2) > 0.5 ? -1 : 0);
  const oy = bob, puff = angry ? 1 : 0;
  const lean = waiting ? (Math.sin(t * 1.5) > 0 ? 1 : 0) : 0;

  // ear tufts
  const tuft = (side) => {
    const cx = 16 + side * 7.5;
    c.poly([[cx - side * 3.5, 10 + oy], [cx + side * (done ? 2.5 : 0.5), 2 + oy - (angry ? 1 : 0) + (annoyed ? 1 : 0)], [cx + side * 3, 10 + oy]], 2);
    // outline the tuft
    const keep = c.px.slice();
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (keep[y * N + x] === 0 && (keep[(y) * N + x + 1] === 2 || keep[(y) * N + x - 1] === 2 || keep[(y + 1) * N + x] === 2 || keep[(y - 1) * N + x] === 2)) c.set(x, y, ink);
  };
  tuft(-1); tuft(1);

  // wings behind
  const wy = done ? 16 : 21;
  for (const side of [-1, 1]) {
    const cx = 16 + side * (done ? 11.2 : 11 + puff * 0.8), cy = wy + oy;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const lean2 = (y - cy) * 0.2 * side * (done ? -1.3 : 1);
      if (c.inEllipse(x - lean2, y, cx, cy, 3.6, done ? 8.2 : 7.2)) c.set(x, y, 3);
      else if (c.inEllipse(x - lean2, y, cx, cy, 4.6, done ? 9.2 : 8.2)) c.set(x, y, ink);
    }
  }

  // body
  const bx = 16 + lean, by = 19 + oy;
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
  mk(bx - 2, by + 1); mk(bx + 2, by + 1); mk(bx, by + 4); mk(bx - 3, by + 6); mk(bx + 3, by + 6); mk(bx, by + 8);

  // feet
  const tap = waiting && Math.sin(t * 7) > 0 ? -1 : 0;
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
  const lid = (mood === 'calm' && blinkAt(t, 4.2, 0.16)) || (waiting && blinkAt(t, 2.8, 0.14)) || (annoyed && blinkAt(t, 5.5, 0.35));
  const look = waiting ? (Math.sin(t * 1.2) > 0 ? 1 : 0) : mood === 'calm' ? (Math.sin(t * 0.7) > 0.5 ? 1 : 0) : 0;
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
    if (annoyed) { c.rect(ix - 4, iy - 4, 9, 4, 2); c.rect(ix - 4, iy, 9, 0, 2); for (let k = -3; k <= 3; k++) c.set(ix + k, iy, ink); c.set(ix - 4, iy - 1, 3); c.set(ix + 4, iy - 1, 3); }
    if (angry) { // thick slanted brows, low on the inside
      const ox = Math.round(cx) + side * 4, oyb = Math.round(ey) - 6, ix2 = Math.round(cx) - side * 3, iyb = Math.round(ey) - 3;
      c.line(ox, oyb, ix2, iyb, ink); c.line(ox, oyb + 1, ix2, iyb + 1, ink); c.line(ox, oyb + 2, ix2, iyb + 2, 3);
    }
  };
  eye(exL, -1); eye(exR, 1);
  if (mood === 'calm') { // relaxed: a soft lid across the top of each ring
    for (const cx2 of [exL, exR]) { const ix = Math.round(cx2); c.rect(ix - 3, Math.round(ey) - 3, 6, 1, 2); c.set(ix - 4, Math.round(ey) - 3, 3); c.set(ix + 3, Math.round(ey) - 3, 3); }
  }
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
  if (angry) { c.glyph('!', 1, 1 + (Math.floor(t * 8) % 2), 14); c.glyph('!', 5, 1 + (Math.floor(t * 8 + 1) % 2), 14); const s = Math.floor(t * 6) % 2; c.puff(bx + 9, 3 - s, 15); c.puff(1, 7 - s, 15); }
  if (done) { const k = Math.floor(t * 6); [[3, 5], [28, 7], [4, 18], [28, 19], [15, 0], [24, 3]].forEach(([x, y], i) => { if ((k + i) % 3 !== 0) c.plus(x, y + ((k + i) % 2), 13); }); }
  return { px: c.px, pal };
}

if (typeof window !== 'undefined') window.MASCOTS = { drawFirefly, drawOwl, MOODS, N };
if (typeof module !== 'undefined') module.exports = { drawFirefly, drawOwl, MOODS, N };
