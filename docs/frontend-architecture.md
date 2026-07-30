# Frontend Architecture — Design Document

## 1. Problem Statement

Workouts CLI exports workout data as static JSON (activities + aggregated stats). The frontend consumes these files and renders multiple visual presentations: a running-log table, a full-screen map with activity list, and a system info diagnostic page. Each presentation is a standalone page deployed to a static host (GitHub Pages).

The frontend needs to support:

- Multiple independent visual themes from the same data
- Optional capabilities: map rendering, chart generation
- Independently versioned theme and plugin packages, with npm publishing capability
- Graceful degradation when a capability is absent

## 2. First Principles

All architectural decisions derive from these constraints:

| Constraint | Derivation |
|---|---|
| Static JSON input, no server | Data layer is client-side fetch + normalize. No SSR. No API server. |
| GitHub Pages deployment | Output is pure HTML/CSS/JS. No server-side routing. Multi-page via multi-HTML-entry. |
| Themes are independent pages | No shared JS state across themes at runtime. Each page is a full page load. |
| Themes differ in component composition | Direct npm imports create hard dependencies. Registry-based lookup allows optional capabilities. |
| Plugins may be absent (map, chart) | Component resolution returns `ComponentType \| null`. Themes handle null gracefully. |
| Build time ≠ runtime | All decisions (which plugins, which theme, config) are resolved at build. No runtime config server. |
| React 19 hook model | Fine-grained re-renders are important. zustand selectors prevent cascade renders. Context is for immutable app-level values. |

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  config.json ────────────────────────────────────────────────── │
│    plugins: [...], theme: "overview", data: { ... }            │
└────────┬────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────┐
│  @workouts/core (engine)                                      │
│    config.ts   → parse + validate                             │
│    loader.ts   → dynamic import() plugin packages             │
│    registry.ts → pluginId × componentName → Component         │
│    context.tsx → CoreProvider { data, config, registry }      │
└───────┬──────────────────────────────────────────────────────┘
        │
        │  dynamic import()
        ▼
┌───────────────────────────────────────────────────────────────┐
│  plugin-data-source (core plugin)                              │
│    init → fetch + normalize → hooks.afterDataLoad              │
└───────────────────────────────────────────────────────────────┘
        │
        │  registerComponents()
        ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│ plugin-map    │ │ plugin-chart   │ │ plugin-ui     │
│ - MapView     │ │ - BarChart     │ │ - MiniPolyline│
│               │ │ - PieChart     │ │ - SourceBadge │
│               │ │               │ │ - Modal       │
└───────────────┘ └───────────────┘ └───────────────┘
        │
        │  theme Layout renders, retrieves components
        ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────────┐
