import { createRequire } from 'node:module';
// Playwright is not a dependency of this repo: use the one in the sibling glade-site checkout (or $PLAYWRIGHT_FROM = a package.json path).
const from = process.env.PLAYWRIGHT_FROM || new URL('../../../glade-site/package.json', import.meta.url).pathname;
const { chromium } = createRequire(from)('playwright');
const [,, out, t = '0.9', w = '1280'] = process.argv;
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: +w, height: 900 }, deviceScaleFactor: 1 });
await p.goto('file://' + process.cwd() + '/preview.html?t=' + t);
await p.waitForTimeout(400);
await p.screenshot({ path: out, fullPage: true });
await b.close();
