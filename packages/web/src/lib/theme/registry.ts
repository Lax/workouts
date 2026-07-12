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
    const modules = import.meta.glob<Record<string, any>>(
      '/src/plugins/themes/*/src/manifest.json',
      { eager: false, import: 'default' },
    )

    for (const [path, loader] of Object.entries(modules)) {
      try {
        const manifestJson = await loader()
        const dir = path.replace('/manifest.json', '')
        const layoutMod = await import(/* @vite-ignore */ `${dir}/Layout.svelte`)
        const pkg: ThemePackage = {
          manifest: manifestJson as any,
          default: layoutMod.default,
        }
        ThemeRegistry.register(pkg)
      } catch (e) {
        console.warn(`Theme load failed: ${path}`, e)
      }
    }
  },
}