│theme-hello    │ │ theme-simple  │ │ theme-overview    │
│ - Layout      │ │ - Layout      │ │ - Layout          │
│               │ │ - Sidebar     │ │ - Drawer          │
│               │ │ - Table       │ │ - ActivityList    │
│               │ │ - FilterBar   │ │ - DetailPanel     │
│               │ │ - Grid/Card   │ │ - Filters,Picker  │
└───────────────┘ └───────────────┘ └───────────────────┘
```

## 4. Package Structure

```
packages/
  core/                       # @workouts/core — framework engine
    src/
      index.ts                # createApp(), types export
      config.ts               # config.json parse + validate + defaults
      loader.ts               # dynamic import plugin/theme packages
      registry.ts             # ComponentRegistry (pluginId, name) → ComponentType
      context.tsx             # CoreProvider, useCore(), usePlugin(), useComponent()
      hooks.ts                # HookSystem (beforeDataLoad, afterDataLoad)
      types.ts                # PluginAPI, PluginManifest, ThemeProps

  plugin-data-source/         # @workouts/plugin-data-source
    src/
      index.ts                # WorkoutsPlugin export
      data.ts                 # fetch + normalize pipeline
      normalize.ts            # Activity type normalization
      types.ts                # DataSource, DataResult

  plugin-map/                 # @workouts/plugin-map
    src/ index.ts, MapView.tsx, types.ts

  plugin-chart/               # @workouts/plugin-chart
    src/ index.ts, BarChart.tsx, PieChart.tsx, types.ts

  plugin-ui/                  # @workouts/plugin-ui (shared primitives)
    src/ index.ts, MiniPolyline.tsx, SourceBadge.tsx, Modal.tsx

  theme-hello-world/          # @workouts/theme-hello-world
    src/ index.ts, Layout.tsx

  theme-simple/               # @workouts/theme-simple (default)
    src/ index.ts, Layout.tsx, store.ts, Sidebar.tsx,
        ActivityTable.tsx, FilterBar.tsx, VirtualGrid.tsx,
        ActivityCard.tsx, ActivityChart.tsx

  theme-overview/             # @workouts/theme-overview
    src/ index.ts, Layout.tsx, store.ts,
        Drawer.tsx, ActivityList.tsx, Filters.tsx,
        YearPicker.tsx, DetailPanel.tsx, ChartOverlay.tsx

  shared/                     # @workouts/shared — pure TS (unchanged)
    src/ index.ts, theme-types.ts, color-mode.ts

  web/                        # @workouts/web — application entry
    config.json               # plugin/theme/data configuration
    vite.config.ts            # Vite + React + Tailwind plugins
    index.html                # root entry
    src/ main.tsx             # reads config → createApp()
     public/
       activities.json         # dev fixture data (summary, no polyline)
       tracks.json             # dev fixture data (run_id → polyline map)
       stats.json
```

## 5. Plugin System

### 5.1 Core Concepts

**Plugin:** An npm package exporting `WorkoutsPlugin`. Provides components via the registry. No visual root of its own. Type: `"plugin"`.

**Theme:** A plugin of `type: "theme"` that also exports a `Layout` React component. Renders the full page.

**Component Registry:** A map `(pluginId, name) → React.ComponentType`. Populated during `init()`. Retrieved at render time by themes calling `useComponent(pluginId, name)`.

**Hook System:** A pub/sub for lifecycle events. Currently: `beforeDataLoad`, `afterDataLoad`. Extensible for config, render.

### 5.2 Plugin Interface

```typescript
// @workouts/core types
type PluginType = 'plugin' | 'theme'

interface PluginManifest {
  id: string                    // unique, e.g. "@workouts/plugin-map"
  version: string
  type: PluginType
  displayName?: string
  description?: string
  requires?: string[]           // hard dependencies (must be loaded first)
  optional?: string[]           // cooperative plugins (enhance if present)
}

interface PluginAPI {
  registry: {
    register: (components: Record<string, React.ComponentType>) => void
    get: (pluginId: string, name: string) => React.ComponentType | null
    getAll: () => Record<string, Record<string, React.ComponentType>>
  }
  data: {
    fetch: (source: string) => Promise<unknown>
    normalize: (raw: unknown) => Activity[]
  }
  config: Record<string, unknown>
  hooks: {
    on: (event: string, handler: (...args: unknown[]) => void) => void
    off: (event: string, handler: (...args: unknown[]) => void) => void
  }
}

interface WorkoutsPlugin {
  manifest: PluginManifest
  init?: (api: PluginAPI) => void | Promise<void>
  components?: Record<string, React.ComponentType<any>>
  Layout?: React.ComponentType<ThemeProps>     // theme only
}

interface ThemeProps {
  data: { activities: Activity[]; stats: Record<string, unknown> | null; error?: string }
  config: Record<string, unknown>
  registry: ComponentRegistry
}
```

### 5.3 Lifecycle

```
bootstrap:
  core/config.ts   → read config.json → validate → merge defaults
  core/loader.ts   → resolve plugin package names → dynamic import()

init: (in dependency order, requires first)
  for each plugin:
    plugin.init(api)
      → api.registry.register(plugin.components)
      → api.hooks.on('afterDataLoad', ...)

  for theme plugin:
    plugin.init(api)
      → create zustand store (theme-private)
      → api.registry.register(theme.components)   // optional override

