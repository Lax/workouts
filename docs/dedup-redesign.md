# Dedup Redesign — Service, Matcher, Trajectory, Election

## Motivation

Current DedupService limitations discovered during Apple Health cross-source analysis:

| Limitation | Impact |
|---|---|
| `group_by date` → intradate only | Misses midnight-crossing activities |
| `parse_time` naive → relies on system timezone | Comparison breaks between AH (+0800) and UTC sources |
| `moving_time` as duration metric | AH (no pause) vs Garmin (pause-filtered) → systematic 14% bias |
| `sport_category` hard -10% for mismatch | walk≠hike penalized same as run≠ride |
| No exact match channel (external_id) | All matching is heuristic, no confidence=1.0 |
| No GPS trajectory similarity | Only point-radius containment (~50m, 30% threshold) |
| No N>2 group management | Each pair matched independently, no group aggregate |
| No logging | Cannot trace why a match was made or missed |

Research data from archive DB (2103 activities across 8 sources) shows:

- **813 cross-source duplicate pairs** after timezone correction
- **573/908 (63.1%)** Apple Health records have at least one duplicate
- **Up to 5 copies** per physical activity (AH + Keep + Strava + iGPSPORT + Garmin CN)
- **442 days** with at least one cross-source duplicate
- Per-source distribution: Keep=496, Strava=59, iGPSPORT=55, Garmin=46, XOSS=40, XingZhe=8, Garmin CN=1

## Overview

```
DedupService.run()
├── P0: Infrastructure
│   ├── Time window: ±1 day sliding
│   ├── parse_time: unified ISO 8601
│   ├── duration: [moving, elapsed].max
│   └── sport_category: hierarchical groups
│
├── P1: Exact Match Channel
│   ├── external_id equality
│   └── field-level merge strategy
│
├── P2: GPS Trajectory Matching
│   ├── Douglas-Peucker simplification
│   ├── DTW similarity score
│   ├── Hausdorff distance
│   ├── Point-radius overlap (existing)
│   └── Composite scoring model
│
├── P3: Production
│   ├── CLI entry point
│   ├── Detailed logging
│   ├── Runner auto-trigger
│   └── Memoized dedup (dedup_group_id)
│
├── Classification (flag selection)
├── Field-level election
└── N>2 group management
```

---

## P0 — Infrastructure Changes

### Time Window

**Current:** `group_by { \|a\| parse_time(a[:start_date]).to_date }` → compare only within same calendar date.

**Problem:** A ride starting at 23:50 and ending at 00:30 is split across two days. The start record in one group never compares with the activity record in the other group.

**Fix:** Sort all activities by `start_date`, use a **sliding window** of ±1 day:

```ruby
def run
  activities = @db[:activities]
    .where(Sequel.lit("distance > 100"))
    .order(:start_date)
    .all
  return 0 if activities.size < 2

  activities.each_with_index do |a, i|
    a_start = parse_time(a[:start_date])
    next unless a_start
    window_end = a_start + 86400  # +1 day

    (i + 1...activities.size).each do |j|
      b = activities[j]
      b_start = parse_time(b[:start_date])
      break unless b_start
      break if b_start > (a_end || a_start) + 86400  # +1 day from a's end

      # Compare a vs b
    end
  end
end
```

**Why ±1 day?** The current window was effectively 0 days (same date group). Expanding to ±1 day covers:
- Midnight-crossing activities (start 23:50, end 00:30)
- Activities separated by a few hours (morning run → evening run, same day)
- Activities with one source recording start time a few hours off from another (rare but documented in Garmin dual-device scenarios)

The O(N²) comparison still holds (2103 activities → ~2.2M pairs worst case), but early break on `b_start > window_end` keeps it manageable.

### parse_time: Unified ISO 8601

**Current:**
```ruby
def parse_time(val)
  return nil unless val
  Time.parse(val.to_s)
rescue
  nil
end
```

✅ Already compatible with both `"%Y-%m-%d %H:%M:%S"` and ISO 8601 formats. `Time.parse` handles both.

After time format migration (see `docs/time-format-iso8601.md`), only ISO 8601 with zone suffix exists. No compatibility layer needed post-migration.

