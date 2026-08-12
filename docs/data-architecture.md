# Data Architecture — L1/L2/L3/L4/L5

分层隔离 raw 源数据 / 标准化 GPS / 摘要库 / 发布素材 / 部署物。

## Layers

| Layer | Name | Content | Stage | Format | Path |
|---|---|---|---|---|---|
| L1 | Source Archive | API data, minimal decode, no field loss | Sync | .fit / .raw.json | data/raw/{source}/ |
| L2 | Standardized | WGS-84 + unified schema, all fields preserved | Sync | .json | data/std/{source}/ |
| L3 | Summary DB | polyline + stats (distance/time/HR/cadence/power/temp) | Sync | SQLite | data/db/workouts.db |
| L4 | Build Artifacts | activities.json (summary) + tracks.json (polyline map) + stats.json + SVG/CSV/HTML | Build | .json / .svg / .csv / .html | site/ |
| L5 | Deploy | website + GPX track download | Deploy | HTML/CSS/SVG/JS / .gpx | Pages URL / gpx_out/ |

## Dependencies

```
L1 -> L2 -> L3 -> L4 (build job)
  |         |
  |         +-> export gpx -> web download
  |
  +-- L1 is source of truth for L2 rebuild (algorithm change)
```

## L1 -> L2 rules

- Coordinate conversion (semicircle -> degree, GCJ-02 -> WGS-84).
- Time normalization (FIT epoch / millisecond -> Unix).
- No field dropped, no aggregation, no stats computed.

## GH Cache 辅助层

`data/raw/{source}/` + `data/std/{source}/` 通过 `git-fit-actions/data-store/cache/{restore,save}@v2` 按源独立管理：
- key: `GitFit-data-{source}-v0-{run_id}`，前缀回退 `GitFit-data-{source}-v0-`
- 保留 7 天，`git-fit-actions/data-store/cache/save@v2` 内联 `find | sort | xargs sha256sum` 计算 SHA256SUMS 检测变化，仅变动的源写 cache
- cache miss → API 全量重拉（受 `time_budget` 限制，1-3 次 CI run 补齐）

> 2026-08 变更：per-source cache（见 CONTEXT.md「关键技术决策」），旧 `workouts-raw-v1-*` 单 key 模式已废弃。

## Source adapter matrix

| Source | L1 | L2 | L3 | Status |
|---|---|---|---|---|
| iGPSPORT | {id}.fit | std/igpsport/{id}.json | done | completed |
| Keep | data/raw/keep/{id}.json (transitional) | std/keep/{id}.json | done | transitional |
| Strava | {id}.json + {id}/ (web 原始文件，服务器原名) | std/strava/{id}.json | done | completed |
| XingZhe | {id}.json | std/xingzhe/{id}.json | done | completed |
| Future sources | required | required | required | mandatory |
