import { chromium } from 'playwright';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto('https://liulantao.com/workouts/simple', { waitUntil: 'networkidle', timeout: 30000 });
await page.waitForSelector('.layout', { timeout: 10000 });
await page.waitForTimeout(3000);
const r = await page.evaluate(() => {
  const map = document.querySelector('.map-wrapper');
  if (!map) return 'no map-wrapper';
  const all = map.querySelectorAll('*');
  const entries = [];
  for (const el of all) {
    const cs = getComputedStyle(el);
    const z = cs.zIndex;
    const p = cs.position;
    if (z !== 'auto' && (p === 'absolute' || p === 'relative')) {
      const cls = typeof el.className === 'string' ? el.className.slice(0,35) : '';
      entries.push({ z: parseInt(z), cls, tag: el.tagName });
    }
  }
  entries.sort((a,b) => a.z - b.z);
  return entries;
});
console.log('Z-stack (deployed):');
for (const e of r) {
  console.log(`  z:${String(e.z).padStart(4)} ${e.tag.padStart(8)} .${e.cls}`);
}
await browser.close();
