export type Scheme = 'light' | 'dark'

export type TileUrlBuilder = (scheme: Scheme) => string

export type Vendor = 'carto' | 'mapbox' | 'openfreemap' | 'maptiler' | 'stadiamaps'

export interface TileConfig {
  vendor: Vendor
  style?: string
  token?: string
}

const STYLES: Record<Vendor, Record<string, string>> = {
  carto: {
    'light-all': 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    'light-nolabels': 'https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png',
    'dark-all': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    'dark-nolabels': 'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
  },
  mapbox: {
    'light-v11': 'https://api.mapbox.com/styles/v1/mapbox/light-v11/tiles/{z}/{x}/{y}@2x?access_token={token}',
    'dark-v11': 'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/{z}/{x}/{y}@2x?access_token={token}',
    'satellite-streets-v12': 'https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/{z}/{x}/{y}@2x?access_token={token}',
    'navigation-night': 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/tiles/{z}/{x}/{y}@2x?access_token={token}',
  },
  openfreemap: {
    bright: 'https://tiles.openfreemap.org/styles/bright/{z}/{x}/{y}.png',
    dark: 'https://tiles.openfreemap.org/styles/dark/{z}/{x}/{y}.png',
  },
  maptiler: {
    'streets-v2': 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key={token}',
    'basic-v2': 'https://api.maptiler.com/maps/basic-v2/{z}/{x}/{y}.png?key={token}',
    'bright-v2': 'https://api.maptiler.com/maps/bright-v2/{z}/{x}/{y}.png?key={token}',
    'dark-v2': 'https://api.maptiler.com/maps/dark-v2/{z}/{x}/{y}.png?key={token}',
    'outdoor-v2': 'https://api.maptiler.com/maps/outdoor-v2/{z}/{x}/{y}.png?key={token}',
    'topo-v2': 'https://api.maptiler.com/maps/topo-v2/{z}/{x}/{y}.png?key={token}',
  },
  stadiamaps: {
    alidade_smooth: 'https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}.png?api_key={token}',
    alidade_smooth_dark: 'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}.png?api_key={token}',
  },
}

const DEFAULT_STYLE_FOR_SCHEME: Record<Vendor, Record<Scheme, string>> = {
  carto: { light: 'light-nolabels', dark: 'dark-nolabels' },
  mapbox: { light: 'light-v11', dark: 'dark-v11' },
  openfreemap: { light: 'bright', dark: 'dark' },
  maptiler: { light: 'bright-v2', dark: 'dark-v2' },
  stadiamaps: { light: 'alidade_smooth', dark: 'alidade_smooth_dark' },
}

const LABELED_STYLE: Record<Vendor, Record<Scheme, string>> = {
  carto: { light: 'light-all', dark: 'dark-all' },
  mapbox: { light: 'light-v11', dark: 'dark-v11' },
  openfreemap: { light: 'bright', dark: 'dark' },
  maptiler: { light: 'bright-v2', dark: 'dark-v2' },
  stadiamaps: { light: 'alidade_smooth', dark: 'alidade_smooth_dark' },
}

export const VENDORS: Vendor[] = ['carto', 'mapbox', 'openfreemap', 'maptiler', 'stadiamaps']

export function getAvailableStyles(vendor: Vendor): string[] {
  return Object.keys(STYLES[vendor] ?? {})
}

export function styleHasLabels(vendor: Vendor, style: string): boolean {
  if (vendor === 'carto') return style.includes('-all')
  if (vendor === 'mapbox') return true
  if (vendor === 'openfreemap') return true
  if (vendor === 'maptiler') return true
  if (vendor === 'stadiamaps') return true
  return false
}

function defaultStyle(vendor: Vendor, scheme: Scheme): string {
  return DEFAULT_STYLE_FOR_SCHEME[vendor]?.[scheme] ?? DEFAULT_STYLE_FOR_SCHEME.carto[scheme]
}

function labelStyle(vendor: Vendor, scheme: Scheme): string {
  return LABELED_STYLE[vendor]?.[scheme] ?? defaultStyle(vendor, scheme)
}

export function resolveTileUrl(config: TileConfig, scheme: Scheme): string {
  const { vendor, token } = config
  const style = config.style ?? defaultStyle(vendor, scheme)
  const vendorStyles = STYLES[vendor]
  const pattern = vendorStyles?.[style] ?? vendorStyles?.[defaultStyle(vendor, scheme)] ?? STYLES.carto[defaultStyle('carto', scheme)]
  if (!pattern) return ''
  return pattern.replace('{token}', token ?? '')
}

export function resolveLabeledTileUrl(config: TileConfig, scheme: Scheme): string {
  const { vendor, token } = config
  const style = labelStyle(vendor, scheme)
  const pattern = STYLES[vendor]?.[style]
  if (!pattern) return resolveTileUrl(config, scheme)
  return pattern.replace('{token}', token ?? '')
}

export function carto(): TileUrlBuilder {
  return (scheme: Scheme) => resolveTileUrl({ vendor: 'carto' }, scheme)
}

export function openfreemap(): TileUrlBuilder {
  return (scheme: Scheme) => resolveTileUrl({ vendor: 'openfreemap' }, scheme)
}

export function mapbox(token: string, style?: string): TileUrlBuilder {
  return (_scheme: Scheme) => resolveTileUrl({ vendor: 'mapbox', style, token }, 'dark')
}

export function maptiler(token: string, style?: string): TileUrlBuilder {
  return (scheme: Scheme) => resolveTileUrl({ vendor: 'maptiler', style, token }, scheme)
}

export function stadiamaps(token: string, style?: string): TileUrlBuilder {
  return (scheme: Scheme) => resolveTileUrl({ vendor: 'stadiamaps', style, token }, scheme)
}
