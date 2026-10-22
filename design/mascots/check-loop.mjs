// Verifier for exported animations: every mood must loop seamlessly (frame at t equals frame at t + LOOP_T).
// Frames are sampled half-way between 24 fps ticks so threshold flips at exact boundaries cannot cause false alarms.
import { createRequire } from 'node:module';
const { drawOwl, MOODS, LOOP_T } = createRequire(import.meta.url)('./mascots.js');
let bad = 0;
for (const mood of MOODS) for (let k = 0; k < LOOP_T * 24; k++) {
  const t = (k + 0.37) / 24, a = drawOwl(mood, t).px, b = drawOwl(mood, t + LOOP_T).px;
  let d = 0; for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) d++;
  if (d) { bad++; console.log(`seam in ${mood} at t=${t.toFixed(3)} (${d} pixels differ)`); break; }
}
console.log(bad ? `${bad} mood(s) do not loop` : `all ${MOODS.length} moods loop seamlessly over ${LOOP_T}s`);
process.exit(bad ? 1 : 0);
