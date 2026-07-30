# Theme System — Architecture

## 概念

Theme = 一组自包含的 Svelte 组件，**完全定义 visual 布局**。

| 传统概念 | 本项目映射 |
|---|---|
| WordPress theme | `packages/plugins/themes/<name>/` |
| Jekyll theme | manifest.json + Layout.svelte + components/ + store.ts + style.css |
| Browser extension | ThemeRegistry 注册，ThemeHost 动态挂载 |

Host 仅提供数据加载和切换 UI，不包含任何布局组件。

---

## ThemePackage 接口

每个主题是一个 npm workspace 包，导出 `ThemePackage`：

```typescript
// packages/shared/src/theme-types.ts

interface ThemeManifest {
  name: string                          // "overview"
  displayName: string                   // "Overview"
  version: string
  description?: string
  author?: string
  data: Record<string, DataRequirement> // 数据源声明
  config?: Record<string, ConfigField>  // 配置 schema
  themes?: Record<string, ThemeColors>  // 可选：扩展主题色
}

interface ThemePackage {
  manifest: ThemeManifest
  default: typeof Layout.svelte         // 默认导出 = 主布局
  store?: (ctx: ThemeContext) => void   // 可选：初始化 store
  onActivate?: (ctx: ThemeContext) => void
  onDeactivate?: () => void
}
```

### ThemeManifest 数据声明

```json
{
  "name": "overview",
  "displayName": "Overview",
  "data": {
    "activities": { "source": "activities.json", "optional": false },
    "tracks": { "source": "tracks.json", "optional": true },
    "stats": { "source": "stats.json", "optional": true }
  },
  "config": {
    "defaultYear": {
      "type": "string",
      "default": "all",
      "description": "Default year filter"
    }
  }
}
```

Host 在挂载主题前根据 `data` 字段预取数据，通过 `ThemeContext.data` 传递给主题。

---

## ThemeRegistry

```typescript
// packages/web/src/lib/theme/registry.ts

class ThemeRegistry {
  static register(pkg: ThemePackage): void
  static lookup(name: string): ThemePackage | undefined
  static list(): ThemePackage[]
  static get active(): ThemePackage | null
  static setActive(name: string): Promise<void>  // 激活主题（数据加载→挂载）
}
```

### 发现方式

| 来源 | 加载时机 | 发现方式 |
|---|---|---|
| built-in themes | 编译时 Vite glob | `import.meta.glob('/packages/plugins/themes/*/src/manifest.json')` |
| npm packages | 显式 import | 用户在 App.svelte 中 `import` + `ThemeRegistry.register()` |
| directory drop-in | 编译时 Vite glob | `import.meta.glob('/plugins/themes/*/manifest.json')` |

---

## ThemeHost 生命周期

```
activate(name):
  ① ThemeRegistry 要求数据
  ② fetch(manifest.data[].source)               → data
  ③ loadConfig(name) + deepMerge(manifest.config) → config
  ④ const ctx = { data, config, theme: name, updateConfig, registerStore }
  ⑤ import ThemePackage.Layout (dynamic import)
  ⑥ <svelte:component this={Layout} context={ctx} />
  ⑦ pkg.onActivate?.(ctx)

deactivate():
  ① 卸载 Layout（svelte:component 自动清理）
  ② cleanupStores(name)
  ③ pkg.onDeactivate?.()
```

---

## ThemeContext

```typescript
// packages/shared/src/theme-types.ts

interface ThemeContext {
  data: Record<string, any>               // manifest.data 声明的数据
  config: Record<string, any>             // 用户配置（persisted）
  theme: string                           // 当前主题名
  themeName: string                       // 当前主题 displayName
  updateConfig: (patch: Record<string, any>) => void
  registerStore: (key: string, initial: any) => void
}
```

通过 Svelte `setContext('theme', ctx)` / `getContext('theme')` 在主题内任意组件获取。

---

## Host 壳

```svelte
<!-- packages/web/src/App.svelte -->
<script lang="ts">
  import { ThemeRegistry, ThemeHost } from './lib/theme'
  import ThemeSwitcher from './lib/theme/ThemeSwitcher.svelte'

  onMount(async () => {
    await ThemeRegistry.loadAll()       // ← Vite glob 发现
    const data = await fetchRequiredData()
    await ThemeRegistry.setActive(app.defaultTheme, data)
  })
</script>

<ThemeSwitcher />
<ThemeHost />
```

App.svelte 约 50 行。无 MapView/Drawer/DetailPanel 等引用。

---

## ThemeSwitcher

```svelte
<!-- packages/web/src/lib/theme/ThemeSwitcher.svelte -->
<select bind:value={app.activeTheme}>
  {#each ThemeRegistry.list() as theme}
    <option value={theme.manifest.name}>{theme.manifest.displayName}</option>
  {/each}
</select>
```

位置：App.svelte 左上角（目前 brand 文字处）。

---

## 主题内 Router

主题可能需要多个视图（如 running_page 的 `/` + `/summary`）。

不在宿主层做路由。主题内部通过 Svelte `$state` 切换视图：

