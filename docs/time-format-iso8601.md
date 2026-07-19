# Time Format ISO 8601 — Standardization Plan

## Motivation

Three inconsistent time formats coexisting in the same `start_date` column cause silent parse errors and cross-source comparison bugs:

| Storage format | Used by | Problem |
|---|---|---|
| `"%Y-%m-%d %H:%M:%S"` naive, **actual UTC** | Strava, Keep, iGPSPORT, XOSS, XingZhe | No timezone info, but `Time.parse` on CST system (UTC+8) yields wrong epoch |
| `"%Y-%m-%d %H:%M:%S"` naive, **actual +0800** | AppleHealth | No timezone info AND wrong time — stored as local Beijing time |
| `"%Y-%m-%d %H:%M:%S"` naive, **source unspecified** | GarminBase (Garmin/GarminCN) | API returns `startTimeGMT` (should be UTC) but not forced |
| ISO 8601 with zone (`2024-01-15T10:30:00+08:00`) | LocalFile (GPX/TCX/FIT) | Format inconsistent with all other adapters |

## Target Format

| Column | Format | Example | Semantics |
|---|---|---|---|
| `start_date` | ISO 8601 UTC (Z suffix) | `"2026-06-25T11:49:17Z"` | Canonical UTC, sorted correctly by dictionary order |
| `start_date_local` | ISO 8601 with offset | `"2026-06-25T19:49:17+08:00"` | Local time at activity location |

Both are valid ISO 8601 → `Time.parse` on **any** system returns the correct epoch. No ambiguity.

## Adapter Changes

### Rule: replace `strftime("%Y-%m-%d %H:%M:%S")` with `.iso8601`

| Adapter | File:Line | Current | Changed to | Notes |
|---|---|---|---|---|
| **AppleHealth** | `lib/workouts/import/apple_health.rb:468-471` | `Time.parse(s).strftime("%Y-%m-%d %H:%M:%S")` | `Time.parse(s).utc.iso8601` | **Fix timezone bug**: Apple Health stores +0800 local, must convert to UTC. `start_date_local` (if `HKTimeZone` present): `Time.parse(s).iso8601` gives `+08:00` offset from input — correct. |
| **AppleHealth** | `lib/workouts/import/apple_health.rb:473-479` | `Time.parse(s)` for elapsed | `Time.parse(s).utc` | No format change (elapsed is computed), just ensure UTC arithmetic |
| **GarminBase** | `lib/workouts/sync/garmin_base.rb:~427-440` | `start_t.strftime(...)` where `start_t = parse_garmin_time(summary["startTimeGMT"])` | `start_t.utc.iso8601` | Defensive `.utc` — the `startTimeGMT` field name guarantees UTC, but code did not enforce it |
| **GarminBase** | same | `start_date_local` same as start_date | `start_t.iso8601` (no `.utc` conversion) | start_date_local with original offset from API |
| **Strava** | `lib/workouts/sync/strava.rb:155-167` | `start_t.strftime(...)` where `start_t = Time.parse(act["start_date"])` | `start_t.iso8601` | Strava API `start_date` is ISO 8601 with Z suffix already, `.iso8601` preserves it. `start_date_local` from `act["start_date_local"]` stays `.iso8601`. |
| **Keep** | `lib/workouts/sync/keep.rb:~264-296` | `start_date.strftime(...)` where `start_date = Time.at(start_time / 1000.0).utc` | `start_date.iso8601` | Already `.utc`, no behavior change |
| **iGPSPORT** | `lib/workouts/sync/igpsport.rb:155-170` | `start_t.strftime(...)` where `start_t = @fit_start_utc \|\| parse_date(act["startTime"])` | `start_t.iso8601` | `@fit_start_utc` already `.utc`. `parse_date` fallback needs `.utc` appended |
| **XOSS** | `lib/workouts/sync/xoss.rb:~239-255` | `start_t.strftime(...)` where `start_t = Time.at(act["start_timestamp"]).utc` | `start_t.iso8601` | Already `.utc`, no behavior change |
| **XingZhe** | `lib/workouts/sync/xingzhe.rb:~131-143` | `start_t.strftime(...)` where `start_t = Time.at(act["start_time"] / 1000.0).utc` | `start_t.iso8601` | Already `.utc`, no behavior change |
| **Parser::Base** | `lib/workouts/parser/base.rb:~119-133` | `t.iso8601` (already ISO 8601) | `t.utc.iso8601` | Defensive `.utc` — GPX/TCX parsers may produce non-UTC times if input has timezone offset |
| **LocalFile import** | caller side | uses Parser::Base `format_time` | same | No change needed, `format_time` already uses `.iso8601` |

