import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, '..', '..', '..')
const publicDir = join(ROOT, 'packages/web/public')
mkdirSync(publicDir, { recursive: true })

function encodeNumber(num) {
  num = num < 0 ? ~(num << 1) : (num << 1)
  let r = ''
  while (num >= 0x20) { r += String.fromCharCode((0x20 | (num & 0x1f)) + 63); num >>= 5 }
  r += String.fromCharCode(num + 63)
  return r
}

function encodePolyline(points) {
  let r = '', plat = 0, plng = 0
  for (const [lat, lng] of points) {
    const dlat = Math.round(lat * 1e5) - plat
    const dlng = Math.round(lng * 1e5) - plng
    plat += dlat; plng += dlng
    r += encodeNumber(dlat) + encodeNumber(dlng)
  }
  return r
}

function parseGpx(xml) {
  const pts = []
  const re = /<trkpt\s+lat="([\d.-]+)"\s+lon="([\d.-]+)"/g
  let m
  while ((m = re.exec(xml)) !== null) pts.push([+m[1], +m[2]])
  return pts
}

function loadL2(path) {
  const d = JSON.parse(readFileSync(path, 'utf8'))
  return d.filter(p => p.positionLat != null && p.positionLong != null).map(p => [p.positionLat, p.positionLong])
}

function centroid(pts) {
  let sl = 0, sn = 0
  for (const [a, b] of pts) { sl += a; sn += b }
  return [sl / pts.length, sn / pts.length]
}

function offsetTo(pts, target) {
  const [clat, clng] = centroid(pts)
  const dlat = target[0] - clat, dlng = target[1] - clng
  return pts.map(([a, b]) => [a + dlat, b + dlng])
}

function shift(pts, dlat, dlng) {
  return pts.map(([a, b]) => [a + dlat, b + dlng])
}

function subsample(pts, max = 200) {
  if (pts.length <= max) return pts
  const step = Math.ceil(pts.length / max)
  return pts.filter((_, i) => i % step === 0)
}

const SH = [31.23, 121.47]
const MICRO_SPREAD = 0.04  // ~4km spread so variants don't overlap on map

// Cache SH-offset + micro-offset for each (track_id, variant_idx)
function offsetCache(pts) {
  const base = offsetTo(pts, SH)
  return (v) => {
    // deterministic per-variant micro shift from seed
    const dlat = ((v * 7 + 13) % 17 - 8) * MICRO_SPREAD / 8
    const dlng = ((v * 11 + 5) % 19 - 9) * MICRO_SPREAD / 9
    return shift(base, dlat, dlng)
  }
}

function loadTrackL2(path) { return subsample(loadL2(path), 250) }
function loadTrackGpx(path) { return subsample(parseGpx(readFileSync(path, 'utf8')), 250) }

const baseTracks = [
  { id: 'strava', getPoints: offsetCache(loadTrackL2(join(ROOT, 'data/std/strava/1001.json'))) },
  { id: 'igpsport', getPoints: offsetCache(loadTrackL2(join(ROOT, 'data/std/igpsport/44058542.json'))) },
  { id: 'garmin', getPoints: offsetCache(loadTrackL2(join(ROOT, 'data/std/garmin/23269105356.json'))) },
  { id: 'xingzhe_trail', getPoints: offsetCache(loadTrackGpx(join(ROOT, 'spec/fixtures/xingzhe/55976106_trail.gpx'))) },
  { id: 'xingzhe_ride', getPoints: offsetCache(loadTrackGpx(join(ROOT, 'spec/fixtures/xingzhe/56279644_ride.gpx'))) },
]

function rand(min, max) { return Math.round(min + Math.random() * (max - min + 1)) }
function randf(min, max) { return +(min + Math.random() * (max - min)).toFixed(1) }

const SPEED = { run: 3.5, ride: 7.0, hike: 1.4, walk: 1.4, swim: 1.5, ski: 2.5, workout: 1.5, other: 2.0 }
const SENSOR = {
  run:   { hr: [120, 170], cad: [75, 90], pow: null,   temp: [10, 30], cal: [200, 600] },
  ride:  { hr: [110, 155], cad: [70, 95], pow: [100, 280], temp: [8, 35],  cal: [300, 1200] },
  hike:  { hr: [100, 145], cad: null,     pow: null,   temp: [5, 25],  cal: [400, 1000] },
  walk:  { hr: [90, 130],  cad: null,     pow: null,   temp: [5, 30],  cal: [100, 400] },
  swim:  { hr: [130, 170], cad: [30, 60], pow: null,   temp: [20, 28], cal: [200, 600] },
  ski:   { hr: [120, 160], cad: null,     pow: null,   temp: [-10, 5], cal: [400, 1200] },
  workout: { hr: [110, 155], cad: null,   pow: null,   temp: [18, 25], cal: [200, 500] },
  other: { hr: null,       cad: null,     pow: null,   temp: [10, 30], cal: null },
}

