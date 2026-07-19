# Dedup + Time Format — Execution Roadmap

**Approved:** 2026-07-19

```
Milestone 1 ── Infrastructure (P0 + AH fix)
  ├─ Adapter ISO 8601 format (8 adapters + 1 parser)
  ├─ Apple Health timezone fix (format_datetime UTC)
  ├─ Apple Health 7+4 run_id with creationDate
  ├─ DB migration: naive → ISO 8601 by source
  ├─ DELETE + re-import apple_health (927 records)
  └─ DedupMatcher: effective_duration = [moving, elapsed].max

Milestone 2 ── Exact Match (external_id)
  ├─ DB migration: ADD external_id column
  ├─ Apple Health: write meta["HKExternalUUID"]
  ├─ Strava: write detail["external_id"]
  ├─ DedupMatcher: external_id exact match channel
  └─ Comparison analysis script → merge strategy

Milestone 3 ── GPS Trajectory Matching (P2)
  ├─ Douglas-Peucker simplification
  ├─ DTW similarity
  ├─ Hausdorff distance
  ├─ Enhanced overlap + containment_relation
  └─ Composite scoring model + new flags

Milestone 4 ── Production (P3 + export)
  ├─ dedup_groups + dedup_group_members tables
  ├─ workouts dedup CLI (--incremental / --status / --export-composites)
  ├─ DedupService rewrite: union-find + incremental + logging
  ├─ Export JSON/SVG/Stats: field-level composite integration
  └─ scripts/dedup-quantify.rb analysis script
```

## Key Decisions

| Decision | Value |
|---|---|
| Time format | ISO 8601 with zone: start_date UTC Z, start_date_local +08:00 |
| AH run_id | 7+4: MD5[source+start+end][0,7] + MD5[source+creation+start+end][0,4] |
| dedup groups | Separate dedup_groups + dedup_group_members tables (not activities.dedup_group_id) |
| Field election | Computed at export time, not persisted (50ms for ~500 groups) |
| external_id scope | AH↔Strava only (HKExternalUUID bridge, 27 pairs) |
| Garmin Intl/CN time | Defensive .utc only, no functional change needed |
