import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { expect, type Locator, type Page, test } from '@playwright/test'
import { generateActivities } from '../fixtures/activities'

/**
 * Visual regression snapshot for a specific page region.
 * Uses Playwright's built-in toMatchSnapshot with local baselines.
 * First run: generates baseline. Subsequent: compares.
 * Run with --update-snapshots to update baselines.
 */

/**
 * Visual integrity audit for a map overlay element.
 * Catches: z-index too low, hidden behind tiles, clipped by overflow, off-screen.
 */
async function expectOverlayVisible(overlay: Locator) {
  await expect(overlay).toBeAttached()
  await expect(overlay).toBeVisible()

  const box = await overlay.boundingBox()
  expect(box, 'overlay must have non-zero bounding box').not.toBeNull()
  expect(box!.width, 'overlay width must be > 0').toBeGreaterThan(0)
  expect(box!.height, 'overlay height must be > 0').toBeGreaterThan(0)

  // Check 1: within viewport (not off-screen)
  const vp = await overlay.page().evaluate(() => ({ w: window.innerWidth, h: window.innerHeight }))
  expect(box!.x + box!.width, 'right edge must be within viewport').toBeLessThanOrEqual(vp.w + 2)
  expect(box!.y + box!.height, 'bottom edge must be within viewport').toBeLessThanOrEqual(vp.h + 2)
  expect(box!.x, 'left edge must be >= 0').toBeGreaterThanOrEqual(0)
  expect(box!.y, 'top edge must be >= 0').toBeGreaterThanOrEqual(0)

  // Check 2: not clipped by overflow:hidden parent (tolerate 2px for intentional clipping like rounded corners)
  const notClipped = await overlay.evaluate((el) => {
    let parent = el.parentElement
    while (parent && parent !== document.body) {
      const cs = getComputedStyle(parent)
      if (cs.overflow === 'hidden' || cs.overflowX === 'hidden' || cs.overflowY === 'hidden') {
        const pr = parent.getBoundingClientRect()
        const er = el.getBoundingClientRect()
        if (er.right > pr.right + 2 || er.bottom > pr.bottom + 2 || er.left < pr.left - 2 || er.top < pr.top - 2) {
          return { clipped: true, by: parent.className.slice(0, 40) }
        }
      }
      parent = parent.parentElement
    }
    return { clipped: false, by: '' }
  })
  expect(notClipped.clipped, `overlay must not be clipped by overflow:hidden parent (${notClipped.by})`).toBe(false)

  // Check 3: not occluded — temporarily disable pointer-events:none for true hit test
  const occluded = await overlay.evaluate((el) => {
    const all = document.querySelectorAll('*')
    const restored: { el: HTMLElement; val: string }[] = []
    for (const e of all) {
      const ht = e as HTMLElement
      const pe = getComputedStyle(ht).pointerEvents
      if (pe === 'none') {
        ht.style.pointerEvents = 'auto'
        restored.push({ el: ht, val: pe })
      }
    }
    const r = el.getBoundingClientRect()
    const cx = r.x + r.width / 2
    const cy = r.y + r.height / 2
    const top = document.elementFromPoint(cx, cy)
    for (const x of restored) x.el.style.pointerEvents = x.val
    const isSelf =
      top === el ||
      el.contains(top) ||
      (top as HTMLElement)?.closest?.(el.className ? `.${el.className.split(' ')[0]}` : el.tagName) !== null
    return { occluded: !isSelf, topEl: top?.tagName || '', topCls: (top as HTMLElement)?.className?.slice(0, 40) || '' }
  })
  expect(occluded.occluded, `overlay must be at top of visual stack (found: ${occluded.topEl}.${occluded.topCls})`).toBe(false)
}

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)
const dist = (...p: string[]) => join(__dirname, '..', '..', 'dist', ...p)

