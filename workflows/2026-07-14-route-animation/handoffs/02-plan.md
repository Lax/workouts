# Route Animation — Plan

## File Change List

| File | Action | Why |
|---|---|---|
| `packages/plugin-map/src/useMapPolylines.ts` | Modify | Add `animate` option + rAF animation logic |
| `packages/plugin-map/src/PanelMap.tsx` | Modify | Thread `animate` prop to PolylineOptions |
| `packages/theme-simple/src/components/SimpleMap.tsx` | Modify | Thread `animate` prop to PanelMap |
| `packages/theme-simple/src/Layout.tsx` | Modify | Compute `animate={!!selectedActivity}` |
| `packages/web/tests/map.test.tsx` | Modify | Add `setLatLngs` to mock + animation test cases |
| `packages/web/tests/polyline.test.ts` | No change | decodePolyline already tested |

No new files. No new deps. No changes to: `MapView.tsx` (theme-overview), `shared`, Ruby backend, JSON schema.

---

## Architecture Decision: Inline rAF in existing useEffect

**Chosen:** Add `animate` boolean to `PolylineOptions` (default `false`), implement animation branch inside existing main `useEffect` in `useMapPolylines.ts`.

**Rejected alternatives:**

| Alternative | Rejected because |
|---|---|
| New `useAnimatedPolyline` hook | PFC violation. One consumer only. Would duplicate cleanup/layer logic |
| Animation in theme-simple | DRY violation. Would need access to `L.polyline` from outside plugin-map |
| Third-party animation lib | YAGNI + constraint. rAF sufficient for ~60 lines of logic |

**Rationale:**
- `useEffect` already handles create/cleanup lifecycle on activity/colorMode changes
- `polylinesRef` already stores active polylines for hover highlight
- `animate` default `false` = zero risk for theme-overview/theme-hello-world
- Animation branch sits cleanly inside the existing for-loop: `if (options.animate && activities.length === 1) { ... } else { ... }`

---

## Implementation Steps (order by dependency)

### Step 1: PolylineOptions interface

`useMapPolylines.ts:8-17` — add field:
```ts
export interface PolylineOptions {
  // ... existing fields ...
  animate?: boolean  // new, default false
}
```

`useMapPolylines.ts:24` — destructure:
```ts
const { colorMode, hoveredActivityId = null, maxLines = 500, fitOnChange = true, dashLines = false, showMarkers = false, onActivityClick, onActivityHover, animate = false } = options
```

### Step 2: Thread through component chain

`PanelMap.tsx` — add `animate?: boolean` to `PanelMapProps`, set in opts object:
```ts
const opts: PolylineOptions = { colorMode, hoveredActivityId, maxLines, fitOnChange: true, dashLines, animate, ... }
```

`SimpleMap.tsx` — add `animate?: boolean` to `SimpleMapProps`, pass thru:
```ts
<PanelMap ... animate={animate} />
```

`Layout.tsx` — compute and pass:
```ts
<SimpleMap animate={!!selectedActivity} ... />
```

### Step 3: Animation branch in main useEffect

Inside the existing for-loop in `useMapPolylines.ts:38`, after decoding points:

```ts
if (animate && activities.length === 1 && points.length > 2) {
  // --- Animated path ---
  const initialPoints = [points[0], points[1]]
  const line = L.polyline(initialPoints, { /* same as static */ }).addTo(mapInst)
  // bind events, tooltip, store in ref (same as static)
  // store full points list for animation
  const animPoints = points
  const startTime = performance.now()
  const duration = Math.min(4000, points.length * 20) // scale: ~20ms/point
  let frameId: number

  const animRef = { frameId: 0, startTime: 0 } // stored outside closure

  function step(timestamp: number) {
    if (!animRef.startTime) animRef.startTime = timestamp
    const elapsed = timestamp - animRef.startTime
    const progress = Math.min(elapsed / duration, 1)
    const count = Math.max(2, Math.floor(points.length * progress))
    line.setLatLngs(points.slice(0, count))
    if (progress < 1) {
      animRef.frameId = requestAnimationFrame(step)
    }
  }
  animRef.frameId = requestAnimationFrame(step)

  // Store frameId for cleanup — use a Set or Map to track animation state
  // e.g. animFramesRef.current.set(a.run_id, animRef)
} else {
  // --- Existing static path (unchanged) ---
}
```

