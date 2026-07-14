import type { ThemePlugin, ThemeProps } from '@workouts/core'
import './hello.css'

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

const TOOLING_LIST = new Set(['vite', 'typescript', 'vitest', 'jsdom', '@biomejs/biome', '@playwright/test', '@vitejs/plugin-react'])

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

function Section({ label, rows }: { label: string; rows: Row[] }) {
  return (
    <div className="hello-section">
      <h2>
        {label} <span style={{ fontWeight: 400, color: 'var(--color-text-dim)' }}>({rows.length})</span>
      </h2>
      <div className="hello-list">
        {rows.length === 0 ? (
          <div className="hello-empty">No packages found</div>
        ) : (
          rows.map((r) => (
            <div key={r.name} className="hello-row">
              <span className="hello-pkg">{r.name}</span>
              <span className="hello-ver">{r.version}</span>
            </div>
          ))
        )}
      </div>
    </div>
  )
}

function HelloWorldLayout(_props: ThemeProps) {
  return (
    <div className="hello-container">
      <div className="hello-header">
        <h1>Hello World</h1>
        <p>Workouts frontend — dependency &amp; tooling overview</p>
      </div>
      <div className="hello-content">
        <Section label="Workspace Packages" rows={wsRows} />
        <Section label="Runtime Dependencies" rows={runtimeRows} />
        <Section label="Tooling" rows={toolingRows} />
      </div>
    </div>
  )
}

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'hello-world', name: 'Hello World', version: '0.1.0' },
  Layout: HelloWorldLayout,
}

export default theme
