import { chromium } from 'playwright';

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto('https://liulantao.com/workouts/simple', { waitUntil: 'networkidle', timeout: 30000 });
await page.waitForSelector('.layout', { timeout: 10000 });
await page.waitForTimeout(5000);

const z = await page.evaluate(() => {
  const wrapper = document.querySelector('.map-wrapper');
  if (!wrapper) return [];
  const results = [];
  const all = wrapper.querySelectorAll('*');
  for (const el of all) {
    const cs = getComputedStyle(el);
    const zIdx = cs.zIndex;
    const pos = cs.position;
    if (zIdx !== 'auto' && pos !== 'static') {
      const cls = (typeof el.className === 'string') ? el.className.slice(0,40) : (el.className?.baseVal?.slice(0,40) || '');
      results.push({ tag: el.tagName, cls, zIndex: zIdx, position: pos });
    }
  }
  results.sort((a,b) => parseInt(a.zIndex) - parseInt(b.zIndex));
  return results;
});

console.log('Z-stack within map-wrapper:');
for (const item of z) {
  console.log(`  z:${item.zIndex.padStart(3)} ${item.position.padStart(10)} ${item.tag.padStart(8)} .${item.cls.slice(0,35)}`);
}

const hit = await page.evaluate(() => {
  const btn = document.querySelector('.map-lights button');
  if (!btn) return null;
  const r = btn.getBoundingClientRect();
  const cx = r.x + r.width/2, cy = r.y + r.height/2;
  const el = document.elementFromPoint(cx, cy);
  return {
    buttonRect: `${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`,
    topElTag: el?.tagName,
    topElClass: typeof el?.className === 'string' ? el.className.slice(0,50) : '',
    topElZ: el ? getComputedStyle(el).zIndex : 'N/A',
    isButton: el === btn,
    buttonBg: getComputedStyle(btn).backgroundColor,
  };
});
console.log('\nHit test:', JSON.stringify(hit, null, 2));

await browser.close();
