import { fetchData, fetchTracks } from '@workouts/plugin-data-source'
import { afterEach, describe, expect, it, vi } from 'vitest'

describe('fetchTracks', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  function mockFetch(ok: boolean, jsonData: unknown, status = ok ? 200 : 404) {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok,
      status,
      json: async () => jsonData,
    } as unknown as Response)
  }

  it('returns parsed JSON map on success', async () => {
    mockFetch(true, { r1: 'abc', r2: 'def' })
    const result = await fetchTracks('tracks.json')
    expect(result).toEqual({ r1: 'abc', r2: 'def' })
  })

  it('returns null on fetch throw (network error)', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('Network down'))
    const result = await fetchTracks('tracks.json')
    expect(result).toBeNull()
  })

  it('returns null on HTTP 404', async () => {
    mockFetch(false, {}, 404)
    const result = await fetchTracks('tracks.json')
    expect(result).toBeNull()
  })

  it('returns null on invalid JSON body', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => {
        throw new Error('Unexpected token')
      },
    } as unknown as Response)
    const result = await fetchTracks('tracks.json')
    expect(result).toBeNull()
  })
})

describe('fetchData', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  const activitiesJson = [{ run_id: 'a1', type: 'run', distance: 5000, moving_time: 1800 }]

  it('fetches all sources in parallel and normalizes activities', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => activitiesJson,
    } as unknown as Response)

    const config = {
      activities: { source: 'activities.json', optional: false },
      stats: { source: 'stats.json', optional: true },
    }
    const result = await fetchData(config)

    expect(result.activities).toHaveLength(1)
    expect(result.activities[0].run_id).toBe('a1')
    expect(result.error).toBeUndefined()
    expect(vi.mocked(fetch)).toHaveBeenCalledTimes(2)
  })

  it('returns error for mandatory source failure', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('Network down'))

    const config = {
      activities: { source: 'activities.json', optional: false },
      stats: { source: 'stats.json', optional: true },
    }
    const result = await fetchData(config)

    expect(result.error).toContain('Failed to load activities')
    expect(result.error).toContain('Network down')
    expect(result.activities).toEqual([])
  })

  it('silently returns null for optional source failure', async () => {
    globalThis.fetch = vi.fn()
    vi.mocked(fetch)
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => activitiesJson,
      } as unknown as Response)
      .mockRejectedValueOnce(new Error('Stats unavailable'))

    const config = {
      activities: { source: 'activities.json', optional: false },
      stats: { source: 'stats.json', optional: true },
    }
    const result = await fetchData(config)

    expect(result.activities).toHaveLength(1)
    expect(result.error).toBeUndefined()
  })
})
