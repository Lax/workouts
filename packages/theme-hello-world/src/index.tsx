import type { ThemePlugin, ThemeProps } from '@workouts/core'

interface PkgMeta {
  name: string
  version: string
  dependencies?: Record<string, string>
  peerDependencies?: Record<string, string>
  devDependencies?: Record<string, string>
}

const wsPkgs = import.meta.glob('/packages/*/package.json', { eager: true }) as Record<string, PkgMeta>
const nmTopPkgs = import.meta.glob('/node_modules/*/package.json', { eager: true }) as Record<string, PkgMeta>
const nmScopedPkgs = import.meta.glob('/node_modules/@*/*/package.json', { eager: true }) as Record<string, PkgMeta>

const allNmPkgs = { ...nmTopPkgs, ...nmScopedPkgs }

const wsNames = new Set<string>()
const runtimeNames = new Set<string>()
const toolingNames = new Set<string>()

const TOOLING_LIST = new Set([
  'vite', 'typescript', 'vitest', 'jsdom', '@biomejs/biome',
  '@playwright/test', '@vitejs/plugin-react',
])

for (const pkg of Object.values(wsPkgs)) {
  wsNames.add(pkg.name)
  const deps = { ...pkg.dependencies, ...pkg.peerDependencies, ...pkg.devDependencies }
  for (const [name] of Object.entries(deps ?? {})) {
    if (TOOLING_LIST.has(name)) toolingNames.add(name)
    else if (!name.startsWith('@workouts/') && !name.startsWith('@types/')) runtimeNames.add(name)
    if (name.startsWith('@types/')) toolingNames.add(name)
  }
}

interface Row {
  name: string
  version: string
}

function toRows(names: Set<string>): Row[] {
  return [...names]
    .map((name) => {
      const key = `/node_modules/${name}/package.json`
      const pkg = allNmPkgs[key]
      return pkg ? { name, version: pkg.version } : null
    })
    .filter((r): r is Row => r !== null)
    .sort((a, b) => a.name.localeCompare(b.name))
}

const wsRows: Row[] = [...wsNames].sort().map((name) => {
  const key = Object.keys(wsPkgs).find((k) => wsPkgs[k].name === name)
  return { name, version: key ? wsPkgs[key].version : '?' }
})

const runtimeRows = toRows(runtimeNames)
const toolingRows = toRows(toolingNames)

function Table({ label, rows }: { label: string; rows: Row[] }) {
  return (
    <div style={{ marginBottom: '1.5rem' }}>
      <h2 style={{ fontSize: '1rem', marginBottom: '0.5rem', color: 'var(--color-accent, #4dd2ff)' }}>
        {label} ({rows.length})
      </h2>
      <table style={{ fontSize: '0.8rem', borderCollapse: 'collapse' }}>
        <tbody>
          {rows.map((r) => (
            <tr key={r.name}>
              <td style={{ padding: '2px 16px 2px 0', fontFamily: 'monospace', color: 'var(--color-text, #e0e0e0)' }}>
                {r.name}
              </td>
              <td style={{ padding: '2px 0', fontFamily: 'monospace', color: 'var(--color-text-secondary, #888)' }}>
                {r.version}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function HelloWorldLayout(_props: ThemeProps) {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '100vh',
        padding: '2rem',
        color: 'var(--color-text, #e0e0e0)',
        background: 'var(--color-bg, #121212)',
      }}
    >
      <h1 style={{ fontSize: '2rem', marginBottom: '1.5rem' }}>Hello World</h1>
      <Table label="Workspace Packages" rows={wsRows} />
      <Table label="Runtime Dependencies" rows={runtimeRows} />
      <Table label="Tooling" rows={toolingRows} />
    </div>
  )
}

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'hello-world', name: 'Hello World', version: '0.1.0' },
  Layout: HelloWorldLayout,
}

export default theme
