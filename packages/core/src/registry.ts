import type { ComponentType } from 'react'
import type { ComponentRegistry, PluginAPI } from './types'

export function createRegistry(): ComponentRegistry {
  const components = new Map<string, ComponentType<any>>()

  return {
    register(pluginId: string, name: string, component: ComponentType<any>) {
      components.set(key(pluginId, name), component)
    },
    get(pluginId: string, name: string) {
      return components.get(key(pluginId, name)) ?? null
    },
  }
}

export function createPluginAPI(registry: ComponentRegistry, pluginId: string): PluginAPI {
  return {
    registerComponent(name: string, component: ComponentType<any>) {
      registry.register(pluginId, name, component)
    },
  }
}

function key(pluginId: string, name: string): string {
  return `${pluginId}:${name}`
}