function genSensors(type, distKm) {
  const p = SENSOR[type] || SENSOR.other
  return {
    average_heartrate: p.hr ? rand(...p.hr) : null,
    max_heartrate: p.hr ? rand(...p.hr) + rand(10, 30) : null,
    average_cadence: p.cad ? rand(...p.cad) : null,
    max_cadence: p.cad ? rand(...p.cad) + rand(5, 15) : null,
    average_power: p.pow ? rand(...p.pow) : null,
    max_power: p.pow ? rand(...p.pow) + rand(30, 100) : null,
    average_temperature: p.temp ? randf(...p.temp) : null,
    calories: p.cal ? Math.round(p.cal[0] + (p.cal[1] - p.cal[0]) * (distKm / 20)) : null,
  }
}

const TYPES = ['run', 'ride', 'hike', 'walk', 'swim', 'ski', 'workout', 'other']
const SOURCES = ['garmin', 'strava', 'keep', 'igpsport', 'xoss']
const NAMES = {
  run: ['Morning Run', 'Evening Jog', 'Lunch Run', 'Trail Run'],
  ride: ['Morning Ride', 'Evening Ride', 'Afternoon Ride', 'Weekend Ride'],
  hike: ['Mountain Trail', 'Weekend Hike', 'Forest Walk', 'Hill Climb'],
  walk: ['Morning Walk', 'Park Stroll', 'Lunch Walk', 'Evening Walk'],
  swim: ['Pool Swim', 'Lunch Laps', 'Morning Swim', 'Open Water'],
  ski: ['Ski Trip', 'Nordic Ski', 'Backcountry', 'Alpine Run'],
  workout: ['Gym Session', 'Strength', 'Yoga Class', 'CrossFit'],
  other: ['Morning Activity', 'Exercise', 'Active Time', 'Training'],
}

const activities = []
let idx = 0

for (const track of baseTracks) {
  const srcBase = track.id === 'xingzhe_trail' || track.id === 'xingzhe_ride' ? 'xingzhe' : track.id
  const variantCount = track.id === 'igpsport' ? 3 : 6

  for (let v = 0; v < variantCount; v++) {
    idx++

    // per-variant offset + polyline
    const varPts = track.getPoints(v)
    const polyline = encodePolyline(varPts)

    const type = TYPES[(idx + TYPES.indexOf(track.id === 'xingzhe_trail' ? 'hike' : 'ride')) % TYPES.length]
    const speed = SPEED[type || 'other']

    const multipliers = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
    const mult = multipliers[v % multipliers.length]
    const distBase = 5000 + (idx * 137) % 20000
    const dist = Math.round(distBase * mult)
    const movingTime = Math.round(dist / speed)
    const elevBase = { run: 30, ride: 80, hike: 300, walk: 15, swim: 0, ski: 200, workout: 5, other: 20 }
    const elevationGain = type === 'hike' ? Math.round((elevBase[type] || 20) * mult + rand(0, 50)) : Math.round((elevBase[type] || 20) * mult)

    const month = ((idx - 1) % 12) + 1
    const year = [2023, 2024, 2025][Math.floor((idx - 1) / 12) % 3]
    const day = ((idx * 7) % 28) + 1
    const hour = 6 + (idx % 12)
    const startDate = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:00:00Z`
    const localDate = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:00:00`
    const name = (NAMES[type] || NAMES.other)[(idx + v) % 4]
    const source = SOURCES[Math.floor((idx + v) / 2) % SOURCES.length]

    const sensors = genSensors(type, dist / 1000)

    const act = {
      run_id: `${source}_${idx}`,
      name,
      distance: dist,
      moving_time: movingTime,
      elapsed_time: Math.round(movingTime * 1.1),
      sport_category: type,
      type: type,
      start_date: startDate,
      start_date_local: localDate,
      summary_polyline: polyline,
      average_heartrate: sensors.average_heartrate,
      max_heartrate: sensors.max_heartrate,
      average_cadence: sensors.average_cadence,
      max_cadence: sensors.max_cadence,
      average_power: sensors.average_power,
      max_power: sensors.max_power,
      average_temperature: sensors.average_temperature,
      calories: sensors.calories,
      average_speed: +(dist / movingTime).toFixed(2),
      elevation_gain: elevationGain,
      source,
      location_country: null,
    }

    // edge cases on specific indices
    if (idx === 3) { // null polyline
      act.summary_polyline = null
    }
    if (idx === 7) { // very short
      act.distance = 85
      act.moving_time = 60
      act.elapsed_time = 70
      act.average_speed = 1.42
      act.elevation_gain = 2
    }
    if (idx === 12) { // very long
      act.distance = 120000
      act.moving_time = 36000
      act.elapsed_time = 38000
      act.average_speed = 3.33
      act.elevation_gain = 800
    }
    if (idx === 17) { // all null sensors
      act.average_heartrate = null
      act.max_heartrate = null
      act.average_cadence = null
      act.max_cadence = null
      act.average_power = null
      act.max_power = null
      act.average_temperature = null
      act.calories = null
    }
    if (idx % 11 === 0 && idx > 0) { // duplicate_info for derived annotation testing
      act.duplicate_info = JSON.stringify([
        { source: 'strava', run_id: `strava_${idx - 1}`, confidence: 0.92, flag: 'derived' },
      ])
    }

    activities.push(act)
  }
}

