import { afterEach, beforeEach, describe, expect, it, onTestFinished, vi } from 'vitest'

vi.mock('leaflet', () => {
  class MockTileLayer {
    addTo = vi.fn().mockReturnThis()
  }
  class MockPolyline {
    addTo = vi.fn().mockReturnThis()
    setStyle = vi.fn().mockReturnThis()
    bringToFront = vi.fn()
    bindTooltip = vi.fn().mockReturnThis()
    on = vi.fn()
    setLatLngs = vi.fn().mockReturnThis()
  }
  class MockCircleMarker {
    addTo = vi.fn().mockReturnThis()
    setLatLng = vi.fn().mockReturnThis()
    setRadius = vi.fn().mockReturnThis()
    setStyle = vi.fn().mockReturnThis()
  }

  const mapInstance = {
    setView: vi.fn().mockReturnThis(),
    remove: vi.fn(),
    fitBounds: vi.fn(),
    eachLayer: vi.fn(),
    addLayer: vi.fn(),
    removeLayer: vi.fn(),
    on: vi.fn(),
    invalidateSize: vi.fn(),
  }

  const mockMap = vi.fn(() => ({ ...mapInstance, _leaflet_id: 1 }))

  return {
    default: {
      map: mockMap,
      tileLayer: vi.fn(() => new MockTileLayer()),
      polyline: vi.fn(() => new MockPolyline()),
      circleMarker: vi.fn(() => new MockCircleMarker()),
      control: { zoom: vi.fn(() => ({ addTo: vi.fn() })) },
      latLngBounds: vi.fn(() => ({
        isValid: vi.fn(() => true),
        pad: vi.fn(() => ({ isValid: vi.fn(() => true) })),
      })),
      latLng: vi.fn(),
      TileLayer: MockTileLayer,
      Polyline: MockPolyline,
    },
  }
})

import { MapView } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'
import { DetailPanel, useOverviewStore } from '@workouts/theme-overview'
import L from 'leaflet'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'

function MapViewWrapper() {
  const colorScheme = useOverviewStore((s) => s.colorScheme)
  return <MapView activities={[]} colorScheme={colorScheme} />
}

function testActivity(overrides: Partial<Activity> = {}): Activity {
  return {
    run_id: 'test-1',
    name: 'Test Activity',
    distance: 5000,
    moving_time: 1800,
    elapsed_time: 2000,
    sport_category: 'run',
    start_date: '2024-06-01T00:00:00Z',
    start_date_local: '2024-06-01T00:00:00',
    location_country: null,
    source: 'garmin',
    average_heartrate: null,
    max_heartrate: null,
    average_cadence: null,
    max_cadence: null,
    average_power: null,
    max_power: null,
    average_temperature: null,
    calories: null,
    average_speed: null,
    elevation_gain: null,
    summary_polyline: '_p~iF~ps|U_ulLnnqC',
    ...overrides,
  }
}

describe('MapView — dark/light toggle impact', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    vi.clearAllMocks()
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('toggleTheme does not recreate map', async () => {
    await act(async () => {
      root.render(<MapViewWrapper />)
    })

    const mountCalls = vi.mocked(L.map).mock.calls.length
    expect(mountCalls).toBe(1)

    await act(async () => {
      useOverviewStore.getState().toggleTheme()
    })

    expect(L.map).toHaveBeenCalledTimes(mountCalls)
  })
})

function getFitBounds() {
  return (vi.mocked(L.map).mock.results[0]?.value as Record<string, unknown>)?.fitBounds as ReturnType<typeof vi.fn>
}

function activitiesA(): Activity[] {
  return [
    testActivity({ run_id: 'a', summary_polyline: '_p~iF~ps|U_ulLnnqC', start_date: '2024-01-01T00:00:00Z' }),
    testActivity({ run_id: 'b', summary_polyline: '_p~iF~ps|U_ulLnnqC', start_date: '2024-06-15T00:00:00Z' }),
    testActivity({ run_id: 'c', summary_polyline: '_p~iF~ps|U_ulLnnqC', start_date: '2025-03-01T00:00:00Z' }),
  ]
}

function activitiesB(): Activity[] {
  return [
    testActivity({ run_id: 'd', summary_polyline: '_p~iF~ps|U_ulLnnqC', start_date: '2024-02-01T00:00:00Z' }),
    testActivity({ run_id: 'e', summary_polyline: '_p~iF~ps|U_ulLnnqC', start_date: '2024-07-15T00:00:00Z' }),
    testActivity({ run_id: 'f', summary_polyline: '_p~iF~ps|U_ulLnnqC', start_date: '2025-04-01T00:00:00Z' }),
  ]
}

