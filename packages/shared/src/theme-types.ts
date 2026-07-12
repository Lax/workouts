export interface DataRequirement {
  source: string
  optional?: boolean
}

export interface ConfigField {
  type: 'string' | 'number' | 'boolean' | 'string[]'
  default: any
  description?: string
}

export interface ThemeManifest {
  name: string
  displayName: string
  version: string
  description?: string
  author?: string
  data?: Record<string, DataRequirement>
  config?: Record<string, ConfigField>
}

export interface ThemeContext {
  data: Record<string, any>
  config: Record<string, any>
  theme: string
  themeName: string
  updateConfig: (patch: Record<string, any>) => void
  registerStore: (key: string, initial: any) => any
}

export interface ThemePackage {
  manifest: ThemeManifest
  default: any
  store?: (ctx: ThemeContext) => void
  onActivate?: (ctx: ThemeContext) => void
  onDeactivate?: () => void
}