data:
  hooks.fire('beforeDataLoad')
  plugin-data-source → fetch → normalize
  hooks.fire('afterDataLoad', normalizedData)

render:
  ReactDOM.createRoot(target).render(
    <CoreProvider value={{ data, config, registry }}>
      <ThemeLayout />
    </CoreProvider>
  )
```

### 5.4 Component Resolution

Themes retrieve plugin components via `useComponent`, never by direct import:

```tsx
function ThemeLayout() {
  const MapView = useComponent('@workouts/plugin-map', 'MapView')
  const BarChart = useComponent('@workouts/plugin-chart', 'BarChart')

  return (
    <div>
      {MapView ? <MapView activities={filtered} /> : <FallbackPanel />}
      {BarChart && (
        <Modal>
          <BarChart data={monthlyData} />
        </Modal>
      )}
    </div>
  )
}
```

Resolution chain:
1. Lookup `registry[(pluginId, name)]`
2. If not found → return `null`
3. Theme handles `null` → component not rendered, no error

Themes cannot override another plugin's registered component. A theme that needs custom map behavior either:
- Passes props to the standard MapView component
- Conditionally renders a completely different component when MapView is available
- Registers its own component set (theme-private, not in the global registry)

### 5.4.1 Development-Time Resolution Check

Themes can use a wrapper that warns in development when an expected component is not registered:

```typescript
function useRequiredComponent(pluginId: string, name: string) {
  const Component = useComponent(pluginId, name)
  if (process.env.NODE_ENV === 'development' && !Component) {
    console.warn(`[${pluginId}] ${name} not loaded`)
  }
  return Component
}
```

Zero runtime cost — the entire check is dead-code-eliminated in production builds.

### 5.5 Graceful Degradation

| Scenario | Behavior |
|---|---|
| plugin-map not loaded | `useComponent` returns null. Theme renders without map. |
| plugin-chart not loaded | Chart button hidden or disabled. |
| data.{key}.optional = true, fetch fails | Field is null. Components handle null. |
| data.{key}.optional = false, fetch fails | Core passes error info via Context (`error` field in ThemeProps). Theme Layout handles visual presentation of the error. |
| plugin init() throws | Core logs error, skips plugin. Other plugins proceed. |
| config.json missing/empty | Core throws descriptive error at bootstrap. |
| config.json references unknown plugin | Core logs warning, continues without it. |

### 5.6 Plugin Discovery

Plugins must be explicitly listed in config.json:

```json
{
  "plugins": ["@workouts/plugin-map", "@workouts/plugin-chart"],
  "themes": {
    "simple": "@workouts/theme-simple",
    "overview": "@workouts/theme-overview"
  },
  "theme": "simple"
}
```

Rejected alternatives:
- **File-system scanning** (e.g., scan `node_modules/@workouts/plugin-*`): Implicit, fragile, slow for large node_modules.
- **Package dependency scanning** (read package.json deps): Every installed package would need to be a plugin.

### 5.7 Local Development vs Publishing

**Development:** npm workspaces resolve packages locally.

```json
// packages/web/package.json
{ "dependencies": {
    "@workouts/core": "*",
    "@workouts/plugin-map": "*",
    "@workouts/theme-overview": "*"
} }
```

**Published:** Same config, versioned dependencies.

```json
{ "dependencies": {
    "@workouts/core": "^1.0.0",
    "@workouts/plugin-map": "^1.0.0",
    "@workouts/theme-overview": "^1.0.0"
} }
```

`config.json` requires zero changes. npm resolves the package — workspace or registry — transparently.

## 6. Configuration

### 6.1 Schema

```typescript
interface WorkoutsConfig {
  plugins?: string[]                                // feature plugins
  themes?: Record<string, string>                   // { id: packageName }
  theme: string                                     // active theme id
  themeOptions?: Record<string, unknown>             // passed to theme Layout
  pluginOptions?: Record<string, Record<string, unknown>>
  data: Record<string, string | {
    type: 'url' | 'json'
    path?: string
    data?: unknown
    optional?: boolean
  }>
  entries?: Record<string, string>  // { urlPath: themeId }. "index" → /, "overview" → /overview
}
```

### 6.2 Scenarios

**Minimal (single theme, local data):**
```json
{
  "theme": "simple",
  "data": {
    "activities": "site/activities.json",
    "tracks": "site/tracks.json",
    "stats": "site/stats.json"
  }
}
```

**Full (multi-entry, plugins, options):**
```json
{
  "plugins": ["@workouts/plugin-map", "@workouts/plugin-chart"],
  "themes": {
    "simple": "@workouts/theme-simple",
    "overview": "@workouts/theme-overview",
    "hello": "@workouts/theme-hello-world"
  },
  "theme": "overview",
  "themeOptions": { "colorMode": "speed" },
  "pluginOptions": {
    "@workouts/plugin-map": { "tileStyle": "carto-dark" },
    "@workouts/plugin-chart": { "theme": "dark" }
  },
  "data": {
    "activities": { "type": "url", "path": "https://cdn.example.com/activities.json", "optional": false },
    "tracks": { "type": "url", "path": "https://cdn.example.com/tracks.json", "optional": true },
    "stats": { "type": "url", "path": "https://cdn.example.com/stats.json", "optional": true }
  },
  "entries": {
    "index": "simple",
    "overview": "overview",
    "hello": "hello"
  }
}
```

**Minimal degraded (no plugins, no multi-entry):**
```json
{
  "theme": "simple",
  "data": { "activities": "site/activities.json", "tracks": "site/tracks.json" }
}
```

## 7. Data Flow

```
config.json
  └→ core/config.ts 解析

