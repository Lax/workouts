export { bootstrap } from './bootstrap.js'
export { ErrorBoundary } from './ErrorBoundary'
export { ThemeProvider, useTheme, useComponent, useRequiredComponent } from './context'
export { createRegistry, createPluginAPI } from './registry'
export type {
  Config,
  PluginManifest,
  Stats,
  ThemeProps,
  ComponentRegistry,
  PluginAPI,
  ThemePlugin,
  RegularPlugin,
  WorkoutsPlugin,
} from './types'