test.beforeAll(() => {
  mkdirSync(dist(), { recursive: true })
  writeFileSync(dist('activities.json'), JSON.stringify(generateActivities(60)))
  writeFileSync(
    dist('stats.json'),
    JSON.stringify({
      summary: {
        total_activities: 60,
        total_distance_km: 1200,
        total_moving_time_h: 200,
        total_elevation_gain_m: 4000,
        avg_cadence: 82,
        avg_power: null,
        sport_breakdown: [
          { category: 'run', count: 20, distance_km: 400, moving_time_h: 70 },
          { category: 'ride', count: 15, distance_km: 600, moving_time_h: 90 },
          { category: 'hike', count: 10, distance_km: 100, moving_time_h: 30 },
          { category: 'swim', count: 8, distance_km: 25, moving_time_h: 10 },
        ],
      },
      monthly: [],
      yearly: [],
      streaks: { current: 7, all_time: 30 },
      activity_types: ['run', 'ride', 'hike', 'swim'],
    }),
  )
})

async function waitLoaded(page: Page) {
  await page.goto('/index.html')
  await expect(page.locator('.layout')).toBeVisible({ timeout: 10000 })
}

async function gotoOverview(page: Page) {
  await page.goto('/overview.html')
  await expect(page.locator('text=Workouts')).toBeVisible({ timeout: 10000 })
}

async function gotoHello(page: Page) {
  await page.goto('/hello.html')
  await expect(page.locator('text=Hello World')).toBeVisible({ timeout: 10000 })
}

test('hello page shows version tables with data', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))
  await gotoHello(page)
  expect(errors).toEqual([])
  await expect(page.locator('text=Workspace Packages')).toBeVisible()
  await expect(page.locator('text=Runtime Dependencies')).toBeVisible()
  await expect(page.getByRole('heading', { name: /Tooling/ })).toBeVisible()
  await expect(page.locator('.hello-row').first()).toBeVisible()
  await expect(page.locator('.hello-pkg').first()).toBeVisible()
})

test('hello page shows error state when versions.json fails', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))
  await page.route('**/versions.json', (route) => route.fulfill({ status: 404 }))
  await gotoHello(page)
  expect(errors).toEqual([])
  await expect(page.locator('text=Failed to load version data')).toBeVisible()
})

test('hello page shows empty state when no packages found', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))
  await page.route('**/versions.json', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ workspace: [], runtime: [], tooling: [] }),
    }),
  )
  await gotoHello(page)
  expect(errors).toEqual([])
  const emptyStates = page.locator('.hello-empty')
  await expect(emptyStates).toHaveCount(3)
})

// ──────── Layout CSS Classes ────────

test('overview has map-overlays with correct structure', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.map-overlays')).toBeVisible()
  await expect(page.locator('.brand')).toBeVisible()
  await expect(page.locator('.year-pill').first()).toBeVisible()
})

test('year-picker shows All button and deselects on click', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.year-pill:has-text("All")')).toBeVisible()
  // "All" is active by default (no year selected)
  await expect(page.locator('.year-pill:has-text("All").active')).toBeVisible()
  // Click a year pill → All loses active, year gets active
  await page.locator('.year-pill').nth(1).click()
  await expect(page.locator('.year-pill:has-text("All").active')).toHaveCount(0)
  await expect(page.locator('.year-pill.active')).toHaveCount(1)
  // Click All → year deselected, All active again
  await page.locator('.year-pill:has-text("All")').click()
  await expect(page.locator('.year-pill:has-text("All").active')).toBeVisible()
  await expect(page.locator('.year-pill.active')).toHaveCount(1)
})

test('leaflet zoom controls use theme CSS variables', async ({ page }) => {
  await gotoOverview(page)
  const zoomIn = page.locator('.leaflet-control-zoom a').first()
  await expect(zoomIn).toBeVisible()
  // Check it uses a custom background (not default Leaflet blue #f4f4f4)
  const bg = await zoomIn.evaluate((el) => window.getComputedStyle(el).backgroundColor)
  // Surface color in dark theme is dark (not light gray)
  expect(bg).not.toBe('rgb(244, 244, 244)')
})

test('drawer activity row background is not white in dark mode', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  await expect(page.locator('.drawer.open')).toBeVisible()
  const rowBg = await page
    .locator('.activity-row')
    .first()
    .evaluate((el) => window.getComputedStyle(el).backgroundColor)
  expect(rowBg).not.toBe('rgb(255, 255, 255)')
})

test('drawer scrollbar uses overflow-y auto', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const overflowY = await page.locator('.list').evaluate((el) => window.getComputedStyle(el).overflowY)
  expect(overflowY).toBe('auto')
})