loader.ts 动态 import
  ├→ plugin-data-source  init → 注册 fetch + normalize → 挂 afterDataLoad hook
  ├→ plugin-map          init → registry.register({ MapView })
  ├→ plugin-chart        init → registry.register({ BarChart, PieChart })
  ├→ plugin-ui           init → registry.register({ MiniPolyline, SourceBadge, Modal })
  └→ theme-{name}        init → 创建 zustand store (主题私有), registry.register(theme components)

hooks.fire('beforeDataLoad')
  └→ plugin-data-source 监听, 无操作

data layer:
  Phase 1 (eager): plugin-data-source.fetch([activities, stats]) → Promise.all parallel fetch
                    → activities summary renders list + stats immediately
  Phase 2 (lazy):  plugin-data-source.fetchTracks(tracks.json) → { run_id: polyline } map
                    → tracks merged into activities → map polylines render progressively
  plugin-data-source.normalize(raw) → Activity[] (normalize legacy fields)
  hooks.fire('afterDataLoad', data)

CoreProvider
  ├→ data:   { activities: Activity[], stats: Record<string, unknown> | null }
  ├→ config: Record<string, unknown>  (merged from config.json)
  └→ registry: ComponentRegistry

ThemeLayout mounts
  ├→ useCore() → data, config
  ├→ useComponent('@workouts/plugin-map', 'MapView') → ComponentType | null
  ├→ usePluginStore() → theme-private zustand store
  └→ renders composed component tree
