/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly GIT_FIT_DATA_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
