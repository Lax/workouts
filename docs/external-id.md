# External ID — Cross-Source Exact Matching

## Motivation

Cross-source duplicate detection currently relies entirely on heuristic matching (time + distance + duration + sport_category comparison). This is expensive, imprecise, and cannot achieve confidence=1.0. An exact match via a shared external identifier would make dedup deterministic for certain source pairs.

## Source Identifier Survey

### Platform-level IDs (used for `run_id`)

| Source | `run_id` suffix | Type | Scope |
|---|---|---|---|
| Garmin Intl | `activityId` (numeric) | Platform internal | Garmin Connect only |
| Garmin CN | `activityId` (numeric) | Platform internal | Garmin Connect CN only |
| Strava | `id` (numeric) | Platform internal | Strava only |
| Keep | `keep_id` (compound → numeric) | Platform internal | Keep only |
| iGPSPORT | `rideId` (numeric) | Platform internal | iGPSPORT only |
| XOSS | `id` (numeric) | Platform internal | XOSS only |
| XingZhe | `id` (numeric) | Platform internal | XingZhe only |
| Apple Health | MD5(content hash) | Computed | Apple Health only |
| GPX/FIT/TCX import | SHA256(content hash) | Computed | Local files only |

None of these are shared between platforms. Cross-source exact matching is impossible via native `run_id`.

### Cross-source identifiers

| Identifier | Present in | Absent from | Type |
|---|---|---|---|
| **HKExternalUUID** | Apple Health (Strava-sourced workouts: 27/27) | Apple Health (Keep/Connect/Apple Watch/etc: 0/880) | UUID from HealthKit |
| **Strava API external_id** | Strava API `detail.external_id` (value matches HKExternalUUID for AH-synced activities) | Garmin, Keep, iGPSPORT, XOSS, XingZhe APIs | Echo of HealthKit UUID |
| Strava API `upload_id` | Strava API `detail.upload_id` | All other sources | Upload fingerprint |
| XOSS `fit_file_hash` | XOSS API conditionally (SHA256 of FIT) | All other sources | FIT content fingerprint |
| Human `id` (metadata) | Apple Health Human-sourced workouts (68/68) | All other sources | Human app internal ID |
| HealthKit `creationDate` | Apple Health all workouts (908/908) | All other sources | HealthKit creation timestamp |

### Key findings

1. **HKExternalUUID is the only true cross-source identifier.** It originates from Apple HealthKit when any app writes a workout. Strava's API echoes it back as `external_id`. No other source API provides it.

2. **Strava is the only sync adapter with a usable external_id path.** Garmin, Keep, iGPSPORT, XOSS, XingZhe do not store or expose HealthKit UUIDs.

3. **Within apple_health, HKExternalUUID covers only Strava-sourced workouts.** Sources without UUID (Keep, Connect, Apple Watch, Nike Run Club, Human, iGPSPORT, XOSS, XingZhe) account for 880/908 records. No external_id exists for these.

4. **XOSS `fit_file_hash` is the closest alternative** — a SHA256 hash of the raw FIT file. If two sources upload the exact same FIT file (e.g., Garmin Edge FIT → XOSS), the hash would match. But in practice, sources reprocess and re-encode the data, changing the hash.

## Schema

```sql
ALTER TABLE activities ADD COLUMN external_id TEXT;
```

Unique index (nullable, allows duplicates because not all records have external_id):

```sql
CREATE INDEX idx_activities_external_id ON activities(external_id);
```

## Implementation

### Apple Health import (`lib/workouts/import/apple_health.rb`)

`extract_metadata` already captures all `<MetadataEntry>` elements including `HKExternalUUID`. But `build_attrs` does not pass it to DB.

**Change in `build_attrs`** (line 445-466):

```ruby
attrs = {
  # ... existing fields ...
  source: "apple_health",
  external_id: meta["HKExternalUUID"]   # NEW: "strava://activities/3056096737"
}
```

### Strava adapter (`lib/workouts/sync/strava.rb`)

The `fetch_detail` response contains `external_id` and `upload_id`. Current code parses the detail JSON for summary_polyline, but does not extract these fields.

**Change in `process_one`** — after fetch_detail:

```ruby
detail = fetch_detail(summary["id"])
if detail
  external_id = detail["external_id"]  # "544EA64D-4645-4BBC-9147-638B642FCFE1"
  # store for build_attrs
end
```

And in `build_attrs` (line 155-167), pass the value:

```ruby
attrs = {
  # ... existing fields ...
  external_id: @current_external_id,  # "544EA64D-4645-4BBC-9147-638B642FCFE1"
}
```

### DedupMatcher (`lib/workouts/dedup/matcher.rb`)

**New method: exact match channel.**

```ruby
def self.external_id_match(a, b)
  a_eid = a[:external_id]
  b_eid = b[:external_id]
  return nil if a_eid.nil? || b_eid.nil?
  return nil if a_eid.empty? || b_eid.empty?

  # Strava external_id is HKExternalUUID: "544EA64D-4645-4BBC-9147-638B642FCFE1"
  # AH HKExternalUUID is also: "544EA64D-4645-4BBC-9147-638B642FCFE1"
  # But AH also stores it as "strava://activities/{id}"
  # So both formats need comparison.
  a_normalized = a_eid.sub(%r{^strava://activities/}, "")
  b_normalized = b_eid.sub(%r{^strava://activities/}, "")

  if a_normalized == b_normalized
    { confidence: 1.0, flag: "derived", source: "external_id" }
  end
end
```

