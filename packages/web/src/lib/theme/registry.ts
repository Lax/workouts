import type { ThemePackage } from '@workouts/shared'

const entries = new Map<string, ThemePackage>()
let activeName: string | null = null

export const ThemeRegistry = {
  register(pkg: ThemePackage) {
    entries.set(pkg.manifest.name, pkg)
  },

  lookup(name: string): ThemePackage | undefined {
    return entries.get(name)
  },

  list(): ThemePackage[] {
    return Array.from(entries.values())
  },

  get active(): ThemePackage | null {
    return activeName ? entries.get(activeName) ?? null : null
  },

  setActive(name: string) {
    if (!entries.has(name)) throw new Error(`Theme not registered: ${name}`)
    activeName = name
  },

  async loadAll(): Promise<void> {
    const manifests = import.meta.glob<Record<string, any>>(
      '/src/plugins/themes/*/src/manifest.json',
      { eager: true, import: 'default' },
    )
    const layouts = import.meta.glob<Record<string, any>>(
      '/src/plugins/themes/*/src/Layout.svelte',
      { eager: true, import: 'default' },
    )

    for (const [path, themeManifest] of Object.entries(manifests)) {
      try {
        const layoutPath = path.replace('/manifest.json', '/Layout.svelte')
        const layoutMod = layouts[layoutPath]
        if (!layoutMod) {
          console.warn(`Theme layout not found: ${layoutPath}`)
          continue
        }
        const pkg: ThemePackage = {
          manifest: themeManifest as any,
          default: layoutMod,
        }
        ThemeRegistry.register(pkg)
      } catch (e) {
        console.warn(`Theme load failed: ${path}`, e)
      }
    }
  },
}
