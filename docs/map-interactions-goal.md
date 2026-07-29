# Map Interactions — Unified Management

## Effects & Dependencies

MapView component (`packages/plugin-map/src/MapView.tsx`) manages 4 useEffect blocks:

| # | Effect | Deps | Triggered by | Zoom change | Animation |
|---|---|---|---|---|---|
| 1 | Init map | `[]` | Mount | `setView(30,110,4)` first time only | Leaflet default |
| 2 | Swap tile layer | `[tileUrl]` | Theme toggle (`colorScheme`), Lights toggle (`lightsOn`) | ❌ No | None (instant) |
| 3 | Draw polylines + fitBounds | `[activities, colorMode, maxLines]` | Filter/sort change, color mode toggle | ✅ Only when activity **content** changes | `fitBounds` default (0.25s) |
| 4 | Hover style | `[hoveredActivityId, colorMode]` | Hover on map/list | ❌ No | None (instant) |

### Effect 3 — fitBounds gating

`fittedRef` stores a **content digest** of the current activity set. `fitBounds` fires only when the digest changes, preventing unnecessary zoom on:
- Sort order toggle (same set, different order)
- Color mode toggle (`colorMode` in deps, but digest unchanged)

```ts
const actKey = fitBoundsKey(activities)  // sorted run_id join
if (fittedRef.current !== actKey) {
  map.fitBounds(...)
  fittedRef.current = actKey
}
```

## All Map Interactions

| Interaction | User action | Store mutation | MapView prop change | Effect fired | Zoom? |
|---|---|---|---|---|---|
| **Theme toggle** | Click 🌙/☀️ | `colorScheme` flips | `colorScheme` | #2 only | ❌ |
| **Lights toggle** | Click 💡 | `lightsOn` flips | `lightsOn` | #2 only | ❌ |
| **Color mode** | Click 类型/速度 | `colorMode` changes | `colorMode` | #3, #4 | ❌ (digest same) |
| **Year filter** | Click year pill | `selectedYear` + `filteredActivities` | `activities` ref changes | #3, #4 | ✅ (digest changes) |
| **Month filter** | Click month | `selectedMonth` + `filteredActivities` | `activities` ref changes | #3, #4 | ✅ (digest changes) |
| **Type/source filter** | Select filter | `filters.*` + `filteredActivities` | `activities` ref changes | #3, #4 | ✅ (digest changes) |
| **Search** | Type in search | `filters.search` + `filteredActivities` | `activities` ref changes | #3, #4 | ✅ (digest changes) |
| **Sort** | Click sort header | `sortField/Desc` + `filteredActivities` | `activities` ref changes | #3, #4 | ❌ (digest same) |
| **Activity hover** | Hover on map row | `mapHoveredId` | `hoveredActivityId` | #4 only | ❌ |
| **Initial load** | Page load | `setActivities()` | `activities` | #3, #4 | ✅ (first) |
| **Drawer open/close** | Click handle | `drawerOpen` | — | none | ❌ (overlay) |
| **Detail panel** | Click activity row | `detailOpen` + `selectedActivity` | — | none | ❌ (overlay) |
| **Chart overlay** | Click 📊 | `showCharts` | — | none | ❌ (overlay) |
| **Window resize** | Resize browser | — | — | Leaflet auto | ✅ (browser level) |

### Panels are overlays, not sidebars

All panels use `position: fixed` with higher `z-index` and overlay on top of the full-screen map. The map container never resizes, so `map.invalidateSize()` is unnecessary.

```
Layout:
  MapView          full-screen, z-index 0, fixed
  Overlays         z-index 1 (brand/year/legend)
  Drawer           z-index 2, slides up/bottom
  DetailPanel      z-index 3, backdrop overlay
  ChartOverlay     z-index 4, backdrop overlay
```

## Map Zoom Animation Policy

| Situation | Animation | Rationale |
|---|---|---|
| Initial load | `fitBounds` default (~0.25s) | User expects to see all activities animate into view |
| Filter change | `fitBounds` default | Content set changed, zoom to new bounds |
| Theme toggle | None | Tile layer instant swap, no zoom |
| Color mode | None | Only polyline color changes |
| Hover | None | Instant style update |
| Sort | None | Same activities, no zoom needed |
| Drawer panel | None (CSS transform only) | Overlay, no container resize |

## Test Coverage

### Unit tests (vitest, mocked Leaflet)

| Test | Scenario | Assertion | Status |
|---|---|---|---|
| Theme toggle → no map recreate | `toggleTheme()` | `L.map` called once | ✅ |
| MiniMap theme toggle → no recreate | `toggleTheme()` | `L.map` called once | ✅ |
| ColorMode → no fitBounds | `setColorMode('speed')` | `fitBounds` called once (initial) | ❌ |
| Filter (different length) → fitBounds | Reduce activities from 5 to 3 | `fitBounds` called again | ❌ |
| Filter (same length, different content) → fitBounds | Swap 5 activities for 5 others | `fitBounds` called again | ❌ |
| Sort → no fitBounds | Reorder same 5 activities | `fitBounds` not called again | ❌ |
| Empty → no fitBounds | 0 activities | `fitBounds` not called | ❌ |

### E2E tests (Playwright, real browser)

| Test | Scenario | Assertion | Status |
|---|---|---|---|
| Theme toggle → map transform unchanged | Click theme button | `leaflet-map-pane` transform same | ✅ |
| Year filter → map zoom changes | Click year pill | Transform changes | ❌ |