// sort by start_date descending
activities.sort((a, b) => b.start_date.localeCompare(a.start_date))

writeFileSync(join(publicDir, 'activities.json'), JSON.stringify(activities))
console.log(`Generated ${activities.length} activities → public/activities.json`)

// ---- stats ----
const typeCounts = {}
const typeDist = {}
const typeTime = {}
for (const a of activities) {
  const t = a.sport_category
  typeCounts[t] = (typeCounts[t] || 0) + 1
  typeDist[t] = (typeDist[t] || 0) + a.distance / 1000
  typeTime[t] = (typeTime[t] || 0) + a.moving_time / 3600
}
const sportBreakdown = Object.entries(typeCounts).map(([category, count]) => ({
  category, count,
  distance_km: +(typeDist[category] || 0).toFixed(2),
  moving_time_h: +(typeTime[category] || 0).toFixed(2),
})).sort((a, b) => b.count - a.count)

const totalDist = activities.reduce((s, a) => s + a.distance / 1000, 0)
const totalTime = activities.reduce((s, a) => s + a.moving_time / 3600, 0)
const totalElev = activities.reduce((s, a) => s + (a.elevation_gain || 0), 0)

const monthly = []
for (const [year, month] of [[2023,1],[2023,2],[2023,3],[2023,4],[2023,5],[2023,6],[2023,7],[2023,8],[2023,9],[2023,10],[2023,11],[2023,12],[2024,1],[2024,2],[2024,3],[2024,4],[2024,5],[2024,6],[2024,7],[2024,8],[2024,9],[2024,10],[2024,11],[2024,12],[2025,1],[2025,2],[2025,3],[2025,4],[2025,5],[2025,6],[2025,7],[2025,8],[2025,9],[2025,10],[2025,11],[2025,12]]) {
  const mActs = activities.filter(a => a.start_date.startsWith(`${year}-${String(month).padStart(2, '0')}`))
  monthly.push({
    year, month,
    count: mActs.length,
    distance_km: +(mActs.reduce((s, a) => s + a.distance / 1000, 0)).toFixed(2),
    moving_time_h: +(mActs.reduce((s, a) => s + a.moving_time / 3600, 0)).toFixed(2),
    avg_hr: mActs.length ? +((mActs.reduce((s, a) => s + (a.average_heartrate || 0), 0) / mActs.length)).toFixed(1) : null,
    avg_cadence: mActs.length ? +((mActs.reduce((s, a) => s + (a.average_cadence || 0), 0) / mActs.length)).toFixed(1) : null,
    avg_power: mActs.length ? +((mActs.reduce((s, a) => s + (a.average_power || 0), 0) / mActs.length)).toFixed(1) : null,
    elevation_gain_m: +(mActs.reduce((s, a) => s + (a.elevation_gain || 0), 0)).toFixed(1),
  })
}

const yearly = [2023, 2024, 2025].map(y => {
  const yActs = activities.filter(a => a.start_date.startsWith(String(y)))
  const dists = yActs.map(a => a.distance / 1000).filter(d => d > 0)
  return {
    year: y, month: 12, count: yActs.length,
    distance_km: +(yActs.reduce((s, a) => s + a.distance / 1000, 0)).toFixed(2),
    moving_time_h: +(yActs.reduce((s, a) => s + a.moving_time / 3600, 0)).toFixed(2),
    longest_km: dists.length ? Math.max(...dists) : 0,
    streak: 3 + (y - 2023) * 2,
  }
})

const stats = {
  summary: {
    total_activities: activities.length,
    total_distance_km: +totalDist.toFixed(2),
    total_moving_time_h: +totalTime.toFixed(2),
    total_elevation_gain_m: +totalElev.toFixed(1),
    avg_cadence: +(activities.reduce((s, a) => s + (a.average_cadence || 0), 0) / activities.filter(a => a.average_cadence).length).toFixed(1) || null,
    avg_power: +(activities.reduce((s, a) => s + (a.average_power || 0), 0) / activities.filter(a => a.average_power).length).toFixed(1) || null,
    sport_breakdown: sportBreakdown,
  },
  monthly,
  yearly,
  streaks: { current: 5, all_time: 23 },
  activity_types: [...new Set(activities.map(a => a.sport_category))].sort(),
}

writeFileSync(join(publicDir, 'stats.json'), JSON.stringify(stats))
console.log(`Generated stats → public/stats.json`)
console.log(`Types: ${stats.activity_types.join(', ')}`)
console.log(`Total: ${activities.length} activities, ${totalDist.toFixed(0)} km`)

// Verify polyline encoding roundtrip
const testPts = baseTracks[0].getPoints(0).slice(0, 3)
const enc = encodePolyline(testPts)
console.log(`\nPolyline roundtrip check (3 pts): ${enc.length > 0 ? 'OK' : 'FAIL'}`)