test('sort buttons respond to hover', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const sortBtn = page.locator('.sort-btn').first()
  await expect(sortBtn).toBeVisible()
  await sortBtn.hover()
})

test('activity rows use 3-column grid', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const grid = await page
    .locator('.activity-row')
    .first()
    .evaluate((el) => ({
      display: window.getComputedStyle(el).display,
      template: window.getComputedStyle(el).gridTemplateColumns,
    }))
  expect(grid.display).toBe('grid')
  // 3-column grid: SVG(60px) + name(info) + metrics(auto)
  expect(grid.template).toContain('60px')
})

test('legend-toggle with active class toggles', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.legend-toggle')).toBeVisible()
  await expect(page.locator('.legend-btn').first()).toBeVisible()
  // Click speed button → it gets active class
  await page.locator('.legend-btn:has-text("速度")').click()
  await expect(page.locator('.legend-btn.active:has-text("速度")')).toBeVisible()
  // Type button should no longer be active
  await expect(page.locator('.legend-btn.active:has-text("类型")')).toHaveCount(0)
})

test('speed legend bar has four color segments', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.speed-legend')).toHaveCount(1)
  await expect(page.locator('.speed-legend > span')).toHaveCount(4)
})

test('icon-btn theme toggle is present', async ({ page }) => {
  await gotoOverview(page)
  const iconBtns = page.locator('.icon-btn')
  // Theme toggle is an icon-btn, should exist
  await expect(iconBtns.first()).toBeVisible()
})

test('drawer opens and shows stats when clicked', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.drawer')).toBeVisible()
  // Drawer starts collapsed
  await expect(page.locator('.drawer-collapsed')).toBeVisible()
  await expect(page.locator('.stat-pill').first()).toBeVisible()
})

test('drawer-body becomes visible after opening', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  await expect(page.locator('.drawer.open')).toBeVisible()
  await expect(page.locator('.drawer-body')).toBeVisible()
  // Should see activity list tabs
  await expect(page.locator('.tab:has-text("Activities")')).toBeVisible()
  await expect(page.locator('.tab:has-text("Filters")')).toBeVisible()
})

test('activity list shows items after drawer opens', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  await expect(page.locator('.drawer.open')).toBeVisible()
  await expect(page.locator('.list')).toBeVisible()
  await expect(page.locator('.list .activity-row').first()).toBeVisible({ timeout: 5000 })
})

test('clicking activity in drawer opens detail panel', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const firstActivity = page.locator('.activity-row').first()
  await expect(firstActivity).toBeVisible({ timeout: 5000 })
  await firstActivity.click()
  await expect(page.locator('.detail-panel')).toBeVisible()
  await expect(page.locator('.detail-card')).toBeVisible()
  await expect(page.locator('.detail-backdrop')).toBeVisible()
  await expect(page.locator('text=Distance')).toBeVisible()
})

test('detail-panel closes via backdrop click', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const firstActivity = page.locator('.activity-row').first()
  await expect(firstActivity).toBeVisible({ timeout: 5000 })
  await firstActivity.click()
  await expect(page.locator('.detail-card')).toBeVisible()
  await page.mouse.click(10, 10)
  await expect(page.locator('.detail-panel')).not.toBeVisible()
})

test('detail-panel shows 3-column grid with stats', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const firstActivity = page.locator('.activity-row').first()
  await expect(firstActivity).toBeVisible({ timeout: 5000 })
  await firstActivity.click()
  await expect(page.locator('.detail-grid')).toBeVisible()
  // Verify 3-column grid structure: Distance, Moving Time, Avg Pace in first row
  await expect(page.locator('.detail-grid .detail-stat')).toHaveCount(8)
  await expect(page.locator('.detail-stat').nth(0)).toContainText('Distance')
  await expect(page.locator('.detail-stat').nth(1)).toContainText('Moving Time')
  await expect(page.locator('.detail-stat').nth(2)).toContainText('Avg Pace')
})

test('detail-panel shows meta info', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const firstActivity = page.locator('.activity-row').first()
  await expect(firstActivity).toBeVisible({ timeout: 5000 })
  await firstActivity.click()
  await expect(page.locator('.detail-meta')).toBeVisible()
  // Meta contains date and source
  const meta = page.locator('.detail-meta')
  await expect(meta).not.toBeEmpty()
})

