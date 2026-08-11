# XOSS — Implementation Notes

> **已迁移至 git-fit gem（`git fit sync --source xoss`）。** 本地薄壳仅保留 XOSS 适配器用于交互式 auth。以下为迁移前的实现历史记录，`lib/workouts/sync/xoss.rb` 等路径指向已删除的本地文件。

## Commands

```
git fit sync --source xoss              # Sync all XOSS activities
git fit sync --source xoss --act ride   # Sync only ride activities
```

## Files

| Path | Role |
|---|---|
| `lib/workouts/sync/xoss.rb` | Sync adapter |
| `lib/workouts/cli/sync.rb` | CLI registration + source_configured? |
| `lib/workouts/cli.rb` | `--source` / `auth` help text |
| `lib/workouts/sync/strava.rb:10` | Duplicate source list |
| `spec/sync/xoss_spec.rb` | 23 tests (all stubbed, zero network) |
| `spec/fixtures/xoss/login_response.json` | JWT login response fixture (synthetic) |
| `spec/fixtures/xoss/login_response_real.json` | Real login response (masked) |
| `spec/fixtures/xoss/login_error_response.json` | Login error: invalid credentials |
| `spec/fixtures/xoss/refresh_response.json` | Refresh success response (masked) |
| `spec/fixtures/xoss/refresh_error_response.json` | Refresh error: expired token |
| `spec/fixtures/xoss/activity_list_page.json` | Paginated list fixture (synthetic) |
| `spec/fixtures/xoss/activity_list_real.json` | Real activity list (masked) |
| `spec/fixtures/xoss/activity_list_error.json` | Activity list: invalid access token |
| `spec/fixtures/xoss/fit_sample.56751769.fit` | Real FIT file (268 GPS points) |
| `.github/workflows/sync.yml` | CI: token cache restore/save |
| `.github/actions/data-store/{restore,save}/action.yml` | CI: raw/std cache per source |

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

error response (HTTP 400, code 10301):
```json
{"code":10301,"data":{"non_field_errors":"No active account found with the given credentials"},"msg":"Invalid input."}
```

### Token Refresh

`POST /api/v1/jwt-token/refresh/` with body `{"refresh":"..."}`

Response body (success, rotated tokens):
```json
{"code":0,"data":{"access":"eyJ...","refresh":"eyJ..."},"msg":"Success"}
```

Error codes:
- 10401: "Token is invalid or expired" (HTTP 400)

Token rotation: each refresh call returns a **new** refresh token (old one invalidated).

### Activity List

`GET /api/v3/activity/?offset=N&limit=M`

Error response (HTTP 401, invalid/expired access token):
```json
{"code":10001,"data":{"detail":"Given token not valid for any token type","code":"token_not_valid","messages":{"token_class":"AccessToken","token_type":"access","message":"Token is invalid or expired"}},"msg":"Token is invalid or expired"}
```

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

git-fit default: `data/auth/xoss/tokens.json`

```json
{
  "access": "eyJ...",
  "refresh": "eyJ...",
  "expires_at": 1783173275
}
```

`expires_at` is a Unix timestamp. Calculated as `Time.now.to_i + 86400` (24h).  
The XOSS API does NOT return `expires_in` — it'\''s hardcoded (unlike Garmin which reads `expires_in` from the API response).

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

- **After**: full FIT download → GPS decode → std JSON → polyline → sensor fields.

## Verification Log

### 2026-07-26: Auth debug — 3 paths validated + 6 fixtures from real API

**3 auth paths tested:**

| Path | Condition | Trigger | HTTP |
|---|---|---|---|
| cached token | load_tokens + access_token_valid? | Second run (token file exists) | 0 |
| refresh | access expired, refresh valid | Manually set expires_at=1 | POST `/refresh/` → 200 |
| login | no cache / all expired | First run (no token file) | POST `/jwt-token/` → 200 |

**6 fixtures captured from real API:**

| Fixture | Scenario | HTTP | Key fields |
|---|---|---|---|
| `login_response_real.json` | Login success | 200 | `code:0`, `data.access`, `data.refresh`, `data.email`, `data.username` |
| `login_error_response.json` | Login: bad credentials | 400 | `code:10301`, `data.non_field_errors`, `msg:"Invalid input."` |
| `refresh_response.json` | Refresh success | 200 | `code:0`, `data.access`, `data.refresh` (both rotated) |
| `refresh_error_response.json` | Refresh: expired token | 400 | `code:10401`, `msg:"Invalid input."` |
| `activity_list_real.json` | List: valid token | 200 | `code:0`, `data.count`, `data.results[]` |
| `activity_list_error.json` | List: invalid token | 401 | `code:10001`, `data.code:"token_not_valid"`, `data.messages.token_type:"access"` |

**Findings from real API:**
- Activity list error returns `code:10001` not `10301` — token errors have distinct codes
- Refresh rotates BOTH access and refresh (confirmed real behavior)
- Refresh response structure differs from login: has `data.access` + `data.refresh` but NOT `data.email`/`data.username`/`data.id`
- Access token error response includes `token_class`, `token_type`, `message` in `data.messages`
- Activity list `count` field is an integer (not null as initially observed — first page with `limit=1` returned null, re-test with full dataset returned integer)

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
| 2026-07-26 | Auth debug: 3 auth paths validated (login/refresh/cached). 6 real-API fixtures captured. Error message handling added. Documented token_path disparity, expires_in absence, error code taxonomy. |
