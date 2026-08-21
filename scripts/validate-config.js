const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..')

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(path.join(root, filePath), 'utf8'))
}

const a = readJson('config.json')
const b = readJson('.git-fit-web/config.json')

const aProfile = a.profile || {}
const bProfile = b.profile || {}

if (aProfile.birthYear !== bProfile.birthYear || aProfile.birthMonth !== bProfile.birthMonth) {
  console.error('Config mismatch: config.json and .git-fit-web/config.json have different profile.birthYear/birthMonth')
  console.error('  Fix: ensure both files have the same profile values.')
  process.exit(1)
}