Need: `animFramesRef` — `useRef<Map<string, { frameId: number; startTime: number }>>(new Map())` to track active animations for cleanup.

### Step 4: Cleanup

In `useEffect` return (currently implicit — `useEffect` has no explicit return but cleanup happens via the top-of-effect removeLayer loop):

```
// Top of effect (before the for-loop):
for (const [, line] of polylinesRef.current) mapInst.removeLayer(line)
polylinesRef.current.clear()
// NEW: cancel all active animations
for (const [, anim] of animFramesRef.current) cancelAnimationFrame(anim.frameId)
animFramesRef.current.clear()
```

This ensures any in-progress animation is cancelled when deps change — covers:
- Activity switch → `activities` changes → effect re-runs → cancel old, start new ✅
- Theme/colorMode toggle → same ✅
- Component unmount → effect cleanup runs → cancel ✅

### Step 5: Mock update

`map.test.tsx:7-13` — add to `MockPolyline`:
```ts
class MockPolyline {
  addTo = vi.fn().mockReturnThis()
  setStyle = vi.fn().mockReturnThis()
  bringToFront = vi.fn()
  bindTooltip = vi.fn().mockReturnThis()
  on = vi.fn()
  setLatLngs = vi.fn().mockReturnThis()  // NEW
}
```

Also need to mock `requestAnimationFrame` and `cancelAnimationFrame` in tests:
```ts
// per-test or global — fire immediately
vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
  cb(performance.now())
  return 1
})
vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {})
```

### Step 6: Test cases

Add to `map.test.tsx`:

1. **Renders static when animate=false** (existing behavior, reinforce)
2. **Animates single activity when animate=true** — mock rAF fires immediately, verify `setLatLngs` called
3. **No animation when activities.length > 1 even with animate=true** — verify `setLatLngs` not called beyond initial render
4. **Restarts on activity switch** — render with activity A (animate=true), re-render with activity B, verify old animation cancelled + new one started
5. **Handles null summary_polyline** — no crash, no polyline
6. **Handles 2-point polyline** — renders instantly (no rAF frame needed)

---

## Test Strategy

| Level | Scope | Method |
|---|---|---|
| Unit | `useMapPolylines` animation logic | Vitest + jsdom + Leaflet mock. Mock rAF to fire immediately. Verify `setLatLngs` call count/args |
| Unit | PolylineOptions default `animate=false` | Existing tests pass unchanged |
| Unit | 2-point polyline edge case | Points.length≤2 → instant render, no rAF |
| Manual | Hover on animated polyline | Open browser, select activity, hover during animation, verify highlight/tooltip |
| Manual | Theme toggle mid-animation | Toggle dark/light, verify animation restarts with new colors |
| Manual | Fast double-click toggling | Rapidly click rows, verify no orphan polylines |

---

## Diff Estimate

`useMapPolylines.ts`: ~40 lines added (interface + branch + animation loop + ref + cleanup)  
`PanelMap.tsx`: +1 line prop + 1 char in opts  
`SimpleMap.tsx`: +1 line prop + 1 char in JSX  
`Layout.tsx`: +1 char in JSX (`animate={!!selectedActivity}`)  
`map.test.tsx`: ~50 lines mock + tests

Total: ~55 lines new code, ~50 lines test.

---

## Verification Checklist

- [ ] `animate=false` (default) — all existing polylines behavior identical
- [ ] `animate=true, length=1` — progressive reveal via rAF
- [ ] `animate=true, length>1` — static (gate)
- [ ] Activity switch mid-animation — cancel + restart
- [ ] 2-point polyline — instant render
- [ ] null polyline — no render, no error
- [ ] Theme/colorMode toggle — animation restarts with correct colors
- [ ] Hover on animated polyline — highlight visible segment
- [ ] Component unmount — no pending rAF callback
- [ ] Existing tests pass (`bundle exec rspec` + `npx vitest run`)
- [ ] `npx tsc --noEmit` — no type errors
