/**
 * Tile URL builders for Leaflet tile layers.
 * Each builder returns a function compatible with useLeafletMap's tileUrl option.
 */

type Scheme = 'light' | 'dark'

export type TileUrlBuilder = (scheme: Scheme) => string

/** CartoDB basemaps — default, no token needed */
export function carto(): TileUrlBuilder {
  return (scheme: Scheme) => {
    const s = scheme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
    return `https://{s}.basemaps.cartocdn.com/${s}/{z}/{x}/{y}{r}.png`
  }
}

/** OpenFreeMap — free, no token needed, good fallback for China */
export function openfreemap(): TileUrlBuilder {
  return (scheme: Scheme) => {
    const style = scheme === 'dark' ? 'dark' : 'bright'
    return `https://tiles.openfreemap.org/styles/${style}`
  }
}

/** Mapbox — requires pk. access token */
export function mapbox(token: string, style?: string): TileUrlBuilder {
  return (_scheme: Scheme) => {
    const s = style || 'dark-v11'
    return `https://api.mapbox.com/styles/v1/mapbox/${s}/tiles/{z}/{x}/{y}@2x?access_token=${token}`
  }
}
