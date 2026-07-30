import { ThemeProvider } from '@workouts/core'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('@workouts/plugin-data-source', () => ({
  default: { type: 'plugin', manifest: { id: 'ds', name: 'DS', version: '1.0' }, setup: vi.fn() },
  useActivities: vi.fn(),
  useDerivedData: vi.fn(),
  computeYears: vi.fn(() => []),
  computeAvailableTypes: vi.fn(() => []),
  computeAvailableSources: vi.fn(() => []),
  computeLocationSummary: vi.fn(() => ({ countries: [], provinces: [], cities: [] })),
  computePeriods: vi.fn(() => []),
  computeProvinceStats: vi.fn(() => []),
  computeTypeBreakdown: vi.fn(() => []),
  computeFilteredActivities: vi.fn(() => []),
  detectLocation: vi.fn(() => ({ type: 'unknown', name: '' })),
}))

vi.mock('leaflet', () => ({
  default: {
    map: vi.fn(() => ({
      setView: vi.fn().mockReturnThis(),
      remove: vi.fn(),
      fitBounds: vi.fn(),
      eachLayer: vi.fn(),
      addLayer: vi.fn(),
      removeLayer: vi.fn(),
      on: vi.fn(),
      invalidateSize: vi.fn(),
      attributionControl: null,
      scrollWheelZoom: { enable: vi.fn() },
    })),
    tileLayer: vi.fn(() => ({ addTo: vi.fn().mockReturnThis() })),
    polyline: vi.fn(() => ({
      addTo: vi.fn().mockReturnThis(),
      setStyle: vi.fn().mockReturnThis(),
      bringToFront: vi.fn(),
      bindTooltip: vi.fn().mockReturnThis(),
      on: vi.fn(),
      setLatLngs: vi.fn().mockReturnThis(),
    })),
    circleMarker: vi.fn(() => ({
      addTo: vi.fn().mockReturnThis(),
      setStyle: vi.fn().mockReturnThis(),
      setLatLng: vi.fn().mockReturnThis(),
      setRadius: vi.fn().mockReturnThis(),
    })),
    control: { zoom: vi.fn(() => ({ addTo: vi.fn() })) },
    latLngBounds: vi.fn(() => ({ isValid: vi.fn(() => true), pad: vi.fn(() => ({ isValid: vi.fn(() => true) })) })),
    latLng: vi.fn(),
  },
}))

import { OverviewLayout } from '@workouts/theme-overview'
import { useActivities } from '@workouts/plugin-data-source'

const mockUseActivities = useActivities as ReturnType<typeof vi.fn>

describe('OverviewLayout loading state', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
  })

  afterEach(() => {
    vi.restoreAllMocks()
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('renders loading overlay when loading is true', async () => {
    mockUseActivities.mockReturnValue({
      activities: [],
      tracks: null,
      tracksLoading: false,
      loading: true,
      error: undefined,
    })

    await act(async () => {
      root.render(
        <ThemeProvider
          data={{ activities: [], stats: null }}
          config={{ data: { activities: { source: 'a.json', optional: false } } } as any}
          registry={{ register: vi.fn(), get: vi.fn() }}
        >
          <OverviewLayout />
        </ThemeProvider>,
      )
    })

    const overlay = container.querySelector('.loading-overlay')
    expect(overlay).not.toBeNull()
  })

  it('hides loading overlay when loading is false', async () => {
    mockUseActivities.mockReturnValue({
      activities: [],
      tracks: null,
      tracksLoading: false,
      loading: false,
      error: undefined,
    })

    await act(async () => {
      root.render(
        <ThemeProvider
          data={{ activities: [], stats: null }}
          config={{ data: { activities: { source: 'a.json', optional: false } } } as any}
          registry={{ register: vi.fn(), get: vi.fn() }}
        >
          <OverviewLayout />
        </ThemeProvider>,
      )
    })

    const overlay = container.querySelector('.loading-overlay')
    expect(overlay).toBeNull()
  })
})
