import type { Activity } from '@workouts/shared'
import type { ComponentType, ReactNode } from 'react'
import { createContext, useContext, useMemo } from 'react'
import type { ComponentRegistry, Stats } from './types'

export interface ThemeContextValue {
  data: { activities: Activity[]; stats: Stats | null; error?: string }
  config: Record<string, unknown>
  registry: ComponentRegistry
}

const ThemeContext = createContext<ThemeContextValue | null>(null)

export function ThemeProvider({ data, config, registry, children }: ThemeContextValue & { children: ReactNode }) {
  const value = useMemo(() => ({ data, config, registry }), [data, config, registry])
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme must be used within a ThemeProvider')
  return ctx
}

export function useComponent(pluginId: string, name: string): ComponentType<any> | null {
  const { registry } = useTheme()
  return useMemo(() => registry.get(pluginId, name), [registry, pluginId, name])
}

export function useRequiredComponent(pluginId: string, name: string): ComponentType<any> | null {
  const Component = useComponent(pluginId, name)
  if (!Component) {
    console.warn(`[@workouts/core] Required component not registered: ${pluginId}:${name}`)
  }
  return Component
}
