import { readFileSync, readdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const dist = join(__dirname, '..', 'dist', 'assets')
let ok = true

for (const f of readdirSync(dist).filter(f => f.endsWith('.js'))) {
  try {
    new Function(readFileSync(join(dist, f), 'utf8'))()
  } catch (e) {
    if (e instanceof ReferenceError && e.message.includes('is not defined')) {
      continue
    }
    if (e.message?.includes('effect_orphan')) {
      console.error(`::error::${f}: effect_orphan — $effect outside component context`)
      ok = false
    }
  }
}

if (!ok) process.exit(1)
console.log('OK: bundle smoke test passed')
