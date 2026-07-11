import { chromium } from 'playwright'
const b = await chromium.launch()

async function analyze(p, label) {
  await p.waitForTimeout(2000)
  const info = await p.evaluate(() => {
    const r = s => { const el = document.querySelector(s); if(!el) return null; const b = el.getBoundingClientRect(); return {x:+b.x.toFixed(1),y:+b.y.toFixed(1),w:+b.width.toFixed(1),h:+b.height.toFixed(1)} }
    const pills = document.querySelectorAll('.year-pill')
    return {
      vp: { w: document.documentElement.clientWidth, h: document.documentElement.clientHeight },
      yearPills: Array.from(pills).map(p => ({ text: p.textContent, active: p.classList.contains('active'), rect: p.getBoundingClientRect() })),
      legendBtns: Array.from(document.querySelectorAll('.legend-btn')).map(b => ({ text: b.textContent, active: b.classList.contains('active') })),
      drawerOpen: document.querySelector('.drawer.open') !== null,
      handleText: document.querySelector('.handle')?.innerText?.substring(0, 80),
    }
  })
  console.log(`\n=== ${label} ===`)
  console.log(JSON.stringify(info, null, 2))
}

// Desktop
const pd = await b.newPage({ viewport: { width: 1440, height: 900 } })
pd.on('pageerror', err => console.error('Desktop error:', err.message))
await pd.goto('https://liulantao.com/workouts/index-svelte.html', { waitUntil: 'networkidle', timeout: 15000 })
await analyze(pd, 'DESKTOP 1440×900')

// Try clicking year pill
await pd.locator('.year-pill').nth(1).click()
await pd.waitForTimeout(500)
const clickResult = await pd.evaluate(() => {
  const active = document.querySelector('.year-pill.active')
  return { activeYear: active?.textContent || null, drawerOpen: document.querySelector('.drawer.open') !== null }
})
console.log('After year pill click:', JSON.stringify(clickResult))

// Try clicking legend button
await pd.locator('.legend-btn').nth(1).click()
await pd.waitForTimeout(300)
const legendResult = await pd.evaluate(() => {
  const btns = Array.from(document.querySelectorAll('.legend-btn'))
  return btns.map(b => ({ text: b.textContent, active: b.classList.contains('active') }))
})
console.log('After legend click:', JSON.stringify(legendResult))

// Mobile
const pm = await b.newPage({ viewport: { width: 375, height: 812 } })
pm.on('pageerror', err => console.error('Mobile error:', err.message))
await pm.goto('https://liulantao.com/workouts/index-svelte.html', { waitUntil: 'networkidle', timeout: 15000 })
await analyze(pm, 'MOBILE 375×812')

await pd.close()
await pm.close()
await b.close()