```

### 7.1 Data Normalization

Done by `@workouts/plugin-data-source`, run once at load time:

```typescript
function normalizeActivity(raw: unknown): Activity {
  return {
    ...raw,
    sport_category: raw.sport_category || raw.type || 'other',
    // Polyline is null in activities.json; merged from tracks.json in Phase 2
    summary_polyline: raw.summary_polyline || raw.polyline || null,
  } as Activity
}
```

Polyline merging happens in the theme Layout's `useEffect`: `a.summary_polyline || tracks[a.run_id] || null`. This two-pass approach keeps the initial load lightweight (~80KB summary vs ~3MB with polylines) while still enabling full GPS map rendering.

The `Activity` interface is defined in `@workouts/shared` and shared across all packages. No normalization logic exists outside `plugin-data-source`.

## 8. State Management

Three layers, separated by volatility and scope:

| Layer | Scope | Volatility | Tool | Example |
|---|---|---|---|---|
| App-level | All plugins/themes | Two-phase: summary first, tracks merged later | React Context | activities[], stats, config |
| Theme UI | Single theme | Frequent changes | Zustand | selectedYear, filters, drawerOpen |
| Component-local | Single component | Transient | useState | input focus, open/close animation |

### 8.1 Why Zustand for Theme UI State

- **Selector API prevents cascade re-renders:** `useSimpleStore(s => s.selectedYear)` re-renders only when `selectedYear` changes.
- **No Provider nesting:** Zustand stores are module-level singletons. No prop drilling. No Context cascade.
- **Outside React access:** Plugins can read store values in event handlers without being in the React tree (e.g., MapView's Leaflet click handler).

React Context is intentionally NOT used for UI state: every Context value change re-renders all consuming components.

### 8.2 Cross-Theme State Sharing

**Not implemented. Not needed.**

Each entry is a separate page load. No JavaScript state survives navigation. No live state sharing exists between themes at runtime.

The only shared layer is data (activities, stats) and config — both provided by CoreProvider as immutable Context values.

### 8.3 Theme Store Example

```typescript
// theme-simple/store.ts
import { create } from 'zustand'

interface SimpleStore {
  selectedYear: number | null
  summaryType: 'all' | 'yearly' | 'monthly'
  summaryInterval: 'month' | 'week'
  setYear: (year: number | null) => void
}

export const useSimpleStore = create<SimpleStore>((set) => ({
  selectedYear: null,
  summaryType: 'all',
  summaryInterval: 'month',
  setYear: (year) => set({ selectedYear: year }),
}))
```

## 9. Themes

### 9.1 Theme Contract

```typescript
interface ThemeProps {
  data: { activities: Activity[]; stats: Stats | null; error?: string }
  config: Record<string, unknown>
  registry: ComponentRegistry
}

// Themes must export:
interface ThemePlugin extends WorkoutsPlugin {
  type: 'theme'
  Layout: React.ComponentType<ThemeProps>
}
```

### 9.2 theme-hello-world

Diagnostic/verification page. Single-panel information display, zero interactivity.

Displays:
- Project name + version (injected at build time)
- Environment (dev/prod)
- Data status (activity count, stats presence)
- Loaded plugins list (id, version, type)
- Available themes (id, package, active marker)
- Rendered config (formatted `config.json`)
- Package versions (react, leaflet, echarts, zustand, tailwindcss)

Data sources: Core metadata (compiled constants), plugin-manifest registry, config object, `package.json` (compiled into bundle).

### 9.3 theme-simple (default)

Running-page style. Two-column layout: sidebar + content area.

**Layout:**
```
┌─────────┬──────────────────────────────────────────────────────┐
│ Sidebar │  Header (title + theme toggle)                       │
│ 2012    │ ┌──────────────────────────────────────────────────┐ │
│ 2013    │ │ ActivityTable (sortable columns)                 │ │
│ ...     │ │  Date | Source | Distance | Pace | HR | Time     │ │
│ Total   │ │  2024 │ G │ 10.2km │ 5:30/km │ 145 │ 0:56:12    │ │
└─────────┴──────────────────────────────────────────────────────┘
```

**Components:** Sidebar (year list with per-year stats), ActivityTable (sortable), FilterBar (type/interval), VirtualGrid + ActivityCard (summary view), ActivityChart (mini bar per activity).

**States:** Year selection, table sorting, summary/table toggle, filter type, filter interval, theme toggle.

### 9.4 theme-overview

Full-screen map with overlay controls and slide-out drawer.

**Layout:**
```
┌──────────────────────────────────────────────────────────────────┐
│ [Brand]                                                          │
│                          Map (full screen)                        │
│ [YearPicker]                                                     │
│                                    [legend] [toggle]              │
│                                                          ┌────┐  │
│                                                          │Drawer│ │
│                                             ┌──┐         │List  │ │
│                       [DetailPanel overlay] │  │         │or    │ │
│                                             └──┘         │Filter│ │
│                                                          └────┘  │
└──────────────────────────────────────────────────────────────────┘
```

**Components:** MapView (Leaflet, polylines, hover/tooltip), Drawer (collapsible panel), ActivityList (with SVG mini-polylines), DetailPanel (modal with stats + mini-map), Filters (type/source/range/search), YearPicker (vertical pills), ChartOverlay (ECharts monthly bar + type pie).

**States:** Selected year, selected month, drawer open/close, detail panel open/close, chart overlay open/close, color mode (type/speed), sort field/direction, filters, map hover ID, dark/light theme.

## 10. Component Architecture

### 10.1 Resolution Model

```
Theme Layout
  ├── useComponent('@workouts/plugin-map', 'MapView') → MapView | null
  ├── useComponent('@workouts/plugin-chart', 'BarChart') → BarChart | null
  ├── useComponent('@workouts/plugin-ui', 'MiniPolyline') → MiniPolyline
  └── import { ... } from './components/*' → theme-private components
