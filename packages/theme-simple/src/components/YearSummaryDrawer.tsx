/** YearSummaryDrawer — pure SVG year summary poster.
 *  Faithfully reproduces running_page's year_summary_YYYY.svg.
 *  Stats + 12-column dot matrix + footer. */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { useSimpleStore } from '../store'

interface YearSummaryDrawerProps {
  year: number
  activities: Activity[]
}

function dotColor(dist: number): string {
  if (dist === 0) return '#555555'
  if (dist < 1000) return '#546166'
  if (dist < 2000) return '#536e77'
  if (dist < 4000) return '#518799'
  if (dist < 6000) return '#5093aa'
  if (dist < 10000) return '#4dc9f3'
  return '#FFFF00'
}

function formatPace(avgSpeed: number): string {
  const paceMinPerKm = 1000 / (avgSpeed * 60)
  const paceMin = Math.floor(paceMinPerKm)
  const paceSec = Math.round((paceMinPerKm - paceMin) * 60)
  return `${paceMin}'${String(paceSec).padStart(2, '"')}`
}

const COL_X = [85.4, 94.25, 103.08, 111.92, 120.75, 129.58, 138.42, 147.25, 156.08, 164.92, 173.75, 182.58]
const DAY_START_Y = 17.42
const DAY_STEP = 8.84
const DOT_R = 3.3125

export function YearSummaryDrawer({ year, activities }: YearSummaryDrawerProps) {
  const colorScheme = useSimpleStore((s) => s.colorScheme)
  const isDark = colorScheme === 'dark'

  const bg = isDark ? '#222222' : '#f0f0f0'
  const dim = isDark ? '#555555' : '#888888'
  const bright = isDark ? '#FFFFFF' : '#333333'

  const data = useMemo(() => {
    const acts = activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)
    let totalDist = 0,
      totalTime = 0
    let totalPaceDist = 0,
      totalPaceTime = 0,
      longest = 0,
      runCount = 0
    const daySet = new Set<string>()
    const dates: string[] = []

    for (const a of acts) {
      totalDist += a.distance ?? 0
      totalTime += a.moving_time ?? 0
      if (a.average_speed && a.average_speed > 0) {
        totalPaceDist += a.distance ?? 0
        totalPaceTime += (a.distance ?? 0) / a.average_speed
      }
      if ((a.distance ?? 0) > longest) longest = a.distance ?? 0
      runCount++
      const dayKey = a.start_date!.slice(0, 10)
      if (!daySet.has(dayKey)) {
        daySet.add(dayKey)
        dates.push(dayKey)
      }
    }

    dates.sort()
    let streak = 0,
      maxStreak = 0,
      current = 1
    for (let i = 1; i < dates.length; i++) {
      const diff = (new Date(dates[i]).getTime() - new Date(dates[i - 1]).getTime()) / 86400000
      if (Math.round(diff) === 1) {
        current++
        if (current > maxStreak) maxStreak = current
      } else current = 1
    }
    streak = maxStreak > 0 ? maxStreak : dates.length > 0 ? 1 : 0

    const pace = totalPaceTime > 0 ? formatPace(totalPaceDist / totalPaceTime) : '--'
    const totalDays = Math.round(
      (new Date(year, 11, 31).getTime() - new Date(Math.min(...acts.map((a) => new Date(a.start_date!).getTime()), Date.now())).getTime()) /
        86400000,
    )
    const runningDays = Math.max(0, totalDays)

    // Dot matrix
    const dayDist = new Map<string, number>()
    for (const a of acts) {
      const dt = new Date(a.start_date!)
      const key = `${dt.getMonth() + 1}-${dt.getDate()}`
      dayDist.set(key, (dayDist.get(key) ?? 0) + (a.distance ?? 0))
    }

    const monthDots = COL_X.map((cx, m) => {
      const daysInMonth = new Date(year, m + 1, 0).getDate()
      return Array.from({ length: daysInMonth }, (_, d) => {
        const dist = dayDist.get(`${m + 1}-${d + 1}`) ?? 0
        return { cx, cy: DAY_START_Y + d * DAY_STEP, color: dotColor(dist), title: `${m + 1}/${d + 1}: ${(dist / 1000).toFixed(1)}km` }
      })
    })

    return { runCount, totalDist, pace, streak, totalTime, longest, runningDays, monthDots }
  }, [year, activities])

  return (
    <svg
      viewBox="0 0 200 300"
      xmlns="http://www.w3.org/2000/svg"
      style={{ width: '100%', height: 'auto', maxWidth: 300 }}
      role="img"
      aria-label={`Year summary for ${year}`}
    >
      <rect width={200} height={300} fill={bg} />
      <text x={11} y={19} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        Running for {data.runningDays} Days
      </text>

      <text x={11} y={39} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        Races
      </text>
      <text x={11} y={59} fill={bright} style={{ fontSize: 8, fontFamily: 'Arial' }}>
        0
      </text>
      <text x={23} y={59} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        0
      </text>

      <text x={11} y={97} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        Stats
      </text>

      {/* Distance */}
      <text x={11} y={103} fill={dim} style={{ fontSize: 5, fontFamily: 'Arial' }}>
        Distance
      </text>
      <text x={11} y={114} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        {(data.totalDist / 1000).toFixed(0)}
      </text>
      <text x={33} y={114} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        km
      </text>

      {/* Runs */}
      <text x={55} y={103} fill={dim} style={{ fontSize: 5, fontFamily: 'Arial' }}>
        Runs
      </text>
      <text x={55} y={114} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        {data.runCount}
      </text>

      {/* Avg Pace */}
      <text x={11} y={131} fill={dim} style={{ fontSize: 5, fontFamily: 'Arial' }}>
        Avg Pace
      </text>
      <text x={11} y={142} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        {data.pace}
      </text>

      {/* Streak */}
      <text x={55} y={131} fill={dim} style={{ fontSize: 5, fontFamily: 'Arial' }}>
        Streak
      </text>
      <text x={55} y={142} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        {data.streak}
      </text>
      <text x={73} y={142} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        d
      </text>

      {/* Time */}
      <text x={11} y={159} fill={dim} style={{ fontSize: 5, fontFamily: 'Arial' }}>
        Time
      </text>
      <text x={11} y={170} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        {Math.round(data.totalTime / 3600)}
      </text>
      <text x={29} y={170} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        h
      </text>

      {/* Longest */}
      <text x={55} y={159} fill={dim} style={{ fontSize: 5, fontFamily: 'Arial' }}>
        Longest
      </text>
      <text x={55} y={170} fill={bright} style={{ fontSize: 10, fontFamily: 'Arial', fontWeight: 'bold' }}>
        {(data.longest / 1000).toFixed(1)}
      </text>

      {/* Dot matrix */}
      {data.monthDots.map((dots) =>
        dots.map((dot) => (
          <circle key={`${dot.cx}-${dot.cy}`} cx={dot.cx} cy={dot.cy} r={DOT_R} fill={dot.color}>
            <title>{dot.title}</title>
          </circle>
        )),
      )}

      {/* Footer */}
      <text x={11} y={252} fill={dim} style={{ fontSize: 6, fontFamily: 'Arial' }}>
        Runner
      </text>
      <text x={11} y={262} fill={bright} style={{ fontSize: 8, fontFamily: 'Arial', fontWeight: 'bold' }}>
        Workouts
      </text>
      <text x={11} y={285} fill={dim} style={{ fontSize: 7, fontFamily: 'Arial' }}>
        running_page/{year}
      </text>
    </svg>
  )
}
