import { ThemeRegistry } from './registry'
import type { ThemeContext, DataRequirement, ConfigField } from '@workouts/shared'

const configCache = new Map<string, Record<string, any>>()
const storeRegistry = new Map<string, { value: any; owner: string }>()

function fetchRequiredData(dataDef: Record<string, DataRequirement>): Promise<Record<string, any>> {
  const fetches: Record<string, Promise<any>> = {}
  for (const [key, req] of Object.entries(dataDef)) {
    if (!req.optional) {
      fetches[key] = fetch(req.source).then((r) => {
        if (!r.ok) throw new Error(`Failed to load ${req.source}: ${r.status}`)
        return r.json()
      })
    }
  }
  return Promise.all(Object.entries(fetches).map(([k, p]) => p.then((v) => [k, v] as const)))
    .then((results) => Object.fromEntries(results))
}

function loadConfig(themeName: string, defaults?: Record<string, any>): Record<string, any> {
  if (configCache.has(themeName)) return configCache.get(themeName)!
  const stored = localStorage.getItem(`theme:${themeName}:config`)
  const config = stored ? { ...defaults, ...JSON.parse(stored) } : { ...defaults }
  configCache.set(themeName, config)
  return config
}

function saveConfig(themeName: string, config: Record<string, any>) {
  configCache.set(themeName, config)
  localStorage.setItem(`theme:${themeName}:config`, JSON.stringify(config))
}

export async function activateTheme(name: string): Promise<ThemeContext> {
  const pkg = ThemeRegistry.lookup(name)
  if (!pkg) throw new Error(`Theme not found: ${name}`)

  const prev = ThemeRegistry.active
  if (prev?.onDeactivate) prev.onDeactivate()

  cleanupStores(name)

  const data = pkg.manifest.data ? await fetchRequiredData(pkg.manifest.data) : {}
  const config = loadConfig(name, pkg.manifest.config ? defaultsFromSchema(pkg.manifest.config) : {})

  const ctx: ThemeContext = {
    data,
    config,
    theme: name,
    themeName: pkg.manifest.displayName,
    updateConfig: (patch: Record<string, any>) => {
      const next = { ...config, ...patch }
      Object.assign(config, patch)
      saveConfig(name, next)
    },
    registerStore: (key: string, initial: any) => {
      const existing = storeRegistry.get(`${name}:${key}`)
      if (existing) return existing.value
      const store = { value: initial }
      storeRegistry.set(`${name}:${key}`, { value: store, owner: name })
      return store
    },
  }

  ThemeRegistry.setActive(name)

  if (pkg.store) pkg.store(ctx)
  if (pkg.onActivate) pkg.onActivate(ctx)

  return ctx
}

export function deactivateTheme() {
  const pkg = ThemeRegistry.active
  if (pkg?.onDeactivate) pkg.onDeactivate()
  if (pkg) cleanupStores(pkg.manifest.name)
  ThemeRegistry.setActive('')
}

export function getActiveContext(): ThemeContext | null {
  return activeCtx
}

let activeCtx: ThemeContext | null = null

export function setActiveContext(ctx: ThemeContext | null) {
  activeCtx = ctx
}

function cleanupStores(themeName: string) {
  for (const [key, entry] of storeRegistry) {
    if (entry.owner === themeName) storeRegistry.delete(key)
  }
}

function defaultsFromSchema(schema: Record<string, any>): Record<string, any> {
  const result: Record<string, any> = {}
  for (const [key, field] of Object.entries(schema)) {
    result[key] = (field as any).default
  }
  return result
}