**Defensive improvement:** Force UTC for consistent epoch arithmetic:

```ruby
def parse_time(val)
  return nil unless val
  t = Time.parse(val.to_s)
  t.utc? ? t : t.utc  # ensure UTC for comparison
rescue
  nil
end
```

### Duration: Use `[moving_time, elapsed_time].max`

**Current:**
```ruby
# in Matcher
duration_a = a[:moving_time] || a[:elapsed_time] || 0
duration_b = b[:moving_time] || b[:elapsed_time] || 0
```

**Problem:** Apple Health has no pause filtering → `moving_time` ≈ `elapsed_time`. Garmin/Strava filter pauses → `moving_time` < `elapsed_time`. Comparing AH.moving_time (3840s) vs Garmin.moving_time (3645s) gives a 5% duration diff even though the activities are identical.

**Fix:**
```ruby
def effective_duration(activity)
  # Use max of moving/elapsed to normalize pause-filtering discrepancies
  [activity[:moving_time].to_f, activity[:elapsed_time].to_f].max
end
```

**Why max?** `moving_time` without pause filtering ≈ `elapsed_time`, while `moving_time` with pause filtering < `elapsed_time`. Using `max` ensures both types converge on total activity time. The duration comparison then becomes:

```ruby
duration_a = effective_duration(a)
duration_b = effective_duration(b)
if duration_a > 0 && duration_b > 0
  duration_diff = (duration_a - duration_b).abs / [duration_a, duration_b].max
  duration_score = duration_diff <= 0.15 ? (1 - duration_diff) * 0.15 : 0
end
```

### sport_category: Hierarchical Groups

**Current:** Hard category comparison with fixed weights:
- Same type: +15%
- Different type: -10%

**Problem:** `walk` ≠ `hike` gets the same -10% penalty as `run` ≠ `ride`. In practice, `walk` and `hike` are the same activity (just different app labels) and should not be penalized.

**Fix:** Hierarchical group mapping:

```ruby
CATEGORY_GROUPS = {
  run:    [:run, :trail_run, :jogging],
  ride:   [:ride, :cycling, :mountain_bike, :gravel_ride],
  hike:   [:hike, :walk, :hiking, :walking],
  swim:   [:swim, :swimming, :pool_swim, :open_water],
  ski:    [:ski, :cross_country_ski, :downhill_ski],
  workout: [:workout, :strength, :elliptical, :stair_climber, :core_training],
  other:  [:other, :cross_training, :mixed]
}
```

**Category match scoring:**

```ruby
def category_score(cat_a, cat_b)
  return 0.15 if same_group?(cat_a, cat_b)
  return -0.05 if different_but_compatible?(cat_a, cat_b)  # e.g., hike vs run
  return -0.10  # incompatible: run vs ride
end
```

**Compatibility matrix** (separate from group membership):

| A \ B | run | ride | hike | walk | swim | ski | workout | other |
|---|---|---|---|---|---|---|---|---|
| **run** | +0.15 | -0.10 | -0.05 | -0.05 | -0.10 | -0.10 | -0.10 | -0.10 |
| **ride** | -0.10 | +0.15 | -0.10 | -0.10 | -0.10 | -0.10 | -0.10 | -0.10 |
| **hike** | -0.05 | -0.10 | +0.15 | +0.15 | -0.10 | -0.05 | -0.10 | -0.05 |
| **walk** | -0.05 | -0.10 | +0.15 | +0.15 | -0.10 | -0.10 | -0.10 | -0.05 |
| **swim** | -0.10 | -0.10 | -0.10 | -0.10 | +0.15 | -0.10 | -0.10 | -0.10 |

---

## P1 — Exact Match Channel (external_id)

See `docs/external-id.md` for full specification.

**Integration into DedupService:**

```ruby
# DedupService#run, before heuristic loop:

# Phase 0: Exact external_id matching
exact_matches = find_external_id_matches(activities)
exact_matches.each do |a, b|
  score = 1.0
  flag = "derived"
  append_info(a[:run_id], b[:source], b[:run_id], score, flag)
  append_info(b[:run_id], a[:source], a[:run_id], score, flag)

  # Pre-assign dedup_group_id for exact matches
  group_id = compute_group_id([a, b])
  mark_group(group_id, [a[:run_id], b[:run_id]])
end

# Phase 1: Heuristic matching (existing + improved loop)
# Only for records without dedup_group_id
```

