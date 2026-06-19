/*
 * Regenerate the README/docs screenshots from the LIVE dashboard.
 *
 * Prereqs: the dashboard is running (bin/dashboard.sh start) with a few lanes in
 * useful states, and Playwright (chromium) is installed — it ships with the lane
 * frontends, so point NODE_PATH at one of them:
 *
 *   NODE_PATH="$HOME/clinical/lane1/frontend/node_modules" \
 *     node docs/screenshots/regenerate.cjs
 *
 * Optional env: DASH_URL (default http://127.0.0.1:8090).
 *
 * Lane assumptions (adjust the numbers below if your lanes differ): a ship lane
 * mid-pipeline (map), a done ship lane with QC proof (gallery), and a pr-review
 * lane (review history). Each shot is best-effort — a missing lane just logs FAIL.
 */
const path = require('path');
let chromium;
for (const m of ['playwright', '@playwright/test', 'playwright-core']) {
  try { ({ chromium } = require(m)); if (chromium) break; } catch { /* try next */ }
}
if (!chromium) { console.error('Playwright not found — run with NODE_PATH=<lane>/frontend/node_modules'); process.exit(2); }

const OUT = __dirname;
const URL = process.env.DASH_URL || 'http://127.0.0.1:8090';
const MAP_LANE = 1, PROOF_LANE = 3, REVIEW_LANE = 4;   // edit to match your lanes
const log = (...a) => console.log('  ', ...a);

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, deviceScaleFactor: 1 });

  async function selectLane(n) {
    await page.locator('.card', { hasText: new RegExp(`lane ${n}\\b`, 'i') }).first().click();
    await page.waitForTimeout(900);
    await page.evaluate(() => window.scrollTo(0, 0)); // clicking a lower card scrolls the page
    await page.waitForTimeout(200);
  }
  async function elShot(name, sel, nth = 0) {
    try { await page.locator(sel).nth(nth).screenshot({ path: path.join(OUT, name) }); log('wrote', name); }
    catch (e) { log('FAIL', name, e.message.split('\n')[0]); }
  }
  async function clipShot(name, clip) {
    try { await page.screenshot({ path: path.join(OUT, name), clip }); log('wrote', name); }
    catch (e) { log('FAIL', name, e.message.split('\n')[0]); }
  }

  await page.goto(URL, { waitUntil: 'networkidle' });
  await page.waitForSelector('.grid', { timeout: 10000 });
  await page.waitForTimeout(1200);

  const hb = await page.evaluate(() => Math.round(document.querySelector('header').getBoundingClientRect().bottom + 10));
  await clipShot('08-top-bar.png', { x: 0, y: 0, width: 1400, height: hb });

  await selectLane(MAP_LANE);
  await clipShot('01-dashboard-overview.png', { x: 0, y: 0, width: 1400, height: 900 });
  await elShot('02-pipeline-map.png', '.mapwrap', 0);

  await selectLane(PROOF_LANE);
  await page.waitForTimeout(600);
  await elShot('03-proof-gallery.png', '.mapwrap', 1);

  await elShot('04-lane-cards.png', '.grid', 0);
  try { await page.locator('.card', { hasText: new RegExp(`lane 2\\b`, 'i') }).first().screenshot({ path: path.join(OUT, '06-lane-card-detail.png') }); log('wrote 06-lane-card-detail.png'); }
  catch (e) { log('FAIL 06', e.message.split('\n')[0]); }

  await selectLane(REVIEW_LANE);
  await page.waitForTimeout(600);
  const mw = await page.locator('.mapwrap').first().boundingBox().catch(() => null);
  if (mw) {
    const y = Math.round(mw.y);
    const h = Math.max(120, Math.min(Math.round(mw.height), 900 - y - 12)); // cap to the visible viewport
    await clipShot('05-lane-review-mode.png', { x: Math.round(mw.x), y, width: Math.round(mw.width), height: h });
  } else await elShot('05-lane-review-mode.png', '.mapwrap', 0);

  try { await page.screenshot({ path: path.join(OUT, '07-full-page.png'), fullPage: true }); log('wrote 07-full-page.png'); }
  catch (e) { log('FAIL 07', e.message.split('\n')[0]); }

  await browser.close();
  console.log('DONE');
})().catch(e => { console.error('FATAL', e.stack || e); process.exit(1); });
