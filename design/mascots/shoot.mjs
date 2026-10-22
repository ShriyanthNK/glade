import { createRequire } from 'node:module';
const { chromium } = createRequire('/Users/shriyanthnandakumar/glade-site/package.json')('playwright');
const [,, out, t = '0.9', w = '1280'] = process.argv;
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: +w, height: 900 }, deviceScaleFactor: 1 });
await p.goto('file://' + process.cwd() + '/preview.html?t=' + t);
await p.waitForTimeout(400);
await p.screenshot({ path: out, fullPage: true });
await b.close();