```svelte
<!-- running_page Layout.svelte -->
<script lang="ts">
  let view = $state<'main' | 'summary'>('main')
</script>

{#if view === 'main'}
  <MainView onSwitch={() => view = 'summary'} />
{:else}
  <SummaryView onSwitch={() => view = 'main'} />
{/if}
```

主题 manifest 不声明路由——视图切换是主题内部实现细节。

---

## CSS 变量体系

Host 提供**基础设施 CSS 变量**（light/dark 色板、字体、间距），主题可覆盖或追加。

### Host 层（`web/src/app.css`）

```css
:root {
  --color-bg: #fafafa;
  --color-text: #1a1a1a;
  --color-accent: #4dd2ff;
  --color-surface: #ffffff;
  --color-border: #e5e5e5;
  --font-sans: -apple-system, BlinkMacSystemFont, sans-serif;
  --font-mono: 'IBM Plex Mono', monospace;
}
[data-theme='dark'] { /* 同上，深色值 */ }
```

Host 变量仅用于 ThemeSwitcher 和 loading 状态。主题自身视觉完全由主题 CSS 控制。

### 主题层

主题在 `style.css` 中覆盖或扩展：

```css
/* overview 主题 */
[data-theme='overview'] {
  --color-bg: #121212;
  --color-accent: #4DD2FF;
  --color-track: #4DD2FF;
}
```

主题通过 `onActivate` 回调在 host CSS 变量上追加覆盖：

```typescript
onActivate(ctx) {
  document.documentElement.setAttribute('data-theme', 'overview')
}
```

---

## 数据流

```
Ruby CLI (sync)
  ↓ 写入
data/activities.json + data/stats.json
  ↓ fetch (静态)
web/public/
  ↓
ThemeHost.loadData(manifest.data)
  ↓
ThemeContext.data.activities, ThemeContext.data.stats
  ↓
Layout.svelte → 组件树
```

主题不直接 fetch 数据。Host 按 manifest.data 声明预取，注入 ThemeContext。

---

## 文件结构

```
packages/
  web/src/
    App.svelte                    ← 50 行壳
    app.css                       ← 仅 CSS 变量
    lib/theme/
      registry.ts                 ← ThemeRegistry
      host.ts                     ← ThemeHost 生命周期
      ThemeSwitcher.svelte        ← 切换 UI
      ThemeHost.svelte            ← 挂载 <svelte:component>
  shared/src/
    theme-types.ts                ← 类型定义
  plugins/themes/
    overview/
      package.json
      src/
        manifest.json
        Layout.svelte
        components/...
        store.ts
        colorMode.ts
        style.css
    running_page/
      ...
```

---

## 类型定义清单（`packages/shared/src/theme-types.ts`）

```typescript
export interface DataRequirement {
  source: string
  optional?: boolean
}

export interface ConfigField {
  type: 'string' | 'number' | 'boolean' | 'string[]'
  default: any
  description?: string
}

export interface ThemeManifest {
  name: string
  displayName: string
  version: string
  description?: string
  author?: string
  data: Record<string, DataRequirement>
  config?: Record<string, ConfigField>
}

export interface ThemeContext {
  data: Record<string, any>
  config: Record<string, any>
  theme: string
  themeName: string
  updateConfig: (patch: Record<string, any>) => void
  registerStore: (key: string, initial: any) => any
}

export interface ThemePackage {
  manifest: ThemeManifest
  default: any  // SvelteComponent
  store?: (ctx: ThemeContext) => void
  onActivate?: (ctx: ThemeContext) => void
  onDeactivate?: () => void
}
```

---

## Manifest JSON Schema

```json
{
  "name": "running_page",
  "displayName": "Running Page",
  "version": "1.0.0",
  "description": "Two-column layout: stats sidebar + map/table. Ported from yihong0618/running_page",
  "author": "Lax",

  "data": {
    "activities": {
      "source": "activities.json",
      "optional": false
    },
    "tracks": {
      "source": "tracks.json",
      "optional": true
    },
    "stats": {
      "source": "stats.json",
      "optional": true
    }
  },

  "config": {
    "defaultView": {
      "type": "string",
      "default": "main",
      "description": "Default view: main or summary"
    }
  }
}
```

---

## 与 Ruby CLI 的关系

Ruby CLI 不感知主题系统。它继续：

- `workouts sync` → 写入 SQLite + `data/activities.json`
- `workouts export svg --style github` → CI/CD 生成海报

主题系统是前端概念。Ruby 端不需要改动。

```
                        ┌─────────────────────────┐
                        │   Ruby CLI (sync)        │
                        │   lib/workouts/          │
                        └────────┬────────────────┘
                                 │ writes JSON
                                 ▼
                        ┌─────────────────────────┐
                        │   data/activities.json   │
                        │   data/stats.json        │
                        └────────┬────────────────┘
                                 │ serves as static files
                                 ▼
                        ┌─────────────────────────┐
                        │   Frontend (Svelte SPA)  │
                        │   Host + Themes          │
                        └─────────────────────────┘
```