### Summary of Changed Lines

Total: 8 files, ~10 line changes. All are single-line `strftime` → `.iso8601` replacements.

## Apple Health — Additional Changes

### `format_datetime` (apple_health.rb:468-471)

```ruby
# Before:
def format_datetime(str)
  return nil unless str
  Time.parse(str).strftime("%Y-%m-%d %H:%M:%S") rescue str
end

# After:
def format_datetime(str, utc: true)
  return nil unless str
  t = Time.parse(str) rescue nil
  return str unless t
  utc ? t.utc.iso8601 : t.iso8601
end
```

Usage:
- `start_date`: `format_datetime(start_date, utc: true)` → `"2026-06-25T11:49:17Z"` (convert +0800 → UTC)
- `start_date_local`: `format_datetime(start_date, utc: false)` → `"2026-06-25T19:49:17+08:00"` (preserve original +0800)

### `compute_elapsed` (apple_health.rb:473-479)

No format change needed, but the Time.parse → `.utc` ensures correct arithmetic regardless of system timezone.

### `generate_run_id` (apple_health.rb:520-524)

**Root cause:** 16 collision groups, 19 records lost. Cause is identical `sourceName + normalized_start + normalized_end` — Apple HealthKit duplicates the same workout entry when iCloud re-syncs. Need `creationDate` to disambiguate.

**Design rationale (7+4 split):**

```
base = MD5(sourceName|start|end)[0, 7]     ← 28 bits, identifies "same activity base"
disc = MD5(sourceName|creation|start|end)[0, 4]  ← 16 bits, disambiguates duplicates
run_id = base + disc                        ← 11 chars total, same length as before
```

- **base 7 hex chars** (28 bits): collision probability ~0.15% across 908 records. Collisions here are benign — they mean different activities that happen to share 28 bits from source+start+end. These are still distinguished by the 4-char disc suffix.
- **disc 4 hex chars** (16 bits, 4096 space): each collision group has at most 4 records with different creationDates. Probability of disc collision within a group: C(4,2)/4096 ≈ 0.15%.
- **Total:** effectively zero collisions across 908 records.

**Change:**

```ruby
# Before:
def generate_run_id(source_name, start_date, end_date)
  s = normalize_date(start_date)
  e = normalize_date(end_date)
  Digest::MD5.hexdigest("#{source_name}|#{s}|#{e}")[0, 11]
end

# After:
def generate_run_id(source_name, creation_date, start_date, end_date)
  s = normalize_date(start_date)
  e = normalize_date(end_date)
  c = normalize_date(creation_date)
  base = Digest::MD5.hexdigest("#{source_name}|#{s}|#{e}")[0, 7]
  disc = Digest::MD5.hexdigest("#{source_name}|#{c}|#{s}|#{e}")[0, 4]
  "#{base}#{disc}"
end
```

Caller (`process_workout_chunk`) already has `creationDate` in the Workout XML attribute. Extract and pass it.

```ruby
creation_date = workout["creationDate"]
run_id = generate_run_id(source_name, creation_date, start_date, end_date)
```

This ensures all 927 records get unique run_ids. The 19 duplicates are correctly imported as separate records, each with distinct creation dates. DedupService will match them later.

