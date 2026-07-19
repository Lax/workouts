# Acceptance Report — 2026-07-19

## Spec Suite: 619 examples, 0 failures (2.02s)

## M1 — Infrastructure

| Check | Status | Evidence |
|-------|--------|----------|
| ISO 8601 dates in GarminBase | ✅ | `start_date: start_t&.utc&.iso8601` at `garmin_base.rb:439` |
| AH `generate_run_id` uses creationDate | ✅ | 7+4 split: MD5(source+\|s\|e)[0,7] + MD5(source+\|c\|s+\|e)[0,4] at `apple_health.rb:525-531` |
| AH `format_datetime` returns ISO 8601 | ✅ | `.utc.iso8601` with `utc:` kwarg at `apple_health.rb:471-476` |
| `effective_duration` uses `[moving, elapsed].max` | ✅ | At `matcher.rb:14-16` |
| Migration 006 exists | ✅ | Source-aware conversion (AH +0800→UTC, others UTC→ISO8601) at `db/migrations/006_iso8601_time_format.rb` |
| DB has 0 AH run_id collisions | ✅ | 922 AH records, 0 collision groups |

## M2 — external_id Exact Match

| Check | Status | Evidence |
|-------|--------|----------|
| Migration 007 adds `external_id` column | ✅ | `add_column :activities, :external_id, String` + index at `007_add_external_id.rb` |
| AH writes `HKExternalUUID` in `build_attrs` | ✅ | `external_id: meta["HKExternalUUID"]` at `apple_health.rb:465` |
| Strava extracts `detail["external_id"]` | ✅ | `sync_activity` at `strava.rb:65` passes `external_id:` to `build_attrs` |
| Strava writes external_id in `build_attrs` | ✅ | `external_id: external_id` at `strava.rb:183` |
| `Matcher.external_id_match` method exists | ✅ | Normalizes `strava://activities/` prefix; returns `confidence: 1.0, flag: "derived"` at `matcher.rb:18-30` |
| DB external_id records | ✅ | 29 AH records with non-null external_id |
| Strava data present | ⚠️ | 0 Strava records in DB → external_id matching cannot be verified end-to-end |

## M3 — GPS Trajectory

| Check | Status | Evidence |
|-------|--------|----------|
| `douglas_peucker` exists | ✅ | Iterative DP with `perpendicular_distance` at `trajectory.rb:36-66` |
| `dtw_similarity` exists | ✅ | O(nm) DTW with haversine cost, normalized by `MAX_EXPECTED_COST` at `trajectory.rb:68-89` |
| `hausdorff_distance` exists | ✅ | Undirected Hausdorff: `max_min_a, max_min_b].max` at `trajectory.rb:91-101` |
| `normalized_hausdorff_score` exists | ✅ | `1.0 - dist / 2000.0` at `trajectory.rb:103-107` |
| `overlap_score` exists | ✅ | Symmetric containment ratio at `trajectory.rb:109-122` |
| `containment_relation` exists | ✅ | Returns `:equivalent/:contained_a/:contained_b/:partial/:cross/:disjoint` at `trajectory.rb:124-147` |
| Constant `DP_EPSILON` | ✅ | `0.0001` (~10m lat/lng) |
| Constant `CONTAINED_THRESHOLD` | ✅ | `0.7` (70% overlap) |
| Constant `PARTIAL_THRESHOLD` | ✅ | `0.3` (30% boundary) |
| Constant `MAX_EXPECTED_COST` | ✅ | `1000.0` |
| Service `classify_flag` returns 6 types | ✅ | `derived`, `duplicate`, `contained`, `partial`, `cross`, `similar` at `service.rb:110-130` |

## M4 — Production

| Check | Status | Evidence |
|-------|--------|----------|
| Migration 008: `dedup_groups` table | ✅ | `group_id TEXT UNIQUE`, timestamps at `008_dedup_groups.rb:3-8` |
| Migration 008: `dedup_group_members` table | ✅ | FK to dedup_groups, run_id, source, flag, confidence, UNIQUE(group_id, run_id), index(run_id) at `008_dedup_groups.rb:10-19` |
| `GroupConsolidator` with union-find | ✅ | `find` (path compression), `union`, `consolidate` → SHA256 group_id at `group_consolidator.rb` |
| `FieldElector` with all election rules | ✅ | 15 rules: median/min/max/mean/non_null/best_polyline/best_name/earliest/computed at `field_elector.rb:8-25` |
| Source name priority | ✅ | `garmin:1, strava:2, ... apple_health:7` at `field_elector.rb:27-29` |
| `LogWriter` exists | ✅ | JSON log output to `data/dedup/{timestamp}.json` at `log_writer.rb` |
| CLI dedup command | ✅ | `--incremental`, `--log`, `--verbose` options at `cli.rb:123-139` |
| `composite_activity` in JSON export | ✅ | Field-level election per FIELD_ELECTION_RULES at `json.rb:72-104` |
| CSV includes `dedup_group_id` | ✅ | HEADERS includes `dedup_group_id` at `csv.rb:12` |
| SVG dedup integration | ❌ | SVG exporter has no dedup_group or composite support (0 matches for "dedup" or "composite") |
| Stats dedup integration | ❌ | Stats exporter has no dedup_group or composite support (0 matches) |
| `scripts/dedup-quantify.rb` exists | ✅ | File present |

## Acceptance Criteria

| # | Criterion | Result | Details |
|---|-----------|--------|---------|
| 1 | All 19 previously lost AH records imported and matched | ✅ | 922 AH records, 0 run_id collisions. 7+4 split works. |
| 2 | 27 AH↔Strava pairs detected with confidence=1.0 | ⚠️ | 29 AH records have external_id set. Code path verified (`external_id_match` returns 1.0). No Strava data in this DB → cannot confirm pair count. |
| 3 | 5-source group on 2026-06-18 consolidated | ⚠️ | Only AH (922) + Keep (791) data present. No multi-platform data for the specific date to verify 5-source grouping. Union-find logic at `group_consolidator.rb` is correct. |
| 4 | Field-level composite contains temperature + power + polyline | ⚠️ | Polyline present in composites. Temperature field exists in code but nil in sampled data (data-dependent — only AH with weather data has it). Power absent (requires non-null from Strava/Garmin — not in DB). |
| 5 | Second DedupService run processes only new records | ✅ | `--incremental` flag filters `run_id NOT IN (SELECT run_id FROM dedup_group_members)` at `service.rb:89-93` |
| 6 | Export JSON includes composite records | ✅ | 1029 composites with `dedup_group` + `member_sources` fields in `/tmp/accept.json` |

## Issues Found

1. **SVG exporter lacks dedup support** — `lib/workouts/export/svg.rb` has no dedup_group/composite integration though design doc lists it in M4. JSON and CSV are integrated; SVG and Stats are not.
2. **No Strava/Garmin/iGPSPORT/XOSS/XingZhe data in test DB** — Only AH (922), Keep (791), and 5 imported local files. External_id matching (criterion 2) and multi-source grouping (criterion 3) cannot be end-to-end verified against this snapshot.

## DB State Summary

```
Tables: activities, dedup_group_members, dedup_groups, schema_info
Schema version: 8
Activities: 1718
Dedup groups: 529
Dedup members: 1293
External_ids: 29 (in AH records)
Sources: apple_health=922, fit=1, gpx=3, keep=791, tcx=1
```