**Integration into `Dedup::Matcher.match`:**

```ruby
def self.match(a, b)
  # Phase 1: Exact match via external_id
  exact = external_id_match(a, b)
  return exact if exact

  # Phase 2: Heuristic match (existing logic)
  # ... time, distance, duration, sport comparison ...
end
```

## AH↔Strava Comparison Analysis

### Why AH may be the better source for certain fields

| Field | Strava API | AH (Strava source) | Worse or better? |
|---|---|---|---|
| `summary_polyline` | ~1500 points (API polylines decode to ~1500 points for 2h ride) | 3000-8000 points (GPX raw data, 1pt/s) | **AH better** (higher resolution) |
| `average_heartrate` | 142 bpm (from device) | 140 bpm (from HealthKit correlation) | Neck-and-neck |
| `max_heartrate` | 168 bpm | 165 bpm | Neck-and-neck |
| `moving_time` | 3645s (with pause filtering) | 3840s (no pause filtering, elapsed-like) | **Strava better** |
| `average_power` | 185w (power meter) | nil (no power in HealthKit) | **Strava better** |
| `average_cadence` | 78 rpm | nil | **Strava better** |
| `average_temperature` | nil | 28°C (from Apple Weather) | **AH better** |
| `elevation_gain` | 312m (barometric) | 318m (GPS-based) | Neck-and-neck |
| `calories` | 850 kcal (algorithm) | 830 kcal (HealthKit active+basal) | Neck-and-neck |
| `distance` | 12.3 km | 12.3 km | Same |
| GPS coordinate count | ~1500 decoded points | ~3000-8000 raw points | **AH better** (~2-5x more) |

### Merge Strategy

After exact match, the composite record uses:

| Field | Primary source | Rationale |
|---|---|---|
| `distance` | Both (mean) | Both use GPS, <1% typical deviation |
| `moving_time` | Strava | AH has no pause filtering |
| `elapsed_time` | Strava | AH elapsed from duration tag, low confidence |
| `average_heartrate` | Both (mean) | <3 bpm typical deviation |
| `max_heartrate` | Both (max) | Higher value more accurate |
| `average_power` | Strava | Power meter data not in HealthKit |
| `average_cadence` | Strava | Not in HealthKit |
| `summary_polyline` | AH | Higher resolution |
| `elevation_gain` | Both (median) | Barometric vs GPS, take middle |
| `calories` | Both (median) | Algorithm-dependent |
| `average_temperature` | AH | Not in Strava API |
| `average_speed` | Computed | distance / moving_time |

### Analysis Script

To confirm the merge strategy quantitatively, run a comparison across all 27 AH↔Strava pairs:

```ruby
# pseudo-code
matched_pairs = join AH_records(external_id NOT NULL), Strava_records(external_id NOT NULL) ON external_id
matched_pairs.each do |ah, strava|
  fields.each do |f|
    ah_val = ah[f]
    st_val = strava[f]
    diff = (ah_val - st_val).abs / [ah_val, st_val].max
    stats[f][:ah_count] += 1 if ah_val
    stats[f][:strava_count] += 1 if st_val
    stats[f][:diff_sum] += diff if ah_val && st_val
  end
end
```

Output: per-field availability matrix + deviation distribution.

## Non-Strava Sources: Current Limitations

| Source | Why external_id does not apply | Future possibility |
|---|---|---|
| Keep | No HealthKit UUID in export.xml, no API external_id | None identified |
| Connect (Garmin) | Workouts synced to HealthKit via Garmin Connect app, no UUID in export | None |
| Apple Watch (native) | No UUID, no external API | None |
| Nike Run Club | No UUID | None |
| Human | Has `id` metadata but Human app is defunct (68 records) | Could use Human `id` as external_id but no cross-ref target |
| iGPSPORT | No UUID, no API external_id | None |
| XOSS | Has `fit_file_hash` (SHA256 of FIT) | Could match if same FIT file exists in another source |
| XingZhe | No UUID, no API external_id | None |

## `dedup_group_id` — Computed Memoized Cross-Reference

Since true external_id is Strava-only, for all other sources we use a **computed** group ID after heuristic matching:

```sql
ALTER TABLE activities ADD COLUMN dedup_group_id TEXT;
```

After the first DedupService run finds match (garmin_12345, apple_health_a1b2c3, keep_98765 belong together):

- Compute: `SHA256(sorted_run_ids_concat)[0, 16]`
- Write `dedup_group_id = "a1b2c3d4e5f67890"` to all three records
- Next DedupService run: compare only by `group_id IS NULL` records, match new records to existing groups

This serves as a computed external_id — once heuristic matching confirms kinship, subsequent runs use it as exact match with O(1) lookup.

## Summary

```
external_id: ONLY Strava ↔ Apple Health
  └─ 27 exact-match pairs (of 2103 total)
  └─ confidence = 1.0, no heuristic needed
  
dedup_group_id: ALL cross-source matches (after first heuristic run)
  └─ memoized for O(1) re-match on subsequent runs
  └─ computed, not platform-level
  
All other source pairs: pure heuristic matching (P0/P2 improvements)
```
