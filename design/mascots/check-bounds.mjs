// Automated check for rubric criterion 6: no sprite pixel may touch the frame edge in any mood at any time.
// Run: node check-bounds.mjs   (exits 1 on any violation)
import { createRequire } from 'node:module';
const { drawFirefly, drawOwl, MOODS, N } = createRequire(import.meta.url)('./mascots.js');
let bad = 0;
for (const [name, draw] of [['glim', drawFirefly], ['hoot', drawOwl]]) {
  for (const mood of MOODS) {
    const hits = new Set();
    for (let t = 0; t < 8; t += 0.05) {
      const { px } = draw(mood, t);
      for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (px[y * N + x] && (x === 0 || y === 0 || x === N - 1 || y === N - 1)) hits.add(`${x},${y}`);
    }
    if (hits.size) { bad++; console.log(`FAIL ${name}/${mood}: touches the frame edge at ${[...hits].slice(0, 6).join(' ')}${hits.size > 6 ? ` (+${hits.size - 6})` : ''}`); }
  }
}
console.log(bad ? `${bad} mood(s) clip` : 'no clipping in any mood or frame');
process.exit(bad ? 1 : 0);
