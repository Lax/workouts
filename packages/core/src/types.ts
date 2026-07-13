import type { ComponentType, ReactNode } from 'react'
import type { Activity } from '@workouts/shared'

export interface Config {
  theme?: string
  entries?: Record<string, string>
  plugins?: Record<string, Record<string, unknown>>
  data?: Record<string, { source: string; optional?: boolean }>
}

export interface PluginManifest {
  id: string
  name?: string
  version?: string
}

export interface Stats {
  totalActivities: number
  totalDistance: number
  totalDuration: number
  totalElevation: number
  byYear: Record<string, { count: number; distance: number }>
  byType: Record<string, { count: number; distance: number }>
}

export interface ThemeProps {
  data: {
    activities: Activity[]
    stats: Stats | null
    error?: string
  }
  config: Record<string, unknown>
  registry: ComponentRegistry
}

export interface ComponentRegistry {
  register(pluginId: string, name: string, component: ComponentType<any>): void
  get(pluginId: string, name: string): ComponentType<any> | null
}

export interface PluginAPI {
  registerComponent(name: string, component: ComponentType<any>): void
}

export interface ThemePlugin {
  type: 'theme'
  manifest: PluginManifest
  Layout: ComponentType<ThemeProps>
  plugins?: Record<string, RegularPlugin>
}

export interface RegularPlugin {
  type: 'plugin'
  manifest: PluginManifest
  setup: (api: PluginAPI) => void
}

export type WorkoutsPlugin = ThemePlugin | RegularPlugin
