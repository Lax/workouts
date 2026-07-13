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
        { category: 'walk', count: 7, distance_km: 50, moving_time_h: 15 },
        { category: 'workout', count: 0, distance_km: 0, moving_time_h: 0 },
      ],
    },
    monthly: [],
    yearly: [],
    streaks: { current: 7, all_time: 30 },
    activity_types: ['run', 'ride', 'hike', 'swim', 'walk', 'workout'],
  }))
})

async function waitLoaded(page: Page) {
  await page.goto('/index.html')
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
  // Theme toggle is the last button in the bottom-left overlay group
  const buttons = page.locator('button:has-text("☀️"), button:has-text("🌙")')
  await buttons.first().click()
  const after = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
  expect(after).not.toBe(before)
  await page.reload()
  await waitLoaded(page)
  expect(await page.evaluate(() => document.documentElement.getAttribute('data-theme'))).toBe(after)
})

test('drawer opens and shows activity count', async ({ page }) => {
  await waitLoaded(page)
  // Click the right-edge drawer toggle (contains "activities")
  await page.locator('text=/activities/').first().click()
  // Drawer panel slides in; should show filter header
  await expect(page.locator('text=Filters')).toBeVisible({ timeout: 3000 })
  // Should show activity type chips (Run, Ride, etc.)
  await expect(page.locator('text=/run/i').first()).toBeVisible()
})

test('activity items appear in drawer', async ({ page }) => {
  await waitLoaded(page)
  await page.locator('text=/activities/').first().click()
  // Activity items have date+name in the drawer
  await expect(page.locator('text=/Morning|Evening|Lunch|Hill|Recovery|Long|Commute|Weekend/').first()).toBeVisible({ timeout: 5000 })
})

test('clicking activity opens detail panel', async ({ page }) => {
  await waitLoaded(page)
  await page.locator('text=/activities/').first().click()
  // Wait for drawer content, click first activity name
  const activityLink = page.locator('text=/Morning|Evening|Lunch|Hill|Recovery|Long|Commute|Weekend/').first()
  await expect(activityLink).toBeVisible({ timeout: 5000 })
  await activityLink.click()
  // Detail panel modal opens with close button ×
  await expect(page.locator('button:has-text("×")')).toBeVisible({ timeout: 5000 })
  // Stats should be visible
  await expect(page.locator('text=Distance')).toBeVisible()
})