```

Theme-private components are direct imports. Plugin components are resolved via registry. This distinction is clear: proprietary vs shared.

### 10.2 Shared Components (plugin-ui)

| Component | Purpose | Used by |
|---|---|---|
| `MiniPolyline` | Inline SVG polyline thumbnail (activity list row) | theme-overview, theme-simple |
| `SourceBadge` | Source indicator badge (G/GC/S/K/iG/X/XZ) | All themes |
| `Modal` | Generic overlay/modal with backdrop + animation | All themes |

The `plugin-ui` package starts as a placeholder. Components are extracted when actual duplication across themes becomes evident.

## 11. Build System

### 11.1 Vite Configuration

```typescript
// vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import config from './config.json'

const input = Object.fromEntries(
  Object.entries(config.entries ?? { index: config.theme }).map(([key, theme]) => [
    key === 'index' ? 'index' : key,
    `src/entries/${theme}.tsx`,
  ])
)

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: '',
  resolve: { alias: { '@': 'src' } },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input,
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
})
```

### 11.2 Entry Generation

Each entry is a thin TypeScript file that imports the correct theme:

```typescript
// src/entries/simple.tsx
import { createApp } from '@workouts/core'
import config from '../../config.json'

createApp({
  target: document.getElementById('app')!,
  theme: 'simple',
  config,
})
```

Entry files are generated from `config.json.entries` at build time. The `prebuild` script creates them if absent.

### 11.3 Tailwind

Applied at the app level via `@tailwindcss/vite`. Each plugin/theme uses Tailwind utility classes optionally. Unused classes are purged at build time — a theme that doesn't use Tailwind generates no Tailwind output.

Design tokens are centralized in `@theme`:

```css
/* packages/web/src/global.css */
@import 'tailwindcss';

@theme {
  --color-accent: #4DD2FF;
  --color-surface: #16213E;
  --color-border: #2A2A4A;
  --color-text: #E0E0E0;
  --color-text-secondary: #888888;
}
```

Dark mode: Tailwind's `dark:` prefix, driven by `data-theme` attribute on `<html>`.

```css
@custom-variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));
```

An inline `<script>` in the HTML `<head>` prevents flash of wrong theme (FOUC):

```html
<script>
  const saved = localStorage.getItem('theme')
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
  if (saved === 'dark' || (!saved && prefersDark))
    document.documentElement.setAttribute('data-theme', 'dark')
</script>
```

Theme switching follows system preference by default, overridden by manual toggle which persists to `localStorage`.

### 11.1 Preload Optimization

The HTML template includes `<link rel="preload" href="activities.json" as="fetch">` to begin downloading summary data before JavaScript initializes. This eliminates the fetch-from-JS waterfall for the critical data file, reducing first-contentful-paint by 200–500ms.

## 12. Testing

### 12.1 Strategy

| Layer | Scope | Tool |
|---|---|---|
| L0 Unit | Core config/loader/registry, data normalize, formatters | vitest |
| L1 Integration | Plugin init order, component render with mock data, graceful degradation | vitest + jsdom + @testing-library/react |
| L2 E2E | Full page load, interaction, visual consistency, data chaos, a11y | Playwright |

### 12.2 Data Chaos Matrix

Every theme is tested against every data anomaly:

```
                  │ empty │ malformed │ missing_fields │ slow_net │ 404