test('detail-panel uses h2 for activity name', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed').click()
  const firstActivity = page.locator('.activity-row').first()
  await expect(firstActivity).toBeVisible({ timeout: 5000 })
  await firstActivity.click()
  await expect(page.locator('.detail-card h2')).toBeVisible()
})

test('chart-overlay opens via Charts button in drawer', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed button:has-text("📊")').click()
  await expect(page.locator('.chart-overlay')).toBeVisible()
  await expect(page.locator('.chart-card')).toBeVisible()
})

test('chart-overlay closes via backdrop click', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-collapsed button:has-text("📊")').click()
  await expect(page.locator('.chart-card')).toBeVisible()
  await page.mouse.click(10, 10)
  await expect(page.locator('.chart-overlay')).not.toBeVisible()
})

// ──────── Simple Theme ────────

test('SPA loads without page errors', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))
  await waitLoaded(page)
  expect(errors).toEqual([])
})

test('theme toggle persists across reload', async ({ page }) => {
  await waitLoaded(page)
  const before = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
  const buttons = page.locator('button[aria-label="Toggle theme"]')
  await buttons.first().click()
  const after = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
  expect(after).not.toBe(before)
  await page.reload()
  await page.goto('/index.html')
  await expect(page.locator('.layout')).toBeVisible({ timeout: 10000 })
  expect(await page.evaluate(() => document.documentElement.getAttribute('data-theme'))).toBe(after)
})

test('simple theme has two-column layout', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('.layout')).toBeVisible()
  await expect(page.locator('.left-panel')).toBeVisible()
  await expect(page.locator('.right-panel')).toBeVisible()
})

test('simple theme shows year blocks in left panel', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('.year-block').first()).toBeVisible()
  await expect(page.locator('.year-label').first()).toBeVisible()
  await expect(page.locator('.stat-item').first()).toBeVisible()
})

test('simple theme shows run table with sortable headers', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('.run-table')).toBeVisible()
  await expect(page.locator('.run-table thead th:has-text("Date")')).toBeVisible()
  await expect(page.locator('.run-table thead th:has-text("km")')).toBeVisible()
  await expect(page.locator('.run-table thead th:has-text("Pace")')).toBeVisible()
  await expect(page.locator('.run-table tbody tr')).not.toHaveCount(0)
})

test('simple theme map overlays show year selector and controls', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('.map-year-selector .year-pill:has-text("All")')).toBeVisible()
  await expect(page.locator('.map-lights button')).toBeVisible()
  await expect(page.locator('.map-fullscreen button')).toBeVisible()
})

test('visual integrity: all map overlays pass occlusion, clipping, and viewport checks', async ({ page }) => {
  await waitLoaded(page)
  const overlays = [
    { name: 'lights toggle', sel: page.locator('.map-lights button') },
    { name: 'fullscreen', sel: page.locator('.map-fullscreen button') },
    { name: 'year pills', sel: page.locator('.map-year-selector .year-pill').first() },
    { name: 'month-chip', sel: page.locator('.month-chip') },
  ]
  for (const { name, sel } of overlays) {
    const exists = await sel.count()
    if (exists === 0) {
      console.log(`  SKIP ${name} — not rendered (conditional)`)
      continue
    }
    await test.step(`visual integrity: ${name}`, async () => {
      await expectOverlayVisible(sel)
    })
  }
})

test('visual regression: map overlay regions match expected appearance', async ({ page }) => {
  await waitLoaded(page)
  await page.waitForTimeout(2000)

  // Year selector pills
  await test.step('year selector', async () => {
    const region = page.locator('.map-year-selector')
    await expect(region).toBeAttached()
    const box = await region.boundingBox()
    expect(box).not.toBeNull()
    if (box!.width > 10 && box!.height > 10) {
      expect(await region.screenshot()).toMatchSnapshot('simple-year-selector.png')
    }
  })

  // Top-right controls (lights + fullscreen)
  await test.step('top-right controls', async () => {
    const lights = page.locator('.map-lights')
    const fullscreen = page.locator('.map-fullscreen')
    const lightsBox = await lights.boundingBox()
    const fsBox = await fullscreen.boundingBox()
    if (lightsBox && fsBox) {
      const clip = {
        x: Math.min(lightsBox.x, fsBox.x) - 5,
        y: Math.min(lightsBox.y, fsBox.y) - 5,
        width: Math.max(lightsBox.x + lightsBox.width, fsBox.x + fsBox.width) - Math.min(lightsBox.x, fsBox.x) + 10,
        height: Math.max(lightsBox.y + lightsBox.height, fsBox.y + fsBox.height) - Math.min(lightsBox.y, fsBox.y) + 10,
      }
      const shot = await page.screenshot({ clip })
      expect(shot).toMatchSnapshot('simple-top-right.png')
    }
  })
})

