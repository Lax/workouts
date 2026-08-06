import { fetchData, fetchTracks, probeDataUrl, resolveDataUrl } from '@workouts/plugin-data-source'
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

describe('resolveDataUrl', () => {
  it('returns source unchanged when baseUrl is empty', () => {
    expect(resolveDataUrl('activities.json', '')).toBe('activities.json')
  })

  it('joins baseUrl with trailing slash', () => {
    expect(resolveDataUrl('activities.json', 'https://data.example/workouts/')).toBe('https://data.example/workouts/activities.json')
  })

  it('joins baseUrl without trailing slash', () => {
    expect(resolveDataUrl('activities.json', 'https://data.example/workouts')).toBe('https://data.example/workouts/activities.json')
  })

  it('leaves absolute source unchanged', () => {
    expect(resolveDataUrl('https://other.example/tracks.json', 'https://data.example/workouts')).toBe('https://other.example/tracks.json')
  })

  it('leaves protocol-relative source unchanged', () => {
    expect(resolveDataUrl('//cdn.example/tracks.json', 'https://data.example/workouts')).toBe('//cdn.example/tracks.json')
  })
})

describe('fetchData', () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllEnvs()
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

  it('prefixes sources with GIT_FIT_DATA_URL when set', async () => {
    vi.stubEnv('GIT_FIT_DATA_URL', 'https://data.example/workouts')
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => [],
    } as unknown as Response)

    const config = {
      activities: { source: 'activities.json', optional: false },
      tracks: { source: 'tracks.json', optional: true },
    }
    await fetchData(config)

    expect(vi.mocked(fetch)).toHaveBeenCalledWith('https://data.example/workouts/activities.json')
  })

  it('leaves absolute sources unchanged when GIT_FIT_DATA_URL is set', async () => {
    vi.stubEnv('GIT_FIT_DATA_URL', 'https://data.example/workouts')
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => [],
    } as unknown as Response)

    const config = {
      activities: { source: 'https://other.example/activities.json', optional: false },
    }
    await fetchData(config)

    expect(vi.mocked(fetch)).toHaveBeenCalledWith('https://other.example/activities.json')
  })

  it('prefers the explicit baseUrl argument over GIT_FIT_DATA_URL', async () => {
    vi.stubEnv('GIT_FIT_DATA_URL', 'https://env.example/data/')
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => [],
    } as unknown as Response)

    const config = {
      activities: { source: 'activities.json', optional: false },
      tracks: { source: 'tracks.json', optional: true },
    }
    await fetchData(config, 'https://data.example/workouts')

    expect(vi.mocked(fetch)).toHaveBeenCalledWith('https://data.example/workouts/activities.json')
    expect(vi.mocked(fetch)).not.toHaveBeenCalledWith('https://env.example/data/activities.json')
  })
})

describe('probeDataUrl', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('returns true when the first mandatory source loads', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => [],
    } as unknown as Response)

    const config = { activities: { source: 'activities.json', optional: false } }
    await expect(probeDataUrl(config, 'https://data.example/workouts')).resolves.toBe(true)
    expect(vi.mocked(fetch)).toHaveBeenCalledWith('https://data.example/workouts/activities.json')
  })

  it('returns false when the source responds 404', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({}),
    } as unknown as Response)

    const config = { activities: { source: 'activities.json', optional: false } }
    await expect(probeDataUrl(config, 'https://data.example/workouts')).resolves.toBe(false)
  })

  it('returns false when the fetch throws', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('Network down'))

    const config = { activities: { source: 'activities.json', optional: false } }
    await expect(probeDataUrl(config, 'https://data.example/workouts')).resolves.toBe(false)
  })

  it('returns false without fetching when no mandatory source exists', async () => {
    globalThis.fetch = vi.fn()

    const config = { stats: { source: 'stats.json', optional: true } }
    await expect(probeDataUrl(config, 'https://data.example/workouts')).resolves.toBe(false)
    expect(vi.mocked(fetch)).not.toHaveBeenCalled()
  })
})
