# Data Architecture — L1/L2/L3/L4/L5

分层隔离 raw 源数据 / 标准化 GPS / 摘要库 / 发布素材 / 部署物。

## Layers

| Layer | Name | Content | Stage | Format | Path |
|---|---|---|---|---|---|
| L1 | Source Archive | API data, minimal decode, no field loss | Sync | .fit / .raw.json | data/raw/{source}/ |
| L2 | Standardized | WGS-84 + unified schema, all fields preserved | Sync | .json | data/std/{source}/ |
| L3 | Summary DB | polyline + stats (distance/time/HR) | Sync | SQLite | data/workouts.db |
| L4 | Build Artifacts | JSON/CSV/SVG/HTML export | Build | .json / .svg / .csv / .html | build/ |
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

## Source adapter matrix

| Source | L1 | L2 | L3 | Status |
|---|---|---|---|---|
| iGPSPORT | {id}.fit | std/igpsport/{id}.json | done | completed |
| Keep | data/raw/keep/{id}.json (transitional) | std/keep/{id}.json | done | transitional |
| Strava | {id}.json | std/strava/{id}.json | done | completed |
| XingZhe | {id}.json | std/xingzhe/{id}.json | done | completed |
| Future sources | required | required | required | mandatory |
