import type { ThemePlugin, ThemeProps } from '@workouts/core'
import { useEffect, useState } from 'react'
import './hello.css'

interface Row {
  name: string
  version: string
}

interface VersionData {
  workspace: Row[]
  runtime: Row[]
  tooling: Row[]
}

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
  const [data, setData] = useState<VersionData | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch('/versions.json')
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json()
      })
      .then((d: VersionData) => setData(d))
      .catch((e: Error) => setError(e.message))
  }, [])

  return (
    <div className="hello-container">
      <div className="hello-header">
        <h1>Hello World</h1>
        <p>Workouts frontend — dependency &amp; tooling overview</p>
      </div>
      <div className="hello-content">
        {error ? (
          <div className="hello-empty">Failed to load version data: {error}</div>
        ) : !data ? (
          <div className="hello-empty">Loading...</div>
        ) : (
          <>
            <Section label="Workspace Packages" rows={data.workspace} />
            <Section label="Runtime Dependencies" rows={data.runtime} />
            <Section label="Tooling" rows={data.tooling} />
          </>
        )}
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
