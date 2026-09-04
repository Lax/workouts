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

// workouts#47 (Activity Snapshot): ytd_goal_km is an opt-in display value added
// to config.json. Only flag a mismatch when BOTH sides define it and differ —
// a stale .git-fit-web/config.json build artifact missing the new key must not
// deadlock the local dev tool (one side undefined = no mismatch).
const aGoal = aProfile.ytd_goal_km
const bGoal = bProfile.ytd_goal_km
if (aGoal !== undefined && bGoal !== undefined && aGoal !== bGoal) {
  console.error('Config mismatch: config.json and .git-fit-web/config.json have different profile.ytd_goal_km')
  console.error(`  Fix: align profile.ytd_goal_km in both files (e.g. \`npm run build:ui\` to regenerate .git-fit-web/config.json, or edit it to ${aGoal})`)
  process.exit(1)
}
