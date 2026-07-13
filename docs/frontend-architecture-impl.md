# Frontend Architecture — Implementation Record

## 1. Migration Context

The original frontend was a Svelte 5 SPA with a theme plugin system based on dynamic `import()` of Layout components and a multi-page Vite build (`config.json` → HTML entries with `<meta name="app-theme">`).

Two forces converged to make migration necessary:

1. **Framework preference:** React's ecosystem, hiring market, and component model better align with the project's long-term goals.
2. **Architectural divergence:** Svelte 5 runes (`$state`, `$effect`, `$derived`) have no direct React equivalents. A 1:1 port would produce anti-pattern React code (putting side effects in render, missing dependency arrays, mutating state directly). A clean-slate design was the only correct path.

The strategy was: design the plugin system from first principles in React, then implement themes as consumers of that system. No incremental migration. No compatibility layer.

## 2. Design Evolution

The design went through three major iterations before reaching the current state:

### Iteration 1: Direct Port Attempt (rejected)

Try to map Svelte concepts to React concepts 1:1. `$state` → `useState`, `$effect` → `useEffect`, `$derived` → `useMemo`, `setContext/getContext` → React Context.

**Why rejected:** Svelte's reactivity is compiler-managed. React's is developer-managed. The mapping works mechanically but produces code that fights the framework. Example: Svelte's `$effect` automatically tracks all reactive dependencies; React's `useEffect` requires explicit dependency arrays, which when computed from the Svelte source are invariably missing entries.

### Iteration 2: Inline Everything (rejected)

No plugin system. Put all themes and plugins in a single package. Direct imports between modules.

**Why rejected:** No publish isolation. Third-party themes impossible without forking core. Multi-entry build works but every theme bundles every plugin regardless of usage. Violates the "independently versioned packages" requirement.

### Iteration 3: Registry-Based Plugin System (current)

Core provides component registry + context. Plugins register components at init time. Themes resolve components at render time via `useComponent(pluginId, name)`. Loose coupling, graceful degradation, publish-ready.

## 3. Key Decisions

### 3.1 Config Format: JSON

**Decision:** Single `config.json`. TypeScript interfaces define the schema; validation runs at bootstrap.

**Rationale:**
- Editable by scripts, CI, and humans without a build step
- TypeScript interfaces provide IDE hints without requiring the config itself to be TypeScript
- The config is static and known at build time — dynamic evaluation (Turing-complete config language) has no use case

**Rejected alternatives:**
- **TypeScript config file:** Adds a build step for config changes. Overkill for static key-value data.
- **YAML:** Another syntax to learn. No advantage over JSON for flat structures with no multiline strings.
- **TOML:** Less JSON compatibility, smaller ecosystem.

### 3.2 CSS: Tailwind v4

**Decision:** Tailwind v4 at the application level via `@tailwindcss/vite`. Individual plugins/themes optionally use utility classes. Unused classes are purged at build. Dark mode uses `data-theme` attribute rather than the `dark` CSS class, consistent with the existing project convention.

**Rationale:**
- Utility-first CSS maps directly to component composition in React
- No naming overhead (no `.activityList`, `.drawerPanel`, `.detailGrid` rules to maintain)
- `@theme` directive centralizes design tokens without a separate config file
- Build-time purging ensures non-Tailwind-using themes produce zero Tailwind output
- `@tailwindcss/vite` has zero-config integration with Vite
- Dark mode via `@custom-variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));`

**Why not CSS Modules:** CSS Modules provide scoping but require naming every component. For ~15 components across themes, the naming overhead exceeds the scoping benefit. Tailwind's purge eliminates the unused-class concern from global CSS approaches.

**Why not CSS-in-JS:** Runtime CSS computation adds to FCP (First Contentful Paint). Static deployment benefits from pre-generated CSS. No advantage to computing styles at runtime when themes are pre-defined.

### 3.3 Lint/Format: Biome

**Decision:** Biome replaces ESLint + Prettier as a single tool.

**Rationale:**
- Single configuration file (`biome.json`), single CLI command
- Rules cover ESLint core + typescript-eslint + react-hooks (the subset relevant to this project)
- Import sorting built-in, no `eslint-plugin-import` or `eslint-plugin-simple-import-sort` needed
- 10-100x faster than ESLint (Rust native)
- Lint rules can be selectively disabled per file via `// biome-ignore lint/` comment

