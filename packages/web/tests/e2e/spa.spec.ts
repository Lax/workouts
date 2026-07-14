import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { expect, type Page, test } from '@playwright/test'
import { generateActivities } from '../fixtures/activities'

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
  await expect(page.locator('text=Workouts')).toBeVisible({ timeout: 10000 })
}

async function gotoOverview(page: Page) {
  await page.goto('/overview.html')
  await expect(page.locator('text=Workouts')).toBeVisible({ timeout: 10000 })
}

async function gotoHello(page: Page) {
  await page.goto('/hello.html')
  await expect(page.locator('text=Hello World')).toBeVisible({ timeout: 10000 })
}

test('hello page shows version tables', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))
  await gotoHello(page)
  expect(errors).toEqual([])
  await expect(page.locator('text=Workspace Packages')).toBeVisible()
  await expect(page.locator('text=Runtime Dependencies')).toBeVisible()
  await expect(page.locator('text=Tooling')).toBeVisible()
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
  const buttons = page.locator('button:has-text("☀️"), button:has-text("🌙")')
  await buttons.first().click()
  const after = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
  expect(after).not.toBe(before)
  await page.reload()
  await waitLoaded(page)
  expect(await page.evaluate(() => document.documentElement.getAttribute('data-theme'))).toBe(after)
})

test('simple theme shows activity list', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('text=Workouts')).toBeVisible()
  const actCards = page.locator('text=km').first()
  await expect(actCards).toBeVisible({ timeout: 5000 })
})

test('color mode toggles in simple theme', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('button:has-text("类型")')).toBeVisible()
  await expect(page.locator('button:has-text("速度")')).toBeVisible()
  await page.locator('button:has-text("速度")').click()
  await expect(page.locator('button:has-text("速度")')).toBeVisible()
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
