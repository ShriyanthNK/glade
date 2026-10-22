// Writes frames of Hoot (from the JS the art was reviewed in) for the Swift port to be tested against.
// Run: node design/mascots/export-fixtures.mjs   (from the repo root)
import { createRequire } from 'node:module';
import fs from 'node:fs';
const { drawOwl, MOODS } = createRequire(import.meta.url)('./mascots.js');
const frames = [];
for (const mood of MOODS) for (let k = 3; k < 144; k += 11) {
  const t = (k + 0.37) / 24;                       // half-way between 24fps ticks: no threshold flips
  const { px } = drawOwl(mood, t);
  const rows = [];
  for (let y = 0; y < 32; y++) rows.push([...px.slice(y * 32, y * 32 + 32)].map(v => v.toString(36)).join(''));
  frames.push({ mood, t, rows });
}
fs.mkdirSync('Tests/GladeCoreTests/Fixtures', { recursive: true });
fs.writeFileSync('Tests/GladeCoreTests/Fixtures/hoot-frames.json', JSON.stringify({ frames }));
console.log(`wrote ${frames.length} frames`);