**Trade-off:** Biome's rule set is smaller than ESLint's full plugin ecosystem. However, the project's linting surface is modest: React hooks rules, TypeScript best practices, import ordering. Biome covers all of these. The `@eslint-react/eslint-plugin` (running_page uses) has no Biome equivalent, but this project's React patterns are standard enough that core rules suffice.

### 3.4 State Management: Theme-Owned Zustand

**Decision:** Each theme creates its own zustand store in module scope. Core provides Context only for immutable data (activities, stats, config).

**Rationale:**
- Theme UI state (selectedYear, filters, drawerOpen) is inherently theme-private
- Zustand's selector API provides fine-grained re-renders: `useStore(s => s.selectedYear)` re-renders only when the selected value changes
- React Context would cause cascade re-renders for every state change in the store
- No cross-theme state sharing exists (each entry is a separate page load)
- Stores are module-level — no Provider component needed, no prop drilling

**Why not core-managed stores:** Injecting store management into core adds abstraction for a 1:1 relationship (each theme has exactly one store). The theme knows its own state shape; core does not need to.

**Why not Redux:** Too much ceremony for a single-page application with a small component tree. Boilerplate (actions, reducers, dispatch) dwarfs actual logic.

**Why not React Context for UI state:** Every Context value change re-renders all consumers. A filter change would re-render the map, the list, and the drawer simultaneously. Zustand's selector API avoids this.

**Why not Jotai:** Viable alternative. Zustand chosen for simpler API surface (`create((set) => ({}))` vs multiple `atom()` declarations) and wider ecosystem adoption.

### 3.5 No Cross-Theme State Sharing

**Decision:** Theme state is strictly isolated. Core provides only immutable data and config.

**Rationale:**
- Multi-page architecture: each entry loads a single theme in a full page load. No live state sharing between pages.
- The only shared concern is data (activities, stats) and config — both are immutable after load and provided via Context.
- Adding a cross-theme state mechanism would solve a problem that doesn't exist.

### 3.6 Data Layer: Separate Core Plugin

**Decision:** `@workouts/plugin-data-source` is a standalone package, not built into `@workouts/core`.

**Rationale:**
- Data source management is a pluggable concern. The current implementation fetches JSON files. A future implementation might stream from a WebSocket, query a GraphQL endpoint, or read from IndexedDB. Core should not need to change when the data source changes.
- The hooks API (`beforeDataLoad`, `afterDataLoad`) needs a real consumer from day one to validate its design.
- Testing data loading in isolation without full core bootstrap is simpler with a separate package.

**Trade-off:** Adds one more package to the dependency tree. However, since `plugin-data-source` is effectively mandatory (no data = no render), its dependency status makes no practical difference. The structural separation is the point.

### 3.7 Component Resolution: Registry-Based

**Decision:** Components are registered by plugins at init time. Themes retrieve them via `useComponent(pluginId, componentName)`. Direct imports between packages are not used across the plugin/themes boundary.

**Rationale:**
- Loose coupling: themes don't import plugin packages directly
- Optional: `useComponent` returns `null` when a plugin isn't loaded
- Late binding: registration order is deterministic and independent of import order

**Rejected alternatives:**
- **Direct npm imports (`import { MapView } from '@workouts/plugin-map'`):** Creates hard dependencies. A theme that imports MapView cannot load without `@workouts/plugin-map` installed. Violates the "graceful degradation" requirement.
- **Inversion of control (core injects components as props to Layout):** Works for a single level but doesn't scale. Each theme has different component needs.
- **Slot pattern (`<PluginSlot name="map" />`):** Adds JSX wrapper for something a hook can express more directly.

### 3.8 No Client-Side Router

**Decision:** No router framework. Vite multi-entry generates separate HTML pages per theme entry.

