import { readFileSync, writeFileSync } from 'fs'
import { resolve } from 'path'

const root = resolve(import.meta.dirname, '..')
const config = JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf-8'))
const entries = config.entries ?? { index: config.theme }
const template = readFileSync(resolve(import.meta.dirname, 'template.html'), 'utf-8')

for (const key of Object.keys(entries)) {
  const html = template.replace('{{ENTRY}}', `./src/entries/${key}.tsx`).replace('{{THEME}}', entries[key])
  writeFileSync(resolve(root, `${key}.html`), html)
}
