/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE__MAPBOX__TOKEN: string
  readonly VITE__MAPTILER__TOKEN: string
  readonly VITE__MAP_TILE_VENDOR?: string
  readonly VITE__MAP_TILE_STYLE?: string
  readonly VITE__MAP_TILE_TOKEN?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