**Expected yield:** ~27 exact pairs (Strava↔AH).

---

## P2 — GPS Trajectory Matching

### Current State

`Trajectory#duplicate?` reads L2 JSON files, samples every 10th point, checks if ≥30% of sampled points are within 50m of the other trajectory. This is a **containment** test — good for catching obvious duplicates with GPS.

### Limitations

- Only binary yes/no (≥30% threshold)
- No similarity scoring (how close are the trajectories on a 0-1 scale?)
- No partial overlap detection (30% threshold too binary)
- Hardcoded 10-point stride, 50m radius
- No cross-overlap detection (A overlaps B in section 1, B overlaps A in section 3)
- L2 files may be missing → silently skips

### Algorithm Additions

#### Douglas-Peucker Simplification

Extract "characteristic points" from raw GPS trajectory — reduces 3000 points to 20-50 key points while preserving overall shape. Used as input to DTW and Hausdorff for efficiency.

```ruby
module Trajectory
  def douglas_peucker(points, epsilon = 0.0001)  # ~10m in lat/lng
    return points if points.size <= 2

    dmax = 0
    index = 0
    end_idx = points.size - 1
    first = points[0]
    last = points[end_idx]

    (1...end_idx).each do |i|
      d = perpendicular_distance(points[i], first, last)
      if d > dmax
        dmax = d
        index = i
      end
    end

    if dmax > epsilon
      rec1 = douglas_peucker(points[0..index], epsilon)
      rec2 = douglas_peucker(points[index..-1], epsilon)
      rec1[0..-2] + rec2
    else
      [first, last]
    end
  end
end
```

#### DTW (Dynamic Time Warping)

Similarity score between two simplified trajectories. Returns a normalized score [0, 1] where 1 = identical shape regardless of point count sampling.

```ruby
module Trajectory
  def dtw_similarity(traj_a, traj_b)
    # Cost function: haversine distance between two lat/lng points
    n = traj_a.size
    m = traj_b.size
    dtw = Array.new(n + 1) { Array.new(m + 1, Float::INFINITY) }
    dtw[0][0] = 0

    (1..n).each do |i|
      (1..m).each do |j|
        cost = haversine(traj_a[i - 1], traj_b[j - 1])
        dtw[i][j] = cost + [dtw[i - 1][j], dtw[i][j - 1], dtw[i - 1][j - 1]].min
      end
    end

    # Normalize by path length
    normalized_cost = dtw[n][m] / [n, m].max
    # Convert cost to similarity (higher = more similar)
    [1.0 - normalized_cost / MAX_EXPECTED_COST, 0.0].max
  end
end
```

#### Hausdorff Distance

Maximum deviation between two point sets. Useful for detecting partial overlaps.

```ruby
module Trajectory
  def hausdorff_distance(traj_a, traj_b)
    # Directed Hausdorff: max of min distances from A to B
    max_min_a = traj_a.map { |p| min_distance_to_set(p, traj_b) }.max
    max_min_b = traj_b.map { |p| min_distance_to_set(p, traj_a) }.max
    [max_min_a, max_min_b].max  # Undirected Hausdorff
  end

  def normalized_hausdorff_score(traj_a, traj_b)
    dist = hausdorff_distance(traj_a, traj_b)
    # 0m → 1.0, 500m → 0.5, 2000m → 0.0
    [1.0 - dist / 2000.0, 0.0].max
  end
end
```

#### Overlap Ratio (enhanced from existing)

Replace binary ≥30% threshold with continuous score:

```ruby
module Trajectory
  def overlap_score(traj_a, traj_b, radius = 50)
    sampled_a = traj_a.each_slice(10).map(&:first)
    sampled_b = traj_b.each_slice(10).map(&:first)
    return 0.0 if sampled_a.empty? || sampled_b.empty?

    a_in_b = sampled_a.count { |p| point_near_any?(p, sampled_b, radius) }
    b_in_a = sampled_b.count { |p| point_near_any?(p, sampled_a, radius) }

    ratio_a = a_in_b.to_f / sampled_a.size
    ratio_b = b_in_a.to_f / sampled_b.size

    # symmetric score: (containment_a + containment_b) / 2
    (ratio_a + ratio_b) / 2.0
  end
end
```

#### Partial Containment Detection

```ruby
module Trajectory
  def containment_relation(traj_a, traj_b, radius = 50, threshold = 0.7)
    sampled_a = traj_a.each_slice(10).map(&:first)
    sampled_b = traj_b.each_slice(10).map(&:first)

    a_in_b = sampled_a.count { |p| point_near_any?(p, sampled_b, radius) } / sampled_a.size.to_f
    b_in_a = sampled_b.count { |p| point_near_any?(p, sampled_a, radius) } / sampled_b.size.to_f

    if a_in_b >= threshold && b_in_a >= threshold
      :equivalent     # Both trajectories mostly overlap
    elsif a_in_b >= threshold
      :contained_a    # A ⊂ B
    elsif b_in_a >= threshold
      :contained_b    # B ⊂ A
    elsif a_in_b > 0.3 || b_in_a > 0.3
      :partial        # 30-70% overlap, neither fully contained
    elsif a_in_b > 0 || b_in_a > 0
      :cross          # Points intersect but no significant overlap
    else
      :disjoint       # No meaningful overlap
    end
  end
end
```

### Composite Scoring Model

```ruby
module Matcher
  TRAJECTORY_WEIGHTS = {
    dtw_similarity:      0.30,
    overlap_score:       0.25,
    hausdorff_score:     0.25,
    distance_match:      0.20,
  }.freeze

  def trajectory_score(traj_a, traj_b)
    scores = {
      dtw_similarity:  @trajectory.dtw_similarity(traj_a, traj_b),
      overlap_score:   @trajectory.overlap_score(traj_a, traj_b),
      hausdorff_score: @trajectory.normalized_hausdorff_score(traj_a, traj_b),
      distance_match:  distance_compatibility(traj_a, traj_b)
    }

    scores.sum { |metric, score| score * TRAJECTORY_WEIGHTS[metric] }
  end
end
```

### Flag Classification (updated)

```ruby
def classify(a, b, confidence, traj_a, traj_b)
  # Phase 1: external_id exact match
  return "derived" if confidence >= 1.0

  # Phase 2: High confidence → derived (same activity, different source)
  return "derived" if confidence >= 0.85

  # Phase 3: GPS trajectory analysis
  containment = @trajectory.containment_relation(traj_a, traj_b)

  if containment == :equivalent && confidence >= 0.15
    return "duplicate"
  elsif containment == :contained_a || containment == :contained_b
    return "contained"
  elsif containment == :partial && confidence >= 0.15
    return "partial"
  elsif containment == :cross && confidence >= 0.15
    return "cross"
  elsif confidence >= 0.15
    return "similar"
  end

  nil
end
```

### Final flag set

| Flag | Meaning | Condition |
|---|---|---|
| `derived` | Same activity, different source | external_id=1.0 OR confidence≥0.85 |
| `duplicate` | High overlap, trajectory equivalent | ≥0.15 + containment==equivalent |
| `contained` | One trajectory ⊂ the other | ≥0.15 + partial containment |
| `partial` | 30-70% overlap | ≥0.15 + partial containment |
| `cross` | Points intersect, minimal overlap | ≥0.15 + cross containment |
| `similar` | Same time/dist, different route | ≥0.15 + disjoint |

---

## P3 — Productionization

### CLI Entry Point

```ruby
# lib/workouts/cli/sync.rb or lib/workouts/cli/dedup.rb

desc "dedup", "Run cross-source dedup matching"
method_option :source, type: :string, desc: "Limit to specific source"
method_option :verbose, type: :boolean, default: false, desc: "Detailed per-match output"
method_option :log, type: :string, default: nil, desc: "Write log to file"
method_option :limit, type: :numeric, default: nil, desc: "Max pairs to analyze"
def dedup
  require_relative "../dedup/service"
  db = Workouts::DB.connect
  service = Dedup::Service.new(db, verbose: options[:verbose], log_path: options[:log])
  matched = service.run(source: options[:source], limit: options[:limit])
  puts "DedupService: #{matched} pairs matched"
end
```