──────────────────┼───────┼───────────┼────────────────┼──────────┼─────
theme-simple      │   ✓   │     ✓     │       ✓        │    ✓     │  ✓
theme-overview    │   ✓   │     ✓     │       ✓        │    ✓     │  ✓
theme-hello-world │   ✓   │     ✓     │       ✓        │    ✓     │  ✓
plugin-map off    │   —   │     —     │     ✓(降级)     │    —     │  —
plugin-chart off  │   —   │     —     │     ✓(降级)     │    —     │  —
```

### 12.3 Visual Regression

Playwright screenshot snapshots are NOT tracked in git. Strategy:

- Screenshots generated at CI run time
- Diff compared against baseline from the same CI environment
- On failure, Artifact uploaded with diff images for manual review
- No binary files in the repository

### 12.4 Accessibility

Playwright `pa11y` runs at **mild** level (severe issues only). Not a gate — informational output in CI log. Purpose: catch high-impact regressions (missing labels on interactive elements, insufficient color contrast on primary UI).

### 12.5 Lint & Format

Biome runs as a single command:

```bash
biome check --write src/   # lint + format + import sort
```

CI gate: `biome ci src/` (read-only check, fails on violations). No separate ESLint or Prettier configs.

### 12.6 Bundle Size

CI monitors per-entry bundle sizes. Thresholds are set after the first stable build. Exceeding threshold is a warning, not a hard fail. Purpose: detect accidental dependency bloat (e.g., a plugin pulling in a large transitive dependency).

## 13. Dependency Versions

All packages use latest stable versions at implementation time. Node >=22.0.0.

| Package | Version | Role |
|---|---|---|
| `react` | 19.2.7 | UI framework |
| `react-dom` | 19.2.7 | DOM renderer |
| `zustand` | 5.0.14 | Theme-private state |
| `lucide-react` | 1.24.0 | Icons |
| `@vitejs/plugin-react` | 6.0.3 | Vite React integration |
| `@tailwindcss/vite` | 4.3.2 | Tailwind Vite plugin |
| `tailwindcss` | 4.3.2 | Utility CSS |
| `@biomejs/biome` | 2.5.3 | Lint + format |
| `vite` | 8.1.4 | Build tool |
| `typescript` | 7.0.2 | Type checking |
| `vitest` | 4.1.10 | Unit/integration tests |
| `@playwright/test` | 1.61.1 | E2E tests |
| `jsdom` | 29.1.1 | DOM simulation |
| `@testing-library/react` | 16.3.2 | Component testing |
| `@testing-library/jest-dom` | 6.9.1 | DOM matchers |
| `leaflet` | 1.9.4 | Map rendering (unchanged, stable) |
| `echarts` | 6.1.0 | Chart rendering (unchanged) |
| `@types/react` | 19.2.17 | React type definitions |
| `@types/react-dom` | 19.2.3 | React DOM type definitions |
| `@types/leaflet` | 1.9.21 | Leaflet type definitions |
| `@types/node` | 26.1.1 | Node type definitions |

Removed from current project:
- `svelte`, `@sveltejs/vite-plugin-svelte`, `svelte-check`
- `@workouts/svelte-echarts`, `@workouts/svelte-leaflet`

## 14. Related Documents

- `docs/frontend-architecture-impl.md` — Implementation record: key decisions, rationale, rejected alternatives, implementation order, legacy cleanup plan.
- `CONTEXT.md` — Project overview, CLI commands, data sync architecture, DB schema.
- `docs/data-architecture.md` — L1 raw → L2 standard → L3 SQLite → L4 artifacts → L5 deploy pipeline.