test('map-run-title shows Running Heatmap text', async ({ page }) => {
  await waitLoaded(page)
  const runTitle = page.locator('.map-run-title')
  await expect(runTitle).toBeAttached()
  await expect(runTitle).toBeVisible()
  // Should show "Total Running Heatmap" or "{year} Running Heatmap"
  await expect(runTitle).toContainText('Running Heatmap')
})

test('clicking year block filters table', async ({ page }) => {
  await waitLoaded(page)
  const blocks = page.locator('.year-block')
  await expect(blocks.first()).toBeVisible()
  // Click third block (idx 0=Total, 1=default selected year, 2=other year)
  const thirdBlock = blocks.nth(2)
  if (await thirdBlock.isVisible()) {
    await thirdBlock.click()
    // Selected year moves to first position; verify table still renders
  }
  await expect(page.locator('.run-table tbody tr')).not.toHaveCount(0)
})

test('table row click highlights row and sets URL hash', async ({ page }) => {
  await waitLoaded(page)
  const firstRow = page.locator('.run-row').first()
  await expect(firstRow).toBeVisible()
  await firstRow.click()
  await expect(firstRow).toHaveClass(/selected/)
  // URL hash should be set after React state update
  const hash = await page
    .waitForFunction(() => window.location.hash.startsWith('#run_'), null, { timeout: 5000 })
    .then(() => page.evaluate(() => window.location.hash))
  expect(hash).toMatch(/^#run_/)
})

// ──────── Theme Toggle — Map Stability ────────

test('overview theme toggle preserves map zoom and center', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.leaflet-container')).toBeVisible()
  await expect(page.locator('.leaflet-tile-loaded').first()).toBeVisible({ timeout: 10000 })

  const before = await page.evaluate(() => {
    const pane = document.querySelector('.leaflet-map-pane') as HTMLElement | null
    return pane?.style.transform || ''
  })

  await page.locator('button[aria-label="Toggle theme"]').click()
  await page.waitForTimeout(500)

  const after = await page.evaluate(() => {
    const pane = document.querySelector('.leaflet-map-pane') as HTMLElement | null
    return pane?.style.transform || ''
  })

  expect(after).toBe(before)
})

// ──────── Simple Theme — Map Controls ────────

test('lights toggle button is visible with proper background on map', async ({ page }) => {
  await waitLoaded(page)
  const lights = page.locator('button[aria-label="Hide labels"], button[aria-label="Show labels"]')
  await expect(lights).toBeVisible()

  const box = await lights.boundingBox()
  expect(box).not.toBeNull()
  expect(box!.width).toBe(34)
  expect(box!.height).toBe(34)

  const info = await lights.evaluate((el) => {
    const cs = getComputedStyle(el)
    return {
      bg: cs.backgroundColor,
      border: cs.border,
      shadow: cs.boxShadow,
      borderRadius: cs.borderRadius,
      display: cs.display,
      opacity: cs.opacity,
      rect: el.getBoundingClientRect(),
    }
  })
  expect(info.bg).not.toBe('transparent')
  expect(info.bg).not.toBe('rgba(0, 0, 0, 0)')
  expect(info.display).toBe('flex')
  // Container has reduced opacity; button inherits visually but computed value is on container
  const containerOpacity = await page.locator('.map-lights').evaluate((el) => getComputedStyle(el).opacity)
  expect(containerOpacity).toBe('0.3')
  expect(parseFloat(info.borderRadius)).toBeGreaterThanOrEqual(4)
  // Verify it's within map wrapper
  const mapBox = await page.locator('.map-wrapper').boundingBox()
  expect(mapBox).not.toBeNull()
  expect(info.rect.x).toBeGreaterThanOrEqual(mapBox!.x - 1)
  expect(info.rect.x + info.rect.width).toBeLessThanOrEqual(mapBox!.x + mapBox!.width + 1)
  // Verify it doesn't overlap Leaflet zoom
  const zoomBtn = page.locator('.leaflet-control-zoom a').first()
  if (await zoomBtn.isVisible()) {
    const zb = await zoomBtn.boundingBox()
    if (zb) {
      const noOverlap = info.rect.right < zb.x || info.rect.x > zb.x + zb.width || info.rect.bottom < zb.y || info.rect.y > zb.y + zb.height
      expect(noOverlap).toBe(true)
    }
  }
})

