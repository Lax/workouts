import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { resolve } from 'path'

const root = resolve(import.meta.dirname, '..')
const config = JSON.parse(readFileSync(resolve(root, 'config.json'), 'utf-8'))
const entries = config.entries ?? { index: config.theme }
const htmlTemplate = readFileSync(resolve(import.meta.dirname, 'template.html'), 'utf-8')

const PROJECT_NAME = 'GitFit'

function humanizeTheme(id) {
  return id.split('-').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

// 站点字段两级解析：themes.<themeId>.site.<field> > site.<field>（统一规则，非 title 专属）
function resolveSiteField(config, themeId, field) {
  return config.themes?.[themeId]?.site?.[field] ?? config.site?.[field]
}

function resolveTitle(config, themeId) {
  return resolveSiteField(config, themeId, 'title') ?? `${humanizeTheme(themeId)} - ${PROJECT_NAME}`
}

mkdirSync(resolve(root, 'src/entries'), { recursive: true })

for (const key of Object.keys(entries)) {
  const themeId = entries[key]

  const html = htmlTemplate
    .replace('{{ENTRY}}', `./src/entries/${key}.tsx`)
    .replace('{{THEME}}', themeId)
    .replace('{{TITLE}}', resolveTitle(config, themeId))
  writeFileSync(resolve(root, `${key}.html`), html)

  const defaultPalette = themeId === 'simple' ? 'warm' : 'cool'
  const configured = config.site?.palette
  const family = ['warm', 'cool', 'mono'].includes(configured) ? configured : defaultPalette

  const shim = `import { bootstrap } from '@git-fit/core'
import { applyFamily, schemeFor } from '@git-fit/shared'
import theme from '@git-fit/theme-${themeId}'
import config from '../../config.json'

applyFamily(document.documentElement, '${family}', schemeFor())

bootstrap(config, { theme })
`
  writeFileSync(resolve(root, `src/entries/${key}.tsx`), shim)
}
