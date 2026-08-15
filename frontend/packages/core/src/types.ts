import type { Activity } from '@git-fit/shared'
import type { ComponentType } from 'react'

export interface NavLinkItem {
  name: string
  url?: string
  children?: { name: string; url: string }[]
}

export interface SiteConfig {
  title?: string
  url?: string
  logo?: string | null
  navLinks?: NavLinkItem[]
  mapTileVendor?: string
  mapTileStyle?: string
  mapTileToken?: string
  dashLines?: boolean
  privacyMode?: boolean
  showLabels?: boolean
}

export interface Config {
  theme?: string
  entries?: Record<string, string>
  plugins?: Record<string, Record<string, unknown>>
  data?: Record<string, { source: string; optional?: boolean }>
  site?: SiteConfig
  /** 单主题站点配置覆盖，key 与 entries 的值（themeId）一一对应 */
  themes?: Record<string, { site?: SiteConfig }>
}

export interface PluginManifest {
  id: string
  name?: string
  version?: string
}

export interface Stats {
  summary: {
    total_activities: number
    unique_activities: number
    total_distance_km: number
    total_moving_time_h: number
    total_elevation_gain_m: number
  }
  streaks: {
    current: number
    all_time: number
  }
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

export type GitFitPlugin = ThemePlugin | RegularPlugin
