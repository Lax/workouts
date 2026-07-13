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
  // Brand text and year pills inside
  await expect(page.locator('.brand')).toBeVisible()
  await expect(page.locator('.year-pill').first()).toBeVisible()
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
  await expect(page.locator('.speed-legend')).toBeVisible()
  const spans = page.locator('.speed-legend > span')
  await expect(spans).toHaveCount(4)
})

test('icon-btn theme toggle is present', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.icon-btn')).toBeVisible()
})

test('year-pill active toggles on click', async ({ page }) => {
  await gotoOverview(page)
  const firstPill = page.locator('.year-pill').first()
  await expect(firstPill).toBeVisible()
  await firstPill.click()
  await expect(page.locator('.year-pill.active')).toBeVisible()
})

// ──────── Drawer ────────

test('drawer-toggle opens drawer-panel with open class', async ({ page }) => {
  await gotoOverview(page)
  await expect(page.locator('.drawer-toggle')).toBeVisible()
  // Panel starts closed (no .open class)
  await expect(page.locator('.drawer-panel.open')).toHaveCount(0)
  // Click toggle
  await page.locator('.drawer-toggle').click()
  await expect(page.locator('.drawer-panel.open')).toBeVisible()
  await expect(page.locator('text=Filters')).toBeVisible()
})

test('drawer-panel shows activity list after opening', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-toggle').click()
  await expect(page.locator('.drawer-panel.open')).toBeVisible()
  await expect(page.locator('.drawer-panel').locator('text=/Morning|Evening/').first()).toBeVisible({ timeout: 5000 })
})

// ──────── Detail Panel ────────

test('detail-panel opens with card animation', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-toggle').click()
  const activityLink = page.locator('.drawer-panel').locator('text=/Morning|Evening/').first()
  await expect(activityLink).toBeVisible({ timeout: 5000 })
  await activityLink.click()
  await expect(page.locator('.detail-panel')).toBeVisible()
  await expect(page.locator('.detail-card')).toBeVisible()
  await expect(page.locator('.detail-backdrop')).toBeVisible()
  await expect(page.locator('.close-btn')).toBeVisible()
  await expect(page.locator('text=Distance')).toBeVisible()
})

test('detail-panel closes via backdrop click', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-toggle').click()
  await page.locator('.drawer-panel').locator('text=/Morning|Evening/').first().click()
  await expect(page.locator('.detail-card')).toBeVisible()
  // Click top-left corner (backdrop area, not card)
  await page.mouse.click(10, 10)
  await expect(page.locator('.detail-panel')).not.toBeVisible()
})

// ──────── Chart Overlay ────────

test('chart-overlay opens via Charts button', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-toggle').click()
  await page.locator('button:has-text("Charts")').click()
  await expect(page.locator('.chart-overlay')).toBeVisible()
  await expect(page.locator('.chart-card')).toBeVisible()
  await expect(page.locator('.chart-backdrop')).toBeVisible()
})

test('chart-overlay closes via backdrop click', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('.drawer-toggle').click()
  await page.locator('button:has-text("Charts")').click()
  await expect(page.locator('.chart-card')).toBeVisible()
  // Click top-left corner (backdrop area)
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