### Logging Format

```
DedupService [2026-07-19T10:00:00Z] — scanning 2103 activities
══════════════════════════════════════════════════════
MATCH #142: strava_18970636139 × apple_health_0ac7bd4149d
  confidence: 1.0000
  flag: derived
  channel: external_id
  evidence:
    external_id: "strava://activities/18970636139" = "strava://activities/18970636139"
  ──────────────────────────────────────────
MATCH #143: keep_9223370255070041807 × strava_18970636139
  confidence: 0.9247
  flag: derived
  channel: heuristic + trajectory
  evidence:
    time_diff:     3s  (score: +0.3500)
    dist_diff:     0.8% (score: +0.3430)
    duration_diff: 1.1% (score: +0.1483)
    sport_match:   ride=ride (+0.1500)
    trajectory:
      dtw:         0.87  (weight: 0.30 × 0.87 = 0.261)
      overlap:     0.92  (weight: 0.25 × 0.92 = 0.230)
      hausdorff:   0.89  (weight: 0.25 × 0.89 = 0.223)
      distance:    0.95  (weight: 0.20 × 0.95 = 0.190)
      composite:   0.904
    total:         0.9247
  ──────────────────────────────────────────
MATCH #144: igpsport_51134423 × apple_health_0ac7bd4149d
  confidence: 0.3621
  flag: contained
  channel: heuristic + trajectory
  evidence:
    time_diff:     32s  (score: +0.2900)
    dist_diff:     0.0% (score: +0.3500)
    duration_diff: 67.2% (score: -0.1500)  # AH has no GPS for this → false short
    sport_match:   ride=ride (+0.1500)
    trajectory:
      containment: A ⊂ B (0.95 / 0.12)
      dtw:         0.31  (weight: ...)
      ...
    total:         0.3621
  ──────────────────────────────────────────
Summary:
  total pairs scanned:    142,313
  total pairs compared:   12,847  (had GPS data)
  matched:                813
    derived:   196  (24.1%)
    duplicate: 408  (50.2%)
    contained:  22  (2.7%)
    partial:    21  (2.6%)
    cross:       8  (1.0%)
    similar:   187  (23.0%)
  unmatched (heuristic): 12,034
  elapsed: 14.3s (12,847 pairs → 898 pairs/s)
```

### Log File Output

When `--log FILE` is specified or by default:

```
data/dedup/2026-07-19T100000Z.json
```

JSON format for machine consumption:

```json
{
  "started_at": "2026-07-19T10:00:00Z",
  "elapsed_seconds": 14.3,
  "stats": {
    "scanned": 2103,
    "compared": 12847,
    "matched": 813,
    "by_flag": { "derived": 196, "duplicate": 408, ... }
  },
  "matches": [
    {
      "id": 143,
      "a": { "run_id": "keep_...", "source": "keep" },
      "b": { "run_id": "strava_...", "source": "strava" },
      "confidence": 0.9247,
      "flag": "derived",
      "evidence": { "time_diff": 3, "dist_diff_pct": 0.8, ... },
      "trajectory": { "dtw": 0.87, "overlap": 0.92, ... }
    }
  ]
}
```

### Runner Auto-Trigger

```ruby
# lib/workouts/sync/runner.rb, after all sources complete:

def run
  # ... existing sync logic ...

  # After sync completes:
  if @dedup_auto
    require_relative "../dedup/service"
    service = Dedup::Service.new(@db, verbose: false)
    matched = service.run
    log "DedupService: #{matched} matches found"
  end
end
```

Configurable via `config.yml`:

```yaml
sync:
  dedup_auto: true
```

### Memoized Dedup (dedup_group_id)

```sql
ALTER TABLE activities ADD COLUMN dedup_group_id TEXT;
```

After first match confirms two (or more) activities are the same:

```ruby
def assign_dedup_group(group_records, group_id = nil)
  group_id ||= Digest::SHA256.hexdigest(
    group_records.map { |r| "#{r[:source]}:#{r[:run_id]}" }.sort.join("|")
  )[0, 16]
  group_records.each do |r|
    @db[:activities].where(run_id: r[:run_id]).update(dedup_group_id: group_id)
  end
end
```

Subsequent DedupService runs: `WHERE dedup_group_id IS NULL` only.

---

## Field-Level Election

### Concept

Within a `dedup_group`, no single source has all the best data. Instead of electing one canonical record, elect per-field:

```
dedup_group "a1b2c3d4e5f6":
  members:
    - garmin_12345
    - strava_67890
    - apple_health_a1b2c3
    - keep_98765

  composite (field-level election):
    distance:        12.34 km   (median of 4 sources)
    moving_time:     3645 s     (min: garmin has best pause filtering)
    elapsed_time:    3975 s     (max: garmin's full elapsed)
    avg_heartrate:   141.5 bpm  (mean of garmin+strava+ah)
    max_heartrate:   167 bpm    (max of garmin+strava+ah)
    avg_power:       183 w      (non-null: garmin+strava only)
    avg_cadence:     79 rpm     (non-null: garmin+strava only)
    summary_polyline: (AH's)    (highest point count: AH > garmin > strava)
    elevation_gain:  315 m      (median of all sources)
    calories:        840 kcal   (median of all sources)
    temperature:     28°C       (non-null: only AH has it)
    average_speed:   3.33 m/s   (computed: distance / moving_time)
    name:            "Afternoon Ride"  (best source: strava > garmin > keep > ah)
```

### Election Rules

```ruby
FIELD_ELECTION_RULES = {
  distance:            :median,
  moving_time:         :min,
  elapsed_time:        :max,
  average_heartrate:   :mean,
  max_heartrate:       :max,
  average_power:       :non_null,
  max_power:           :non_null,
  average_cadence:     :non_null,
  max_cadence:         :non_null,
  summary_polyline:    :best_polyline,    # highest point count
  elevation_gain:      :median,
  calories:            :median,
  average_temperature: :non_null,
  average_speed:       :computed,          # distance / moving_time
  name:                :best_name,         # by source priority
  start_date:          :earliest,          # earliest start (guard against timezone drift)
}
```

### Source Priority for Name Election

```ruby
SOURCE_NAME_PRIORITY = {
  garmin:     1,
  strava:     2,
  igpsport:   3,
  xoss:       4,
  keep:       5,
  xingzhe:    6,
  apple_health: 7
}
```

Lower number = higher priority.

### Election Implementation

```ruby
class Dedup::FieldElector
  def elect(field, values)
    rule = FIELD_ELECTION_RULES[field]
    non_nil = values.compact
    return nil if non_nil.empty?

    case rule
    when :median
      sorted = non_nil.sort
      sorted[sorted.size / 2]
    when :mean
      non_nil.sum / non_nil.size
    when :min
      non_nil.min
    when :max
      non_nil.max
    when :non_null
      non_nil.first  # only one source provides it, take it
    when :best_polyline
      values.max_by { |v| decode_polyline(v)&.size.to_i }
    when :computed
      nil  # computed externally
    when :best_name
      pair = values.zip(sources).min_by { |_, src| SOURCE_NAME_PRIORITY[src] || 99 }
      pair&.first
    when :earliest
      non_nil.min_by { |v| Time.parse(v.to_s) rescue Time.at(0) }
    end
  end
end
```

### Composite Record Persistence

Option A (recommended): **View-only**. Composite record computed at export time, not stored in DB.

```ruby
# Export::JSON
def build_composite_activity(group)
  members = group[:members]
  composite = {}
  FIELD_ELECTION_RULES.each_key do |field|
    values = members.map { |m| m[field] }
    composite[field] = FieldElector.new.elect(field, values)
  end
  composite[:dedup_group] = group[:id]
  composite[:member_sources] = members.map { |m| { source: m[:source], run_id: m[:run_id] } }
  composite
end
```

Option B (future): **Store composite**. New `composite_activities` table, rebuilt incrementally. Useful for SVG export performance.

