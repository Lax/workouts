import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { resolve } from 'path'

const root = resolve(import.meta.dirname, '..')
const config = JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf-8'))
const entries = config.entries ?? { index: config.theme }
const htmlTemplate = readFileSync(resolve(import.meta.dirname, 'template.html'), 'utf-8')

mkdirSync(resolve(root, 'src/entries'), { recursive: true })

for (const key of Object.keys(entries)) {
  const themeId = entries[key]

  const html = htmlTemplate.replace('{{ENTRY}}', `./src/entries/${key}.tsx`).replace('{{THEME}}', themeId)
  writeFileSync(resolve(root, `${key}.html`), html)

  const shim = `import { bootstrap } from '@workouts/core'
import theme from '@workouts/theme-${themeId}'
import config from '../../config.json'

bootstrap(config, { theme })
`
  writeFileSync(resolve(root, `src/entries/${key}.tsx`), shim)
}
