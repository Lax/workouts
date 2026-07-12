import { test, expect, Page } from '@playwright/test'
import { writeFileSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { generateActivities } from '../fixtures/activities'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const dist = (...p: string[]) => join(__dirname, '..', '..', 'dist', ...p)

test.beforeAll(() => {
  mkdirSync(dist(), { recursive: true })
  writeFileSync(dist('activities.json'), JSON.stringify(generateActivities(120)))
  writeFileSync(dist('stats.json'), JSON.stringify({
    summary: {
      total_activities: 120,
      total_distance_km: 2500,
      total_moving_time_h: 420,
      total_elevation_gain_m: 8500,
      avg_cadence: 82,
      avg_power: null,
      sport_breakdown: [
        { category: 'run', count: 40, distance_km: 800, moving_time_h: 140 },
        { category: 'ride', count: 30, distance_km: 1200, moving_time_h: 180 },
        { category: 'hike', count: 15, distance_km: 200, moving_time_h: 60 },
        { category: 'swim', count: 15, distance_km: 50, moving_time_h: 20 },
        { category: 'walk', count: 12, distance_km: 100, moving_time_h: 30 },
        { category: 'workout', count: 8, distance_km: 0, moving_time_h: 10 },
      ],
    },
    monthly: [
      { year: 2025, month: 1, count: 12, distance_km: 240, moving_time_h: 40, avg_pace: '5:30', avg_hr: 145, avg_cadence: 80, avg_power: null, elevation_gain_m: 800 },
    ],
    yearly: [
      { year: 2025, month: 1, count: 12, distance_km: 240, moving_time_h: 40, longest_km: 21.1, streak: 5 },
    ],
    streaks: { current: 7, all_time: 30 },
    activity_types: ['run', 'ride', 'hike', 'swim', 'walk', 'workout'],
  }))
})

async function waitLoaded(page: Page) {
  await page.goto('/index.html')
  await expect(page.locator('.brand, .rp-layout, .hello-world')).toHaveCount(1, { timeout: 10000 })
}

async function openDrawer(page: Page) {
  // On desktop (>=1024px), click collapsed strip; on mobile, click handle
  const collapsed = page.locator('.drawer-collapsed')
  if (await collapsed.isVisible()) {
    await collapsed.click()
  } else {
    await page.locator('.drawer-handle').click()
  }
  await expect(page.locator('.drawer.open')).toBeVisible()
}

test('SPA loads without page errors', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', err => errors.push(err.message))
  await waitLoaded(page)
  await expect(page.locator('.brand')).toContainText('Workouts')
  expect(errors).toEqual([])
})

test('theme toggle persists across reload', async ({ page }) => {
  await waitLoaded(page)
  const before = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
  await page.click('button[aria-label="Toggle theme"]')
  const after = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
  expect(after).not.toBe(before)
  await page.reload()
  await waitLoaded(page)
  expect(await page.evaluate(() => document.documentElement.getAttribute('data-theme'))).toBe(after)
})

test('activity list renders items', async ({ page }) => {
  await waitLoaded(page)
  await openDrawer(page)
  const items = page.locator('.activity-row')
  await expect(items.first()).toBeVisible({ timeout: 5000 })
  const count = await items.count()
  expect(count).toBeGreaterThan(0)
})

test('drawer visible with collapsed stats', async ({ page }) => {
  await waitLoaded(page)
  await expect(page.locator('.drawer')).toBeVisible()
  await expect(page.locator('.stat-pill').first()).toBeVisible()
})

test('clicking activity opens detail panel', async ({ page }) => {
  await waitLoaded(page)
  await openDrawer(page)
  const first = page.locator('.activity-row').first()
  await first.click()
  await expect(page.locator('.overlay')).toBeVisible({ timeout: 3000 })
  await expect(page.locator('.close-btn')).toBeVisible()
})