**Note on base grouping:** The first 7 characters of different records from the same activity share the same `base` prefix. This property is purely informational (human eyeball can quickly see "these records are the same activity") and is never used programmatically for grouping. DedupService uses `dedup_groups` table for group membership.

## Data Migration

### Goal: convert existing `start_date` values from naive format to ISO 8601

Since we cannot distinguish UTC vs +0800 in existing data (both are format-identical naive strings), we must use source-specific rules:

| Source | Rule | Rationale |
|---|---|---|
| `apple_health` | `Time.parse(start_date) → .utc.iso8601` | Existing naive dates are Beijing +0800, convert to UTC |
| `garmin`, `garmin_cn` | `Time.parse(start_date + " UTC") → .iso8601` | Existing naive dates are UTC |
| `strava`, `keep`, `igpsport`, `xoss`, `xingzhe` | `Time.parse(start_date + " UTC") → .iso8601` | Existing naive dates are UTC |
| `gpx`, `fit`, `tcx` (LocalFile) | Already ISO 8601 with zone, no conversion needed | Parser::Base already `.iso8601` |

### Migration script (idempotent, one-time):

```sql
-- Create a helper function approach:
-- In Ruby migration:
UPDATE activities SET
  start_date = CASE source
    WHEN 'apple_health' THEN
      strftime('%Y-%m-%dT%H:%M:%SZ', datetime(start_date, '-8 hours'))  -- +0800 → UTC
    ELSE
      strftime('%Y-%m-%dT%H:%M:%SZ', start_date)  -- already UTC, just reformat
    END,
  start_date_local = CASE 
    WHEN start_date_local IS NOT NULL THEN
      CASE source
        WHEN 'apple_health' THEN
          strftime('%Y-%m-%dT%H:%M:%S+08:00', start_date_old)  -- preserve +0800
        ELSE
          strftime('%Y-%m-%dT%H:%M:%S+08:00', start_date_old)  -- convert UTC→+0800 if local data exists
      END
    ELSE NULL
    END;
```

**Important:** `start_date_local` for non-apple_health sources was previously set to the same UTC value as `start_date`. After migration, `start_date_local` should reflect actual local time where available:
- Strava: API provides `start_date_local` (already correct)
- iGPSPORT: `@fit_start_local` (already correct)
- Others: same as start_date (no local time available)

## Compatibility Layer

After migration, all code that reads `start_date` will encounter:
- New records: ISO 8601 with Z suffix
- Old migrated records: ISO 8601 with Z suffix (same format)
- No legacy naive format remains

**However**, during transition (before migration runs), reader code must be compatible. `Time.parse` handles both formats natively, so no special compatibility is needed. But DedupService's `parse_time` should be confirmed safe:

```ruby
def parse_time(val)
  return nil unless val
  Time.parse(val.to_s)  # Handles "2024-01-15 10:30:00" AND "2024-01-15T10:30:00Z" AND "2024-01-15T10:30:00+08:00"
rescue
  nil
end
```

✅ Already correct. No compatibility layer needed for read.

## Write path: Detection After Migration

Once migration completes and adapters output ISO 8601:
- No old code writes naive format → all new data is ISO 8601
- Migration is one-way, no rollback needed
- Future adapters must follow the same contract

## Impact Scope

| Consumer | Impact | Notes |
|---|---|---|
| **DedupService** | `parse_time` handles both formats natively | Low, no code change |
| **Export::JSON** | `start_date` serialized as-is | JSON consumers see ISO 8601 (improvement) |
| **Export::CSV** | `start_date` serialized as-is | CSV readers get unambiguous dates |
| **Export::SVG** | date formatting may need update | SVG date labels should parse → reformat |
| **Export::Stats** | date grouping unchanged | Time.parse handles both |
| **Export::GPX** | re-export from L2 files | L2 files use ISO 8601, no change |
| **Frontend** | JS `Date.parse` handles ISO 8601 natively | Actually an improvement — no need to assume UTC |
| **DB constraints** | TEXT column, no schema change | None |
| **Backup compatibility** | Old backup still loads | Migration script handles conversion |
