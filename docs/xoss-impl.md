# XOSS — Implementation Notes

## Commands

```
workouts sync --source xoss              # Sync all XOSS activities
workouts sync --source xoss --act ride   # Sync only ride activities
```

## Files

| Path | Role |
|---|---|
| `lib/workouts/sync/xoss.rb` | Sync adapter |
| `lib/workouts/cli/sync.rb` | CLI registration + source_configured? |
| `lib/workouts/cli.rb` | `--source` / `auth` help text |
| `lib/workouts/sync/strava.rb:10` | Duplicate source list |
| `spec/sync/xoss_spec.rb` | 23 tests (all stubbed, zero network) |
| `spec/fixtures/xoss/login_response.json` | JWT login response fixture |
| `spec/fixtures/xoss/activity_list_page.json` | Paginated list fixture (2 activities) |
| `spec/fixtures/xoss/fit_sample.56751769.fit` | Real FIT file (268 GPS points) |
| `.github/workflows/sync.yml` | CI: token cache restore/save |
| `.github/actions/data-store/sources-cache/*/action.yml` | CI: raw/std cache per source |

## API Discovery

### Authentication

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/jwt-token/` | POST | Login (email + password) → JWT pair |
| `/api/v1/jwt-token/refresh/` | POST | Refresh access token (rotates both tokens) |

Response body:
```json
{
  "code": 0,
  "data": {
    "access": "eyJ...",     // 24h TTL
    "refresh": "eyJ...",    // 7d TTL
    "id": 1103050,
    "username": "XOSS#DF0663",
    "email": "user@example.com"
  }
}
```

Token rotation: each refresh call returns a **new** refresh token (old one invalidated).

### Activity List

`GET /api/v3/activity/?offset=N&limit=M`

Paginated list with summary fields. Key fields:

| Field | Type | Notes |
|---|---|---|
| `id` | int | Platform activity ID |
| `fit_file_hash` | string | UUID v5 — presence indicates FIT is available |
| `sport` | int | Mapped via `SPORT_MAP` |
| `distance` | float | Meters |
| `duration` | float | Seconds |
| `start_timestamp` | int | Unix epoch |
| `total_calories` | int | kcal |
| `thumbnail_url` | string | 302 → OSS jpeg |
| `fileid` | object | { number, product, productName, timeCreated, manufacturer, serialNumber } |

### FIT File Download

`GET /api/v3/activity/{id}/fit_file/` → **302 redirect** → OSS signed URL

The redirect points to Alibaba Cloud OSS:
```
xoss-production-private.oss-us-west-1.aliyuncs.com/activity_fit_files/{year}/{month}/{id}.fit
  ?AWSAccessKeyId=...
  &Signature=...
  &Expires=...
```

- OSS bucket is **private** — access only via signed URL (1h expiry)
- FIT is original device upload (no GPS loss)
- Downloads are direct (no proxy) — OSS is US West, proxy is for China

### Thumbnail

`GET /api/v3/activity/{id}/thumbnail/` → 302 → public OSS jpeg

### Stream / GPS Endpoints

XOSS (international, `backend.xoss.co`) does **not** expose a REST stream/GPS endpoint like XingZhe (`/api/v1/pgworkout/{id}/stream/`). GPS data is only available via the original FIT file.

### Web App

The XOSS web app at `www.xoss.co` is a Vue.js SPA. The JS bundle (`static/js/app.*.js`) reveals only 4 API paths:
- `/api/v1/jwt-token/`
- `/api/v1/jwt-token/refresh/`
- `/api/v2/athlete/`
- `/api/v3/activity/`

No additional GPS/stream endpoints were found in the client-side code.

## Token Caching

Follows Garmin's pattern (`GarminBaseDI#save_tokens` / `#load_tokens`).

### File

`data/cache/xoss_tokens.json`

```json
{
  "access": "eyJ...",
  "refresh": "eyJ...",
  "expires_at": 1783173275
}
```

### Authentication Chain

```
authenticate:
  ① load_tokens + access_token_valid?  → use cached access token
  ② refresh_access_token               → POST refresh/ → new pair + save
  ③ login (email + password)           → POST jwt-token/ → save tokens
```

| Token | TTL | Rotation |
|---|---|---|
| access | 24h | On refresh |
| refresh | 7d | Rotated on every use |

### Rationale

7d refresh is not worth the complexity of full OAuth refresh management (compared to Garmin's 90d). But caching avoids redundant email+password login on daily sync runs. After 7 days, the chain falls through to login automatically.

## Data Flow

```
sync_activities
  │
  ├─ fetch_page (paginated)
  │    └─ existing_run_ids + raw_file_exists? → skip / backfill
  │
  └─ process_activity
       │
       ├─ Build summary attrs from API response
       ├─ fit_file_hash present?
       │    ├─ download_fit (302 → OSS → raw binary)
       │    ├─ write_raw (temp→rename atomically)
       │    ├─ FIT::Decoder.decode → GPS records
       │    ├─ write_std (standardized JSON)
       │    ├─ Geo::Polyline.encode → summary_polyline
       │    └─ compute_sensor_summary → HR/cadence/power/temp
       │
       └─ upsert_activity (DB)
```

### Backfill Support

Activities already in DB but missing raw files are automatically re-processed:
```
next if existing.include?(act_id) && raw_file_exists?(act_id)
```

### Time Budget

Each activity checks `time_expired?` before processing. Budget is set via:
- `SYNC__TIME_BUDGET` env var
- `sync.time_budget` in config.yml

## Key Decisions

| Decision | Rationale |
|---|---|
| OSS download direct (no proxy) | OSS is US West, proxy is for China. Direct is faster. |
| FIT download via Net::HTTP (not http_request) | HTTP request uses proxy for API calls; OSS doesn't need it. |
| `FIT::Decoder.decode` in begin/rescue | Prevent corrupt FIT from crashing entire sync batch. |
| Retry 2x on timeout | Transient network failures are common with cross-border API calls. |
| `calories` from API, not FIT | FIT record messages don't contain reliable calories. |
| No token cache for CI | 24h access + 7d refresh → token file cached via actions/cache. |

## Sensor Fields

| Field | Source | Notes |
|---|---|---|
| average_temperature | FIT record | °C, from device sensor |
| average_heartrate | FIT record | bpm, only if HR monitor paired |
| average_cadence / max_cadence | FIT record | rpm, only if cadence sensor paired |
| average_power / max_power | FIT record | watts, only if power meter paired |
| calories | API `total_calories` | kcal, from device computation |

Tested real FIT file (XingZhe G2 N5 device): temperature 16.2°C, no HR/cadence/power.

## Changes from Summary-Only

- **Before**: adapter only called `process_activity` with API summary → upsert to DB. No raw/std/polyline.
- **After**: full FIT download → GPS decode → std JSON → polyline → sensor fields.

## Change Log

| Date | Change |
|---|---|
| 2026-07-03 | Initial summary-only adapter (email+JWT, no raw) |
| 2026-07-03 | API discovery: fit_file/ endpoint + OSS storage |
| 2026-07-03 | JWT token caching (load/save/refresh) |
| 2026-07-03 | Proxy support for China API access |
| 2026-07-03 | FIT download + decode pipeline |
| 2026-07-03 | Adversarial review: rescue FIT decode, calories, retry logic |
| 2026-07-03 | CONTEXT.md + config_template updated |
