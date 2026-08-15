#!/usr/bin/env node
/**
 * Build-time: collect direct dependency versions for hello page.
 * Reads declared deps from workspace package.json, looks up installed
 * versions via require.resolve + reading the actual package.json.
 */
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, '..')

const TOOLING = new Set([
  'vite', 'typescript', 'vitest', 'jsdom',
  '@biomejs/biome', '@playwright/test', '@vitejs/plugin-react',
])

function getWorkspacePkgs() {
  const pkgs = []
  const dir = resolve(root, 'packages')
  if (!existsSync(dir)) return pkgs
  for (const entry of readdirSync(dir)) {
    const p = resolve(dir, entry, 'package.json')
    if (!statSync(resolve(dir, entry)).isDirectory() || !existsSync(p)) continue
    try {
      const meta = JSON.parse(readFileSync(p, 'utf-8'))
      if (meta.name && meta.version) pkgs.push({ name: meta.name, version: meta.version })
    } catch {}
  }
  return pkgs
}

function getDeclaredDeps() {
  const deps = new Set()
  const files = []
  const wsDir = resolve(root, 'packages')
  if (existsSync(wsDir)) {
    for (const entry of readdirSync(wsDir)) {
      const p = resolve(wsDir, entry, 'package.json')
      if (statSync(resolve(wsDir, entry)).isDirectory() && existsSync(p)) files.push(p)
    }
  }
  const rootPkg = resolve(root, 'package.json')
  if (existsSync(rootPkg)) files.push(rootPkg)

  for (const f of files) {
    try {
      const meta = JSON.parse(readFileSync(f, 'utf-8'))
      for (const section of ['dependencies', 'devDependencies', 'peerDependencies']) {
        if (meta[section]) Object.keys(meta[section]).forEach((n) => deps.add(n))
      }
    } catch {}
  }
  return deps
}

function collect() {
  const declared = getDeclaredDeps()
  const workspace = getWorkspacePkgs()
  const runtime = [], tooling = []

  for (const name of declared) {
    if (name.startsWith('@workouts/') || name.startsWith('@types/')) continue
    let version = '?'
    const scoped = name.startsWith('@')
    const parts = name.split('/')
    const pkgPath = scoped
      ? resolve(root, 'node_modules', parts[0], parts[1], 'package.json')
      : resolve(root, 'node_modules', name, 'package.json')
    if (existsSync(pkgPath)) {
      try {
        const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'))
        version = pkg.version || '?'
      } catch {}
    }
    const row = { name, version }
    if (TOOLING.has(name)) tooling.push(row)
    else runtime.push(row)
  }

  runtime.sort((a, b) => a.name.localeCompare(b.name))
  tooling.sort((a, b) => a.name.localeCompare(b.name))

  const outDir = resolve(root, 'packages/web/public')
  if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true })
  writeFileSync(resolve(outDir, 'versions.json'), JSON.stringify({ workspace, runtime, tooling }, null, 2))
  console.log(`versions.json: ${workspace.length} workspace, ${runtime.length} runtime, ${tooling.length} tooling`)
}

collect()
