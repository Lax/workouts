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
  writeFileSync(dist('activities.json'), JSON.stringify(generateActivities(60)))
  writeFileSync(dist('stats.json'), JSON.stringify({
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
  }))
})

async function waitLoaded(page: Page) {
  await page.goto('/index.html')
  await expect(page.locator('text=Workouts')).toBeVisible({ timeout: 10000 })
}

async function gotoOverview(page: Page) {
  await page.goto('/overview.html')
  await expect(page.locator('text=Workouts')).toBeVisible({ timeout: 10000 })
}

test('SPA loads without page errors', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', err => errors.push(err.message))
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
  // Simple theme has a bottom activity bar with activity cards
  const actCards = page.locator('text=km').first()
  await expect(actCards).toBeVisible({ timeout: 5000 })
})

test('color mode toggles in simple theme', async ({ page }) => {
  await waitLoaded(page)
  // Type and Speed buttons are visible
  await expect(page.locator('button:has-text("类型")')).toBeVisible()
  await expect(page.locator('button:has-text("速度")')).toBeVisible()
  // Click speed mode
  await page.locator('button:has-text("速度")').click()
  await expect(page.locator('button:has-text("速度")')).toBeVisible()
})

test('overview page loads without errors', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', err => errors.push(err.message))
  await gotoOverview(page)
  expect(errors).toEqual([])
})

test('overview drawer opens and shows activities', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('text=/activities/').first().click()
  await expect(page.locator('text=Filters')).toBeVisible({ timeout: 3000 })
  await expect(page.locator('text=/Morning|Evening|Lunch|Hill|Recovery|Long|Commute|Weekend/').first()).toBeVisible({ timeout: 5000 })
})

test('overview clicking activity opens detail panel', async ({ page }) => {
  await gotoOverview(page)
  await page.locator('text=/activities/').first().click()
  const activityLink = page.locator('text=/Morning|Evening|Lunch|Hill|Recovery|Long|Commute|Weekend/').first()
  await expect(activityLink).toBeVisible({ timeout: 5000 })
  await activityLink.click()
  await expect(page.locator('button:has-text("×")')).toBeVisible({ timeout: 5000 })
  await expect(page.locator('text=Distance')).toBeVisible()
})