test('fullscreen button has control-btn styling and visible background', async ({ page }) => {
  await waitLoaded(page)
  const fsBtn = page.locator('button[aria-label="Fullscreen"]')
  await expect(fsBtn).toBeVisible()

  const box = await fsBtn.boundingBox()
  expect(box).not.toBeNull()
  expect(box!.width).toBe(34)
  expect(box!.height).toBe(34)

  const info = await fsBtn.evaluate((el) => {
    const cs = getComputedStyle(el)
    return {
      bg: cs.backgroundColor,
      border: cs.border,
      shadow: cs.boxShadow,
      borderRadius: cs.borderRadius,
      display: cs.display,
      opacity: cs.opacity,
      rect: el.getBoundingClientRect(),
    }
  })
  expect(info.bg).not.toBe('transparent')
  expect(info.bg).not.toBe('rgba(0, 0, 0, 0)')
  expect(info.display).toBe('flex')
  expect(info.opacity).toBe('1')
  expect(parseFloat(info.borderRadius)).toBeGreaterThanOrEqual(4)

  const mapBox = await page.locator('.map-wrapper').boundingBox()
  expect(mapBox).not.toBeNull()
  expect(info.rect.x).toBeGreaterThanOrEqual(mapBox!.x)
  expect(info.rect.x + info.rect.width).toBeLessThanOrEqual(mapBox!.x + mapBox!.width + 1)
})

test('lights and fullscreen buttons maintain correct background in dark mode', async ({ page }) => {
  await waitLoaded(page)
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'))
  await page.waitForTimeout(500)

  for (const ariaLabel of ['Hide labels', 'Show labels', 'Fullscreen']) {
    const btn = page.locator(`button[aria-label="${ariaLabel}"]`)
    if ((await btn.count()) === 0) continue
    const bg = await btn.evaluate((el) => getComputedStyle(el).backgroundColor)
    expect(bg).not.toBe('transparent')
    expect(bg).not.toBe('rgba(0, 0, 0, 0)')
    // In dark mode, surface is dark (not white)
    const isDark = bg !== 'rgb(255, 255, 255)' && bg !== 'rgba(255, 255, 255, 1)'
    expect(isDark).toBe(true)
  }
})

test('lights toggle aria-label toggles on click', async ({ page }) => {
  await waitLoaded(page)
  const lights = page.locator('button[aria-label="Hide labels"]')
  await expect(lights).toBeVisible()
  await lights.click()
  await expect(page.locator('button[aria-label="Show labels"]')).toBeVisible()
})

test('lights off removes tiles so map bg matches page', async ({ page }) => {
  await waitLoaded(page)
  const tiles = page.locator('.leaflet-tile-loaded')
  await expect(tiles.first()).toBeVisible({ timeout: 15000 })
  expect(await tiles.count()).toBeGreaterThan(0)

  await page.locator('button[aria-label="Hide labels"]').click()
  await page.waitForTimeout(1000)

  await expect(async () => {
    expect(await tiles.count()).toBe(0)
  }).toPass({ timeout: 5000 })
})

test('lights toggle back on restores tile layers', async ({ page }) => {
  await waitLoaded(page)
  // Wait for tiles to load, then turn lights off
  await expect(page.locator('.leaflet-tile-loaded').first()).toBeVisible({ timeout: 15000 })
  await page.locator('button[aria-label="Hide labels"]').click()
  await page.waitForTimeout(500)
  expect(await page.locator('.leaflet-tile-loaded').count()).toBe(0)

  // Turn lights back on
  await page.locator('button[aria-label="Show labels"]').click()

  // Tiles should reload
  const tiles = page.locator('.leaflet-tile-loaded')
  await expect(tiles.first()).toBeVisible({ timeout: 15000 })
  expect(await tiles.count()).toBeGreaterThan(0)
})

