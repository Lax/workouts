# Frontend Architecture — Goal

## Problem

Dashboard 当前是 Ruby 字符串模板内嵌 ~350 行 vanilla JS + ~170 行 CSS。每次改 UI 都改 Ruby 文件，无法复用逻辑，无法扩展到大前端（移动端 / 桌面端）。

## Decision

前后端分离。后端保持 Ruby CLI（sync / dedup / migrate），前端独立为 Svelte SPA。

| 层级 | 技术 | 职责 |
|---|---|---|
| shared/ | TypeScript | 纯函数：类型定义、统计计算、polyline 编解码、SVG 生成 |
| web/ | Svelte 5 + Vite | Dashboard SPA、SVG 预览/下载 |
| mobile/ | 未来决定 | 复用 shared/ |

## Why Svelte

- 代码量最少：同页面比 React 少 ~30% 样板
- 内建响应式：filter/sort 用 `$:` derived store，无需状态管理库
- 本 SPA 规模（1 个页面，3 个 store）不需要框架运行时做任何复杂优化
- Leaflet + ECharts 都是命令式 API，Svelte 的 `onMount`/`onDestroy` 直接封装，不需要 react wrapper 那一层抽象
- CSS：内建 scoped `<style>` + 全局 `app.css`，不引入 Tailwind

## Why npm workspaces

- 3-4 个 package，pnpm 的严格隔离和硬链接无收益
- CI 零配置（GitHub 自带 npm）
- 已经是现有的包管理器

## Why shared/ stays workspace-only

- 当前没有 monorepo 外部的消费者
- 未来有 mobile app 时再加 publish 步骤，成本 30 分钟
- 避免提前的 semver / npm token / CI publish 维护

## Why no API layer

- 数据是 CLI 每日同步生成的静态 JSON
- Dashboard 一次性加载全部数据，不需要分页/筛选后端
- SPA 直接 `fetch('activities.json')`（摘要）+ `fetch('tracks.json')`（polyline 映射，延迟加载）

## Why SVG moves to frontend

- SVG 生成是纯计算，浏览器 V8 比 CRuby 快 10-50x
- 用户可以在浏览器换主题后实时重绘 SVG，不依赖 CLI
- 下载/分享功能在前端用 `<a download>` 即可

## Why Not

| 放弃的方案 | 理由 |
|---|---|
| React | 本规模不需要 virtual DOM 优化，Leaflet/ECharts 的命令式 API 在 React 里反而需要额外的 ref forwarding |
| Vue | `vue-leaflet` 仍 pre-v1，API 不稳定 |
| pnpm | 3 个包，工具链额外成本无收益 |
| Tailwind | 全局 CSS 已写完（170 行），Tailwind 的 purge / 构建配置是过度抽象 |
| Astro / Next | SSR 对纯静态 SPA 无意义 |
| API layer | 当前无动态数据需求 |

## Future

- `npm publish shared` — 当有第一个 mobile consumer 时
- `npm publish svelte-echarts` / `svelte-leaflet` — 通用化后去掉 `@workouts/` scope
- 多页面 SPA / 路由 — 如需新增页面，加 `svelte-spa-router`
