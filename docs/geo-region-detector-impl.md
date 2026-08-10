# Geo Division Detector — Implementation Notes

## Overview

Post-sync step that detects administrative divisions (province/city/district/township) for activities with GPS polyline data. Results are stored in DB and exported to frontend JSON.

## Data Flow

```
sync → workouts geo detect → DB[divisions] → export json → activities.json[divisions]
                                                                    ↓
                                                             StatsPanel reads directly
```

## DB Field

`divisions TEXT` — JSON array of division objects:

```json
[
  {"p":"上海市","c":"上海市","d":"松江区","t":"广富林街道","v":"","l":"上海外国语大学","w":0.625},
  {"p":"江苏省","c":"苏州市","d":"昆山市","w":0.375}
]
```

| Key | Meaning | Level | Required |
|-----|---------|-------|----------|
| `p` | province | 1 | ✅ |
| `c` | city | 2 | |
| `d` | district | 3 | |
| `t` | township/street | 4 | |
| `v` | village/community | 5 | |
| `l` | specific location (venue, school, etc.) | 6 | |
| `w` | weight (0-1, proportion of sampled GPS points) | — | ✅ |

## Cache Files

```
data/cache/
└── geo-point.jsonl           # JSONL: coord → geocode result (per-point API cache)
```

### Point Cache Format (`geo-point.jsonl`)

```jsonl
{"ck":"31.0123,121.4567","p":"上海市","city":"上海市","dist":"松江区","source":"amap"}
```

- `ck`: coordinate key `"lat,lng"`
- Per-provider: AMap returns detailed Chinese admin, Nominatim returns country/state

## Sampling

- GPS points sampled at 0.01° intervals (~1km)
- Each sampled coordinate looked up in point cache first
- Cache miss → API call → cache append
- Results aggregated into divisions with proportional weights

## API Providers

| Region | Provider | API | Requires Key |
|--------|----------|-----|-------------|
| China (73-135E, 18-54N) | AMap | `restapi.amap.com/v3/geocode/regeo` | `AMAP_API_KEY` |
| Non-China | Nominatim (OSM) | `nominatim.openstreetmap.org/reverse` | No |

## Keep Activities

- `summary_polyline == "gqqrFurkeU??"` matches Keep's `PLACEHOLDER_POLYLINE` → skipped
- `location_country == "0"` → no GPS data → skipped

## CLI

```bash
workouts geo detect
workouts geo detect --limit 50
workouts geo detect --batch 20 --strategy proportional --time 300
workouts geo detect --dry-run
```

## Workflow Cache Key

- Restore: `actions/cache/restore`，`key: {cache_key}` 精确尝试，`restore-keys: workouts-geo-v1-` 前缀兜底命中最新条目
- Save: `{cache_key}-{content_hash}`（`cache_key` 含 migration hash，`content_hash` 为 cache 目录内三个文件 `amap-points.jsonl`/`nominatim-points.jsonl`/`SHA256SUMS` 的复合哈希）

Save 仅在 `content_hash` 与 restore 到的 key（`cache-matched-key`）不匹配时触发——数据变化 → 哈希变 → 存新 key；数据未变 → 跳过，避免冗余 cache。

Migration version 在 key 中确保 schema 变更可手动 bump 命名空间强制失效 cache。

## Admin Level Roadmap

Current: province (p), city (c), district (d), township (t)
Reserved: village (v), location (l)
Not yet implemented: county-level city distinction, special admin zones
