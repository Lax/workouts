# Route Animation — Release

## Status
- Phase: Release
- Status: completed
- Attempt: 1

## Change Summary
Route animation for theme-simple's map. When user selects a single activity (detail panel opens), its route polyline draws progressively from start to finish over ~1-4 seconds using requestAnimationFrame.

## Affected Files
- `packages/plugin-map/src/useMapPolylines.ts` — add `animate` option, rAF animation branch, `animFramesRef` cleanup
- `packages/plugin-map/src/MapView.tsx` — thread `animate` prop
- `packages/plugin-map/src/PanelMap.tsx` — thread `animate` prop
- `packages/theme-simple/src/components/SimpleMap.tsx` — thread `animate` prop
- `packages/theme-simple/src/Layout.tsx` — compute `animate={!!selectedActivity}`
- `packages/web/tests/map.test.tsx` — 6 new animation tests

## Test Results
- Vitest: 72/72 passed (7 files)
- Biome: clean
- Build: clean
- CI (GitHub Actions): success

## Known Issues
- None

## Rollback Plan
Revert `a529f5e`:
```
git revert a529f5e && git push
```
