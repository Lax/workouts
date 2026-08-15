import { appendFileSync, readFileSync } from 'fs'
import { resolve } from 'path'

const root = resolve(import.meta.dirname, '..')
const workspaceRoot = resolve(import.meta.dirname, '../..')
const summaryPath = resolve(root, 'coverage', 'coverage-summary.json')
const summary = JSON.parse(readFileSync(summaryPath, 'utf-8'))

const METRICS = ['statements', 'branches', 'functions', 'lines']
const TOP_FILES = 10

function pct(numerator, denominator) {
  return denominator === 0 ? 100 : (numerator / denominator) * 100
}

function metricCell(data) {
  const p = pct(data.covered, data.total)
  return `${p.toFixed(1)}% (${data.covered}/${data.total})`
}

function addRow(target, name, data) {
  const row = { name, counts: {} }
  for (const m of METRICS) {
    row.counts[m] = { total: data[m].total, covered: data[m].covered }
  }
  target.push(row)
}

function packageOf(file) {
  const rel = file.replace(/\\/g, '/')
  if (rel.startsWith('../')) {
    return rel.slice(3, rel.indexOf('/', 3))
  }
  if (rel.startsWith('src/')) {
    return 'web'
  }
  const m = rel.match(/packages\/([^/]+)\//)
  return m ? m[1] : '(root)'
}

const entries = Object.entries(summary).filter(([k]) => k !== 'total')
const byPackage = new Map()
const files = []

function displayPath(file) {
  return file.startsWith(workspaceRoot) ? file.slice(workspaceRoot.length + 1) : file
}

for (const [file, data] of entries) {
  files.push({ file, data })
  const pkg = packageOf(file)
  if (!byPackage.has(pkg)) {
    byPackage.set(pkg, {})
    for (const m of METRICS) byPackage.get(pkg)[m] = { total: 0, covered: 0 }
  }
  for (const m of METRICS) {
    byPackage.get(pkg)[m].total += data[m].total
    byPackage.get(pkg)[m].covered += data[m].covered
  }
}

const packages = [...byPackage.entries()]
  .map(([name, counts]) => ({ name, counts }))
  .sort(
    (a, b) =>
      pct(b.counts.statements.covered, b.counts.statements.total) -
      pct(a.counts.statements.covered, a.counts.statements.total),
  )

const lines = []
lines.push('## Code Coverage')
lines.push('')
lines.push(`| Scope | Statements | Branches | Functions | Lines |`)
lines.push(`| --- | --- | --- | --- | --- |`)
lines.push(
  `| **Total** | ${METRICS.map((m) => metricCell(summary.total[m])).join(' | ')} |`,
)
for (const p of packages) {
  lines.push(
    `| \`${p.name}\` | ${METRICS.map((m) => metricCell(p.counts[m])).join(' | ')} |`,
  )
}

const worstFiles = files
  .map((f) => ({
    file: f.file,
    pct: pct(f.data.statements.covered, f.data.statements.total),
    total: f.data.statements.total,
    covered: f.data.statements.covered,
  }))
  .filter((f) => f.total > 0)
  .sort((a, b) => a.pct - b.pct)
  .slice(0, TOP_FILES)

if (worstFiles.length > 0) {
  lines.push('')
  lines.push(`### Files with lowest statement coverage`)
  lines.push('')
  lines.push(`| File | Package | Statements |`)
  lines.push(`| --- | --- | --- |`)
  for (const f of worstFiles) {
    lines.push(
      `| \`${displayPath(f.file)}\` | \`${packageOf(f.file)}\` | ${f.pct.toFixed(1)}% (${f.covered}/${f.total}) |`,
    )
  }
}

const markdown = lines.join('\n')
const summaryFile = process.env.GITHUB_STEP_SUMMARY

if (summaryFile) {
  appendFileSync(summaryFile, `\n${markdown}\n`)
  console.log('Coverage summary appended to GITHUB_STEP_SUMMARY')
} else {
  console.log(markdown)
}