---

## N>2 Group Management

### Default: pair-wise matching

DedupService produces pair-wise matches. Each record accumulates its own `duplicate_info` array.

Example for a 5-source group:

```
apple_health_a1b2c3.duplicate_info = [
  { source: "strava", run_id: "strava_123", confidence: 1.0, flag: "derived" },
  { source: "keep",   run_id: "keep_456",   confidence: 0.91, flag: "derived" },
  { source: "igpsport", run_id: "igpsport_789",  confidence: 0.85, flag: "derived" },
  { source: "garmin_cn", run_id: "garmin_cn_999", confidence: 0.36, flag: "contained" },
]
```

### Group consolidation (post-processing)

After all pair-wise matches complete, consolidate groups via **union-find**:

```ruby
class Dedup::GroupConsolidator
  def consolidate(matches)
    # Union-Find over run_ids
    parent = {}
    matches.each do |a, b|
      union(parent, a[:run_id], b[:run_id])
    end

    # Collect groups
    groups = Hash.new { |h, k| h[k] = [] }
    parent.each_key { |run_id| groups[find(parent, run_id)] << run_id }
    groups
  end
end
```

This finds all 5-source groups, 4-source groups, etc. without requiring explicit N-wise comparison.

### Group-level actions

- **dedup_group_id write**: assign same group ID to all members
- **Field-level election**: run across all group members
- **Canonical selection** (for visualizations): pick highest-score source or composite
- **Duplicate_info enrichment** (optional): backfill missing cross-refs

### Edge cases

- **False positive chain**: A matches B (0.85), B matches C (0.85), but A does NOT match C (0.05). Union-find groups all three together. **Mitigation for high stakes**: require all-pairs within group to exceed minimum threshold for `derived` flag. For `similar`/`partial`, chain grouping is acceptable.

---

## Migration Path

### Phase 1: P0 (infrastructure)
1. Update `parse_time` in DedupService (already compatible, add defensive `.utc`)
2. Change `effective_duration` to `[moving, elapsed].max`
3. Replace `group_by date` with sliding ±1 day window
4. Add hierarchical sport_category groups
5. Deploy, run on existing data, verify no regressions

### Phase 2: P1 (external_id)
1. Add `external_id` column via DB migration
2. Update Strava adapter: extract `detail["external_id"]`
3. Update Apple Health adapter: extract `meta["HKExternalUUID"]`
4. Update DedupMatcher: exact match channel
5. Run AH↔Strava comparison analysis script
6. Define merge strategy based on analysis results

### Phase 3: P2 (GPS trajectory)
1. Add Douglas-Peucker to Trajectory
2. Add DTW similarity to Trajectory
3. Add Hausdorff distance to Trajectory
4. Enhance existing overlap detection with continuous score
5. Add containment_relation method (equivalent/contained/partial/cross/disjoint)
6. Integrate composite scoring into Matcher
7. Update flag classification

### Phase 4: P3 (production)
1. Add `workouts dedup` CLI
2. Add detailed logging + JSON output
3. Integrate Runner auto-trigger
4. Add `dedup_group_id` column + memoized dedup
5. Implement field-level election
6. Implement union-find group consolidation

---

## Verification

### Test methodology

| Test | What | How |
|---|---|---|
| P0 regression | Same results on existing data | Run DedupService before/after, compare match counts |
| P1 precision | external_id matches always correct | Verify 27 pairs match exactly with confidence=1.0 |
| P2 sensitivity | Trajectory matching catches edge cases | Known 5-source group on 2026-06-18 must be detected |
| P3 memoized | dedup_group_id skips matched records | Run twice, second run should compare only new data |
| Field election | Composite record is always complete | Each field should have a value from the best source |
| N>2 consolidation | Union-find groups correctly | Manual verification on known day with multiple duplicates |

### Acceptance criteria

1. All 19 previously lost AH records are now imported and matched
2. 27 AH↔Strava pairs detected with confidence=1.0
3. 5-source group on 2026-06-18 consolidated into one dedup_group
4. Field-level composite contains temperature (from AH) + power (from Strava) + polyline (from AH)
5. Second DedupService run processes only new records
