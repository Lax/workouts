# Route Animation — Requirement

## What

Add a progressive polyline drawing animation (trail effect) to the map in theme-simple. When a user selects a single activity (detail panel opens), that activity's route polyline draws itself progressively from start point to end point over a short duration.

Non-selected activities on the map must draw immediately (static), as they do today.

## Why

Feature parity with running_page (`RouteAnimator`). Visual feedback reinforces the spatial progression of a route — the user sees where the activity started and how it unfolded. Makes the detail-view experience more engaging without adding UI complexity.

## Scope

**In scope:**
- theme-simple only (not theme-overview, not theme-hello-world)
- Single-activity mode: when `mapActivities.length === 1`
- Animation uses `requestAnimationFrame`, progressively reveals polyline points
- Configurable speed/duration (default ~2–4s for a full-length route)
- Abort/restart when selected activity changes mid-animation
- Works for all sport categories (run, ride, hike, etc.)
- Color and opacity follow existing `activityColor`/year-fade rules — same as static polylines
- Hover interaction (tooltip, highlight) still works on the animated polyline

**Out of scope:**
- Animation for multi-activity map views (overview with 200+ activities)
- Animation in theme-overview (different map/detail UX)
- Animation on first load / initial fitBounds
- Running_page's exact `RouteAnimator` API — not a port, just the same concept
- GSAP or any third-party animation library
- SVG export animation

## Done Criteria

All conditions must be verifiable via code inspection + manual test:

1. When `mapActivities` has exactly 1 Activity with a non-null `summary_polyline`, the polyline draws progressively from first point to last point over ~2–4 seconds (adjustable).
2. When `mapActivities` has more than 1 Activity, all polylines render instantly (static) — no animation.
3. When `mapActivities` transitions from 1 Activity to a different 1 Activity (user clicks another row while detail is open), any in-progress animation cancels immediately and the new activity's polyline starts animating from scratch.
4. When `mapActivities` transitions from 1 Activity to 0 (user closes detail), animation stops immediately.
5. A 2-point polyline animates trivially fast (or completes instantly) — no crash or visible glitch.
6. A null/empty `summary_polyline` produces no polyline and no error.
7. Hover highlight (`hoveredActivityId`) works on the animated polyline: hover toggles weight/color/opacity on visible segment.
8. Existing PolylineOptions (`colorMode`, `dashLines`, `showMarkers`) continue working for animated lines.
9. Theme toggle (light/dark) or color mode toggle (type/speed) while animation is active resets polyline rendering with correct new colors (same behavior as current static rebuild).
10. TypeScript compiles without errors.

## Edge Cases

1. **Activity switch mid-animation**: User clicks a different table row while animation is in progress. The in-progress animation must cancel, and the new activity's polyline must start animating from scratch. No stale polylines, no overlap of old + new.
2. **Multi-point vs 2-point polyline**: Activities with minimal GPS data (e.g., indoor runs with only start/end points) result in a 2-point decoded polyline. Animation must handle trivially short sequences without visual glitch or division-by-zero.
3. **200+ activities overview**: When no activity is selected, `mapActivities` can contain hundreds of polylines. None of these should animate. The animation logic must be strictly gated by `activities.length === 1`.
4. **Component unmount mid-animation**: If the map component unmounts while `requestAnimationFrame` is pending, the callback must be a no-op (use a ref-guard or cleanup in `useEffect` return).
5. **Hover interaction during animation**: While the polyline is progressively drawing, the user may hover over it. The visible portion must respond to hover highlighting correctly (tooltip should show on visible points, not on yet-unrevealed points).
6. **Race condition on fast double-click**: Rapidly toggling the same activity on/off must not leave orphaned polyline layers on the map.

## Constraints

- Must not introduce new npm dependencies.
- Must not modify `@workouts/shared` package.
- Must not break existing map behavior in theme-overview or theme-hello-world.
- Animation only for single-activity mode (`mapActivities.length === 1`).
- Must use native `requestAnimationFrame` — no GSAP, Framer Motion, etc.
- Changes must be confined to `packages/plugin-map/` and `packages/theme-simple/`.
- TypeScript strict mode compatible.
- No changes to the Ruby backend or the JSON export schema.
