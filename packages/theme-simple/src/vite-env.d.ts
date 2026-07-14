/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE__MAPBOX__TOKEN: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
