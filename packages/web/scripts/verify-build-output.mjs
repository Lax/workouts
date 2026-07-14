import { existsSync, readFileSync, readdirSync } from 'fs'
import { resolve } from 'path'

const root = resolve(import.meta.dirname, '..')
const config = JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf-8'))
const entries = Object.keys(config.entries ?? { index: config.theme })
const dist = resolve(root, 'dist')

let failed = false

function check(condition, msg) {
  if (!condition) {
    console.error(`::error::${msg}`)
    failed = true
  } else {
    console.log(`OK: ${msg}`)
  }
}

for (const key of entries) {
  const html = resolve(dist, `${key}.html`)
  check(existsSync(html), `Entry HTML exists: ${key}.html`)

  const htmlContent = readFileSync(html, 'utf-8')
  check(htmlContent.includes(`./assets/${key}-`), `${key}.html references assets/${key}-*`)
}

const versionsJson = resolve(dist, 'versions.json')
check(existsSync(versionsJson), 'versions.json exists')
if (existsSync(versionsJson)) {
  const data = JSON.parse(readFileSync(versionsJson, 'utf-8'))
  check(Array.isArray(data.workspace), 'versions.json has workspace array')
  check(Array.isArray(data.runtime), 'versions.json has runtime array')
  check(Array.isArray(data.tooling), 'versions.json has tooling array')
  check(data.workspace.length > 0, 'workspace has entries')
}

const assets = readdirSync(resolve(dist, 'assets'))
for (const key of entries) {
  const hasJs = assets.some((f) => f.startsWith(`${key}-`) && f.endsWith('.js'))
  check(hasJs, `assets/${key}-*.js exists`)
  const hasCss = assets.some((f) => f.startsWith(`${key}-`) && f.endsWith('.css'))
  if (!hasCss) console.log(`SKIP: assets/${key}-*.css (no separate CSS chunk)`)
}

if (failed) {
  console.error('Build output verification FAILED')
  process.exit(1)
}
console.log('\nAll build output checks passed')
