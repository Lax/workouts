# Route Animation — Development

## Status
- Phase: Development
- Status: completed
- Attempt: 1

## Decisions
- Animation logic inlined in `useMapPolylines`'s existing `useEffect`, not extracted to separate hook (PFC)
- rAF with `performance.now()` for timing, not frame counting (smooth on variable refresh rates)
- Duration: `min(4000ms, max(1000ms, points.length * 25ms))` — scales with route complexity
- `animate` default `false` — zero risk to theme-overview
- Gate: `animate && activities.length === 1` — only single-activity mode
- 2-point polylines skip animation (static render in else branch)

## Artifacts
- `packages/plugin-map/src/useMapPolylines.ts` — `animate` option in PolylineOptions, animation branch inside main useEffect, `animFramesRef` for rAF cleanup
- `packages/plugin-map/src/MapView.tsx` — add `animate` prop, pass to polylineOptions
- `packages/plugin-map/src/PanelMap.tsx` — add `animate` prop, pass to polylineOptions
- `packages/theme-simple/src/components/SimpleMap.tsx` — add `animate` prop, pass to PanelMap
- `packages/theme-simple/src/Layout.tsx` — pass `animate={!!selectedActivity}` to SimpleMap
- `packages/web/tests/map.test.tsx` — add `setLatLngs` to MockPolyline, add 6 animation tests

## Consistency Check
- Plan match: yes
- Req match: yes
- Done Criteria checked:
  1. ✅ Single-activity animation (animate=true → initial 2 points, animate=false → all points)
  2. ✅ Multi-activity static (gate: length===1)
  3. ✅ Mid-switch cancel (effect cleanup cancels rAF via animFramesRef)
  4. ✅ Close stop (cleanup runs on empty activities)
  5. ✅ 2-point polyline renders instantly (else branch)
  6. ✅ null polyline no error (skip if !encoded)
  7. ✅ Hover works (hover effect separate useEffect, polylinesRef populated)
  8. ✅ dashLines, showMarkers work (shared lineStyle before branch)
  9. ✅ Color mode toggle resets animation (colorMode in deps → cleanup + restart)
  10. ✅ TypeScript no errors (build passes)

## Verification
- `npx vitest run`: 71/71 passed
- `npx biome ci .`: clean
- `npx vite build`: clean
- `npx tsc --noEmit`: only pre-existing --jsx errors