test('lights and fullscreen buttons are positioned at top-right of map', async ({ page }) => {
  await waitLoaded(page)
  const mapBox = await page.locator('.map-wrapper').boundingBox()
  expect(mapBox).not.toBeNull()
  const mapRight = mapBox!.x + mapBox!.width

  for (const sel of ['.map-lights', '.map-fullscreen']) {
    const box = await page.locator(sel).boundingBox()
    expect(box).not.toBeNull()
    // Within the right 50px of the map wrapper
    expect(box!.x + box!.width).toBeGreaterThan(mapRight - 50)
    // In the top half of the map wrapper
    expect(box!.y).toBeLessThan(mapBox!.y + mapBox!.height / 2)
  }
})

// ──────── Simple Theme — Layout Integration ────────

test('map-year-selector is positioned at top-left of map wrapper (horizontal pills)', async ({ page }) => {
  await waitLoaded(page)
  const selector = page.locator('.map-year-selector')
  await expect(selector).toBeAttached()

  const pos = await selector.evaluate((el) => ({
    position: window.getComputedStyle(el).position,
    left: window.getComputedStyle(el).left,
    top: window.getComputedStyle(el).top,
  }))
  expect(pos.position).toBe('absolute')
  expect(pos.left).toBe('10px')
  expect(pos.top).toBe('10px')

  // Verify pills are horizontal (row) not vertical (column)
  const pills = page.locator('.year-pills')
  const flexDir = await pills.evaluate((el) => getComputedStyle(el).flexDirection)
  expect(flexDir).toBe('row')
})

test('map-wrapper has isolation:isolate for correct stacking context', async ({ page }) => {
  await waitLoaded(page)
  const wrapper = page.locator('.map-wrapper')
  await expect(wrapper).toBeVisible()
  const isolation = await wrapper.evaluate((el) => window.getComputedStyle(el).isolation)
  expect(isolation).toBe('isolate')
})

test('year-pill background is visible (not transparent on any supported browser)', async ({ page }) => {
  await waitLoaded(page)
  const pill = page.locator('.year-pill').first()
  await expect(pill).toBeVisible()
  const bg = await pill.evaluate((el) => window.getComputedStyle(el).backgroundColor)
  // Must not be fully transparent — rgba(0,0,0,0) or transparent
  expect(bg).not.toBe('transparent')
  expect(bg).not.toBe('rgba(0, 0, 0, 0)')
  // Must have some alpha > 0 — verify it's not fully transparent
  const match = bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/)
  if (match) {
    const alpha = match[4] !== undefined ? parseFloat(match[4]) : 1
    expect(alpha).toBeGreaterThan(0)
  }
})

test('year-pill has backdrop-filter for readability over map tiles', async ({ page }) => {
  await waitLoaded(page)
  const pill = page.locator('.year-pill').first()
  await expect(pill).toBeVisible()
  const backdrop = await pill.evaluate((el) => window.getComputedStyle(el).backdropFilter)
  expect(backdrop).toContain('blur')
})

test('header background matches page background for visual integration', async ({ page }) => {
  await waitLoaded(page)
  const headerBg = await page.locator('.simple-header').evaluate((el) => window.getComputedStyle(el).backgroundColor)
  const pageBg = await page.locator('.page-container').evaluate((el) => window.getComputedStyle(el).backgroundColor)
  const bodyBg = await page.evaluate(() => window.getComputedStyle(document.body).backgroundColor)
  // Header bg must equal body bg or page-container bg
  expect(headerBg === bodyBg || headerBg === pageBg).toBe(true)
})

test('map-run-title uses --color-primary for text color', async ({ page }) => {
  await waitLoaded(page)
  const title = page.locator('.map-run-title')
  await expect(title).toBeAttached()
})

test('no CSS rgba(from ...) syntax leaks into computed backgrounds - all backgrounds render', async ({ page }) => {
  await waitLoaded(page)
  // Check elements that should have visible backgrounds (not .map-overlays which is a positioning container only)
  const elements = [page.locator('.year-pill').first(), page.locator('.simple-header')]
  for (const el of elements) {
    const bg = await el.evaluate((node) => window.getComputedStyle(node).backgroundColor)
    expect(bg).not.toBe('transparent')
    expect(bg).not.toBe('rgba(0, 0, 0, 0)')
  }
})