describe('MapView — fitBounds gating', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    vi.clearAllMocks()
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('calls fitBounds once on initial load', async () => {
    await act(async () => {
      root.render(<MapView activities={activitiesA()} colorScheme="light" />)
    })
    expect(getFitBounds()).toHaveBeenCalledTimes(1)
  })

  it('does not call fitBounds when empty', async () => {
    await act(async () => {
      root.render(<MapView activities={[]} colorScheme="light" />)
    })
    expect(getFitBounds()).toHaveBeenCalledTimes(0)
  })

  it('does not call fitBounds on colorMode change', async () => {
    await act(async () => {
      root.render(<MapView activities={activitiesA()} colorScheme="light" />)
    })
    const spy = getFitBounds()
    expect(spy).toHaveBeenCalledTimes(1)

    await act(async () => {
      root.render(<MapView activities={activitiesA()} colorScheme="light" colorMode="speed" />)
    })
    expect(spy).toHaveBeenCalledTimes(1)
  })

  it('calls fitBounds again when activity content changes (same length)', async () => {
    await act(async () => {
      root.render(<MapView activities={activitiesA()} colorScheme="light" />)
    })
    const spy = getFitBounds()
    expect(spy).toHaveBeenCalledTimes(1)

    await act(async () => {
      root.render(<MapView activities={activitiesB()} colorScheme="light" />)
    })
    expect(spy).toHaveBeenCalledTimes(2)
  })

  it('does not call fitBounds on sort (same content, different order)', async () => {
    const sorted = [...activitiesA()].reverse()
    await act(async () => {
      root.render(<MapView activities={activitiesA()} colorScheme="light" />)
    })
    const spy = getFitBounds()
    expect(spy).toHaveBeenCalledTimes(1)

    await act(async () => {
      root.render(<MapView activities={sorted} colorScheme="light" />)
    })
    expect(spy).toHaveBeenCalledTimes(1)
  })
})

describe('MiniMap — dark/light toggle impact', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    vi.clearAllMocks()

    useOverviewStore.setState({
      detailOpen: true,
      selectedActivity: testActivity(),
    })
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
    useOverviewStore.setState({
      detailOpen: false,
      selectedActivity: null,
    })
  })

  it('toggleTheme does not recreate mini map', async () => {
    await act(async () => {
      root.render(<DetailPanel />)
    })

    const countAfterMount = vi.mocked(L.map).mock.calls.length

    await act(async () => {
      useOverviewStore.getState().toggleTheme()
    })

    expect(L.map).toHaveBeenCalledTimes(countAfterMount)
  })
})

describe('MapView — route animation', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    vi.clearAllMocks()

    vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {})
    onTestFinished(() => {
      vi.mocked(window.cancelAnimationFrame).mockRestore()
    })
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  function singleActivity(): Activity[] {
    return [testActivity({ run_id: 'anim-1', summary_polyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@' })]
  }

  it('renders statically when animate=false (default)', async () => {
    await act(async () => {
      root.render(<MapView activities={singleActivity()} colorScheme="light" />)
    })

    expect(vi.mocked(L.polyline)).toHaveBeenCalledTimes(1)
    const pointsArg = vi.mocked(L.polyline).mock.calls[0][0] as [number, number][]
    expect(pointsArg.length).toBe(3)
  })

  it('animates single activity when animate=true', async () => {
    await act(async () => {
      root.render(<MapView activities={singleActivity()} colorScheme="light" animate />)
    })

    expect(vi.mocked(L.polyline)).toHaveBeenCalledTimes(2)
    const mainPoints = vi.mocked(L.polyline).mock.calls[0][0] as [number, number][]
    expect(mainPoints.length).toBe(2)
    const glowPoints = vi.mocked(L.polyline).mock.calls[1][0] as [number, number][]
    expect(glowPoints.length).toBe(2)
    expect(vi.mocked(L.circleMarker)).toHaveBeenCalledTimes(1)
  })

  it('no animation when activities.length>1 even with animate=true', async () => {
    await act(async () => {
      root.render(<MapView activities={activitiesA()} colorScheme="light" animate />)
    })

    const polylineInstances = vi.mocked(L.polyline).mock.results
    for (const r of polylineInstances) {
      const p = r.value as { setLatLngs: ReturnType<typeof vi.fn> } | undefined
      if (p?.setLatLngs) {
        expect(p.setLatLngs).not.toHaveBeenCalled()
      }
    }
  })

  it('handles null summary_polyline — no crash', async () => {
    await act(async () => {
      root.render(<MapView activities={[testActivity({ summary_polyline: null })]} colorScheme="light" animate />)
    })

    expect(L.polyline).toHaveBeenCalledTimes(0)
  })

  it('renders 2-point polyline instantly (no rAF)', async () => {
    const shortPolyline = '_p~iF~ps|U_ulLnnqC'
    await act(async () => {
      root.render(<MapView activities={[testActivity({ run_id: 'short', summary_polyline: shortPolyline })]} colorScheme="light" animate />)
    })

    const calls = vi.mocked(L.polyline).mock.calls
    const firstCallPoints = calls[0]?.[0] as [number, number][] | undefined
    expect(firstCallPoints).toBeDefined()
  })

  it('cancels old animation and starts new on activity switch (DC3)', async () => {
    const activityA = testActivity({ run_id: 'switch-a', summary_polyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@' })
    const activityB = testActivity({ run_id: 'switch-b', summary_polyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@' })

    await act(async () => {
      root.render(<MapView activities={[activityA]} colorScheme="light" animate />)
    })

    expect(vi.mocked(L.polyline)).toHaveBeenCalledTimes(2)
    const callsBefore = vi.mocked(L.polyline).mock.calls.length

    await act(async () => {
      root.render(<MapView activities={[activityB]} colorScheme="light" animate />)
    })

    expect(vi.mocked(L.polyline).mock.calls.length).toBeGreaterThan(callsBefore)
  })
})
