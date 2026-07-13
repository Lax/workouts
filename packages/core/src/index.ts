export { bootstrap } from './bootstrap.js'
export { ThemeProvider, useComponent, useRequiredComponent, useTheme } from './context'
export { ErrorBoundary } from './ErrorBoundary'
export { createPluginAPI, createRegistry } from './registry'
export type {
  ComponentRegistry,
  Config,
  PluginAPI,
  PluginManifest,
  RegularPlugin,
  Stats,
  ThemePlugin,
  ThemeProps,
  WorkoutsPlugin,
} from './types'