**Rationale:**
- Static deployment (GitHub Pages) has no server for fallback routes
- Each theme is a self-contained page — a router that handles `/`, `/overview`, `/hello` would load all three themes into one bundle
- Multi-entry produces smaller bundles (each page loads only its theme's code)
- Theme-internal navigation (tabs, overlays) uses React state, not URL changes

**When a theme does need a router:** If a theme requires multiple URL-routed views, it can install `react-router-dom` independently. Core does not provide or restrict routing.

### 3.9 Icons: Lucide React

**Decision:** Lucide React for UI icons.

**Rationale:**
- Tree-shakeable: `import { X, ChartBar } from 'lucide-react'` bundles only used icons
- TypeScript-native: every icon is a typed React component
- Platform-consistent rendering across OS/browsers (SVG)
- Stable, widely adopted open-source library

**Why not SVGR (running_page approach):** SVGR requires maintaining SVG files individually and configuring `vite-plugin-svgr`. Suitable for generated SVGs (activity year charts) but overkill for UI symbols that have maintained library implementations.

**Why not inline SVGs:** Requires copy-pasting SVG markup per icon. Lacks type safety. Duplicates markup across themes.

### 3.10 Visual Regression: CI Artifact, Not Git

**Decision:** Playwright screenshot diffs are stored as CI artifacts, not committed to the repository.

**Rationale:**
- Binary files in git cause repository bloat
- Screenshot diffs cannot be meaningfully resolved in merge conflicts
- CI environment rendering differences (OS, GPU, fonts) cause false positive diffs that are indistinguishable from real regressions without manual review
- CI Artifact provides download-and-compare without polluting the repository

### 3.11 Component Resolution: Development-Time Assertion

**Decision:** Themes use a `useRequiredComponent` wrapper that warns in development when an expected plugin component is not registered. The check is dead-code-eliminated in production builds.

**Rationale:**
- The component registry is stringly-typed: a typo in a component name or a misconfigured config.json silently returns `null`
- A development-time warning catches the "plugin missing" class of bugs before they reach CI
- Zero production cost: Vite's `import.meta.env.DEV` tree-shakes the entire check in production

**Rejected alternative:**
- **Runtime assertion that throws:** A missing component is not a crash-worthy error — themes should gracefully degrade. Warning is the correct severity.

## 4. Implementation Order

The order is designed so that each step produces a testable, working increment:

| Step | Package | What It Produces | Dependency |
|---|---|---|---|
| 1 | `@workouts/core` | `createApp()`, `PluginAPI`, `CoreProvider`, `useCore`, `useComponent` | none |
| 2 | `@workouts/plugin-data-source` | Data fetch + normalize, hook integration | core |
| 3 | `@workouts/plugin-map` | `MapView` component (Leaflet) | core |
| 3P | `@workouts/plugin-chart` | `BarChart`, `PieChart` (ECharts) | core |
| 3P | `@workouts/plugin-ui` | `MiniPolyline`, `SourceBadge`, `Modal` | core |
| 4 | `@workouts/theme-hello-world` | Full Layout (system info) | core, plugin-data-source |
| 5 | `@workouts/theme-simple` | Layout + components | core, plugin-data-source, plugin-chart |
| 6 | `@workouts/theme-overview` | Layout + components | core, plugin-data-source, plugin-map, plugin-chart, plugin-ui |
| 7 | `@workouts/web` | `main.tsx`, `config.json`, `vite.config.ts`, build scripts | all |

Steps marked `3P` are parallel — they depend only on core and can be implemented concurrently.

### Rationale for order:

**Step 1 first:** Everything depends on core. No other package can initialize without the plugin loader, config parser, context provider, and component registry.

**Step 2 second:** Data must flow before any theme renders. `theme-hello-world` needs data to display activity counts. Both production themes need data for their components.

**Steps 3-3P in parallel:** Feature plugins are independent of each other. Map doesn't need chart. Chart doesn't need map. `plugin-ui` doesn't need either.

**Step 4 after data:** `theme-hello-world` is the simplest theme — one page, zero interactivity. It validates the end-to-end pipeline (core → data-source → theme) with minimal surface area. If this theme works, the architecture is proven.

**Steps 5-6 after plugins:** Production themes need their respective feature plugins. `theme-simple` uses chart. `theme-overview` uses map, chart, and ui.

**Step 7 last:** The entry point ties everything together. Building before all packages exist produces a broken app.

### What each step's tests verify:

| Step | What must pass |
|---|---|
| 1 | Config parse, plugin load/resolve, component register/lookup, context provider renders children |
| 2 | Fetch succeeds, normalize produces valid Activity[], malformed JSON handled, fetch failure handled |
| 3 | MapView renders Leaflet container, polyline rendering, dark/light tile switch |
| 3P | BarChart renders ECharts instance, PieChart renders, option update on data change |
| 3P | MiniPolyline renders SVG path, SourceBadge maps source to label, Modal opens/closes |
| 4 | Layout renders all info blocks, activity count correct, plugin list correct, config display correct |
| 5 | Layout renders sidebar + table, year selection filters activities, sort works |
| 6 | Layout renders map + drawer, drawer open/close, filter text filters list, year picker selects, detail panel shows correct stats |
| 7 | `npm run build` produces correct dist/, `npm run dev` starts, all entries load |

## 5. Testing Strategy

### 5.1 Layer Details

**L0 (vitest) — Pure logic, no DOM:**
- `core/config.test.ts`: Valid config produces correct output, missing required fields throws, unknown keys warn
- `core/loader.test.ts`: Plugin resolution order, missing plugin handled, init failure isolated
- `core/registry.test.ts`: Register/retrieve cycles, duplicate registration, null for missing
- `plugin-data-source/normalize.test.ts`: Legacy field mapping, null/undefined handling, type coercion
- `shared/formatters.test.ts`: Distance, duration, pace formatting (reuse existing)

**L1 (vitest + jsdom) — Rendered components with mock data:**
- Theme Layout renders with mock `ThemeProps`
- Plugin components render with mock props (MapView with mock activities, BarChart with mock data)
- Component resolution: `useComponent('missing-plugin', 'X')` returns `null`
- Error boundary: plugin init failure → warning logged, other plugins proceed
- Graceful degradation: theme renders without map plugin present

**L2 (Playwright) — Full browser environment:**
- Page load for each theme entry
- Data chaos: intercept activities.json with empty/malformed/missing_fields/404 responses, verify error states
- Interaction: click year, sort, filter, open drawer, open detail
- Screenshot diff: CI-level comparison, failed diffs uploaded as Artifact
- a11y: `pa11y` mild audit
- Console error check: zero errors during page load and interaction

### 5.2 Test Environment

- vitest uses `jsdom` via `@vitest/environment-jsdom`
- `@testing-library/react` for component rendering and queries
- `@testing-library/jest-dom` for DOM matchers (`toBeVisible`, `toHaveTextContent`)
- Playwright uses Chromium (CI) and optionally Firefox (local, for cross-browser)

### 5.3 CI Integration

```
PR →
  biome ci src/          # lint + format + import sort (check-only)
  vitest run             # L0 + L1
  vite build             # all entries compile without errors
  playwright test        # L2 E2E
  bundle-size-check.sh   # warn if threshold exceeded
```

## 6. Legacy Cleanup

After all new packages are implemented and tested:

| Old Package | Action |
|---|---|
| `packages/web` (Svelte) | Replace with new React entry. Remove `@sveltejs/vite-plugin-svelte`, `svelte`, `svelte-check`, `@workouts/svelte-echarts`, `@workouts/svelte-leaflet` |
| `packages/svelte-echarts` | Remove entirely |
| `packages/svelte-leaflet` | Remove entirely |
| `packages/shared` | Keep unchanged — pure TypeScript, zero migration cost |

Cleanup is done as a separate step after all new packages pass tests. The old code remains until the new code is verified end-to-end.

## 7. Future Work

### 7.1 Plugin npm Publishing

When a plugin reaches stability, publish to npm:

1. Update `package.json` with version, repository, license
2. `npm publish --access public`
3. Consumer updates dependency from `"*"` to `"^1.0.0"`
4. `config.json` unchanged — still references by package name

### 7.2 Custom Theme Creation Guide

Documentation for third-party theme authors:
- Required exports (`WorkoutsPlugin` with `Layout`)
- Available hooks and the PluginAPI
- Component resolution (`useComponent`)
- State management patterns
- Build integration (how to add a theme to `config.json`)

### 7.3 Plugin Hot-Reload (Development)

Current HMR reloads the entire page on plugin code change. A future enhancement could preserve theme state across plugin reloads by:
- Separating plugin module from theme module in Vite's module graph
- Using `import.meta.hot` to re-register components on plugin file change
- Keeping the theme's zustand store intact

### 7.4 Remote Theme Loading

Load a theme from a URL (for preview/demo):
- Requires CSP configuration to allow external scripts
- Sandboxed via `<iframe>` or Web Worker
- Config would reference `"source": "https://..."` instead of a package name

### 7.5 Plugin Config Schema

Each plugin could declare its accepted config schema via `PluginManifest.config`. Core would validate `pluginOptions` against the schema at bootstrap and reject invalid values. Currently, validation is manual (plugins check their own options in `init`).

### 7.6 Performance Budgets

After the first production build, set bundle size thresholds per entry. CI gates would warn when a new dependency causes unexpected growth. Thresholds calibrated from the stable baseline, not arbitrary limits.
