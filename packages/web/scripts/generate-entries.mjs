import { readFileSync, writeFileSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, '..')

const { pages } = JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf-8'))
const template = readFileSync(resolve(__dirname, 'template.html'), 'utf-8')

for (const entry of Object.keys(pages)) {
  const { theme } = pages[entry]
  const html = template.replaceAll('{{THEME}}', theme)
  writeFileSync(resolve(root, `${entry}.html`), html)
}