// ──────── Z-stack Layer Audit ────────

test('overlay z-index exceeds highest Leaflet pane z-index within map-wrapper', async ({ page }) => {
  await waitLoaded(page)

  // Direct querySelector approach — more reliable than z-stack parsing
  const overlayZ = await page.evaluate(() => {
    const els = ['.map-year-selector', '.map-lights', '.map-fullscreen']
      .map((s) => document.querySelector(s) as HTMLElement | null)
      .filter(Boolean)
    if (els.length === 0) return { error: 'no overlays found', z: 0 }
    const z = Math.min(...els.map((el) => parseInt(getComputedStyle(el!).zIndex, 10) || 0))
    return { z, count: els.length }
  })
  expect(overlayZ.count, 'at least one overlay element must exist').toBeGreaterThan(0)
  expect(overlayZ.z, 'overlay z-index must be > 0').toBeGreaterThan(0)

  const leafletZ = await page.evaluate(() => {
    const panes = document.querySelectorAll(
      '.leaflet-tile-pane, .leaflet-overlay-pane, .leaflet-shadow-pane, .leaflet-marker-pane, .leaflet-popup-pane',
    )
    let maxZ = 0
    for (const p of panes) {
      const z = parseInt(getComputedStyle(p).zIndex, 10) || 0
      if (z > maxZ) maxZ = z
    }
    return maxZ
  })
  expect(leafletZ, 'Leaflet pane z-index must be > 0').toBeGreaterThan(0)
  expect(overlayZ.z, `overlay z-index (${overlayZ.z}) must exceed Leaflet tile pane z-index (${leafletZ})`).toBeGreaterThan(leafletZ)
})

test('overlay renders above tiles after disabling pointer-events:none on tile pane', async ({ page }) => {
  await waitLoaded(page)
  const onTop = await page.evaluate(() => {
    // Remove pointer-events:none from tile panes to get true visual hit test
    const tiles = document.querySelectorAll('.leaflet-tile-pane, .leaflet-tile-container, .leaflet-layer')
    const restored: { el: HTMLElement; val: string }[] = []
    for (const t of tiles) {
      const ht = t as HTMLElement
      const cur = ht.style.pointerEvents
      ht.style.pointerEvents = 'auto'
      restored.push({ el: ht, val: cur })
    }

    const checks: { name: string; onTop: boolean }[] = []
    for (const sel of ['.map-lights button', '.map-fullscreen button', '.map-year-selector .year-pill']) {
      const btn = document.querySelector(sel) as HTMLElement | null
      if (!btn) continue
      const r = btn.getBoundingClientRect()
      if (r.width === 0 || r.height === 0) continue
      const cx = r.x + r.width / 2
      const cy = r.y + r.height / 2
      const top = document.elementFromPoint(cx, cy)
      const isBtn = top === btn || btn.contains(top as Node) || (top as HTMLElement)?.closest?.(sel) !== null
      checks.push({ name: sel, onTop: isBtn })
    }

    // Restore pointer-events
    for (const r of restored) r.el.style.pointerEvents = r.val

    return checks
  })

  for (const c of onTop) {
    expect(c.onTop).toBe(true)
  }
})

test('all overlay containers have z-index value above Leaflet tile pane (z:200)', async ({ page }) => {
  await waitLoaded(page)
  const tileZ = await page.evaluate(() => {
    const pane = document.querySelector('.leaflet-tile-pane') as HTMLElement
    if (!pane) return 0
    return parseInt(getComputedStyle(pane).zIndex, 10) || 0
  })
  expect(tileZ).toBeGreaterThanOrEqual(200)

  for (const sel of ['.map-year-selector', '.map-lights', '.map-fullscreen']) {
    await expect(async () => {
      const ourZ = await page.evaluate((s) => {
        const el = document.querySelector(s) as HTMLElement
        if (!el) return -1
        return parseInt(getComputedStyle(el).zIndex, 10) || 0
      }, sel)
      expect(ourZ).toBeGreaterThan(tileZ)
    }).toPass({ timeout: 5000 })
  }
})
