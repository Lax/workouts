import { chromium } from 'playwright';

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

// Fresh load - no cache
await page.goto('https://liulantao.com/workouts/simple', { 
  waitUntil: 'commit', timeout: 30000 
});

// Screenshot at increasing intervals
for (const ms of [0, 500, 1000, 2000, 3000, 5000, 8000]) {
  await new Promise(r => setTimeout(r, ms - (ms > 0 ? 500 : 0)));
  // Use clip to capture just the top-right corner (buttons area)
  await page.screenshot({ 
    path: `/tmp/simple-t${String(ms).padStart(4,'0')}ms.png`,
    clip: { x: 1140, y: 140, width: 120, height: 140 }
  });
}

// Also check what changed between t0 and t8s
const diff = await page.evaluate(() => {
  // At 8s, check final state
  const lights = document.querySelector('.map-lights button');
  const fs = document.querySelector('.map-fullscreen button');
  const leaflet = document.querySelector('.leaflet-container');
  return {
    lightsBtn: lights ? {
      tag: lights.tagName,
      text: lights.textContent?.trim(),
      display: getComputedStyle(lights).display,
      bg: getComputedStyle(lights).backgroundColor,
      opacity: getComputedStyle(lights).opacity,
      rect: lights.getBoundingClientRect(),
    } : null,
    fsBtn: fs ? {
      tag: fs.tagName,
      text: fs.textContent?.trim(),
      display: getComputedStyle(fs).display,
      bg: getComputedStyle(fs).backgroundColor,
      rect: fs.getBoundingClientRect(),
    } : null,
    mapTilesLoaded: document.querySelectorAll('.leaflet-tile-loaded').length,
    anyOverlay: document.querySelectorAll('.leaflet-overlay-pane path').length,
  };
});

console.log('8s FINAL STATE:');
console.log(JSON.stringify(diff, null, 2));

await browser.close();
