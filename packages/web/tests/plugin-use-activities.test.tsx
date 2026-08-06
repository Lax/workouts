import { ThemeProvider } from '@workouts/core'
import { type ActivitiesResult, useActivities } from '@workouts/plugin-data-source'
import type { Activity } from '@workouts/shared'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const activitiesJson: Activity[] = [
  {
    run_id: 'a1',
    name: 'Morning Run',
    distance: 5000,
    moving_time: 1800,
    sport_category: 'run',
    start_date: '2024-01-01T00:00:00Z',
    start_date_local: null,
    location_country: null,
    source: 'garmin',
    average_heartrate: 145,
    max_heartrate: null,
    average_cadence: null,
    max_cadence: null,
    average_power: null,
    max_power: null,
    average_temperature: null,
    calories: null,
    average_speed: null,
    elevation_gain: null,
    summary_polyline: null,
  },
]

const tracksJson = { a1: 'abc123', a2: 'def456' }

function makeConfig(overrides?: Record<string, unknown>) {
  return {
    data: {
      activities: { source: 'activities.json', optional: false },
      stats: { source: 'stats.json', optional: true },
      ...overrides,
    },
  }
}

let lastResult: ActivitiesResult | null = null

function CaptureHook() {
  lastResult = useActivities()
  return null
}

describe('useActivities', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => activitiesJson,
    } as unknown as Response)
    vi.spyOn(window, 'prompt').mockReturnValue(null)
    vi.stubGlobal('localStorage', {
      getItem: vi.fn(() => undefined),
      setItem: vi.fn(),
      removeItem: vi.fn(),
      clear: vi.fn(),
    })
    lastResult = null
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('sets loading=false and returns activities after fetch', async () => {
    await act(async () => {
      root.render(
        <ThemeProvider data={{ activities: [], stats: null }} config={makeConfig()} registry={{ register: vi.fn(), get: vi.fn() }}>
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(lastResult).not.toBeNull()
    expect(lastResult!.loading).toBe(false)
    expect(lastResult!.activities).toHaveLength(1)
    expect(lastResult!.activities[0].run_id).toBe('a1')
    expect(lastResult!.error).toBeUndefined()
  })

  it('loads tracks after activities (two-phase)', async () => {
    globalThis.fetch = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => activitiesJson,
      } as unknown as Response)
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({}),
      } as unknown as Response)
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => tracksJson,
      } as unknown as Response)

    await act(async () => {
      root.render(
        <ThemeProvider
          data={{ activities: [], stats: null }}
          config={makeConfig({ tracks: { source: 'tracks.json', optional: true } })}
          registry={{ register: vi.fn(), get: vi.fn() }}
        >
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(lastResult).not.toBeNull()
    expect(lastResult!.loading).toBe(false)
    expect(lastResult!.activities).toHaveLength(1)
    expect(lastResult!.tracks).toEqual(tracksJson)
    expect(lastResult!.tracksLoading).toBe(false)
    expect(lastResult!.error).toBeUndefined()
  })

  it('returns tracks=null when no tracksSource in config', async () => {
    await act(async () => {
      root.render(
        <ThemeProvider data={{ activities: [], stats: null }} config={makeConfig()} registry={{ register: vi.fn(), get: vi.fn() }}>
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(lastResult).not.toBeNull()
    expect(lastResult!.tracks).toBeNull()
    expect(lastResult!.tracksLoading).toBe(false)
  })

  it('sets error state on mandatory activities fetch failure', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('Server error'))

    await act(async () => {
      root.render(
        <ThemeProvider data={{ activities: [], stats: null }} config={makeConfig()} registry={{ register: vi.fn(), get: vi.fn() }}>
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(lastResult).not.toBeNull()
    expect(lastResult!.error).toContain('Server error')
    expect(lastResult!.activities).toEqual([])
    expect(lastResult!.loading).toBe(false)
  })

  it('prompts for a data URL and renders from it when local JSON is missing', async () => {
    vi.spyOn(window, 'prompt').mockReturnValue('https://data.example/workouts')
    globalThis.fetch = vi.fn((input: unknown) => {
      const url = String(input)
      if (url.startsWith('https://data.example/workouts/')) {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: async () => activitiesJson,
        } as unknown as Response)
      }
      return Promise.reject(new Error('Server error'))
    })

    await act(async () => {
      root.render(
        <ThemeProvider data={{ activities: [], stats: null }} config={makeConfig()} registry={{ register: vi.fn(), get: vi.fn() }}>
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(window.prompt).toHaveBeenCalledTimes(1)
    expect(lastResult!.activities).toHaveLength(1)
    expect(lastResult!.error).toBeUndefined()
    expect(lastResult!.loading).toBe(false)
    expect(localStorage.setItem).toHaveBeenCalledWith('git-fit-data-url', 'https://data.example/workouts')
  })

  it('keeps error state when the prompt is cancelled', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('Server error'))

    await act(async () => {
      root.render(
        <ThemeProvider data={{ activities: [], stats: null }} config={makeConfig()} registry={{ register: vi.fn(), get: vi.fn() }}>
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(window.prompt).toHaveBeenCalledTimes(1)
    expect(lastResult!.error).toContain('Server error')
    expect(lastResult!.activities).toEqual([])
    expect(localStorage.setItem).not.toHaveBeenCalled()
  })

  it('alerts and keeps error state when the entered URL is invalid', async () => {
    const alertSpy = vi.spyOn(window, 'alert')
    vi.spyOn(window, 'prompt').mockReturnValue('https://invalid.example')
    globalThis.fetch = vi.fn((input: unknown) => {
      const url = String(input)
      if (url.startsWith('https://invalid.example/')) {
        return Promise.resolve({
          ok: false,
          status: 404,
          json: async () => ({}),
        } as unknown as Response)
      }
      return Promise.reject(new Error('Server error'))
    })

    await act(async () => {
      root.render(
        <ThemeProvider data={{ activities: [], stats: null }} config={makeConfig()} registry={{ register: vi.fn(), get: vi.fn() }}>
          <CaptureHook />
        </ThemeProvider>,
      )
    })

    expect(window.prompt).toHaveBeenCalledTimes(1)
    expect(alertSpy).toHaveBeenCalledWith('Invalid data URL: https://invalid.example')
    expect(lastResult!.error).toContain('Server error')
    expect(localStorage.setItem).not.toHaveBeenCalled()
  })
})
