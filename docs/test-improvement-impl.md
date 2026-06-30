# Test Improvement — Implementation

## Order of Execution

```
Phase 1 — Low-hanging fruit (CI + gemspec + spec cleanup)
Phase 2 — High-risk tests (Dashboard JS + Stats)
Phase 3 — Medium-risk tests (Renderer smoke + Garmin type anomaly)
Phase 4 — Acceptance verification
```

## Phase 1: CI + gemspec + Spec Cleanup

### 1.1 Ruby version: ci.yml

File: `.github/workflows/ci.yml`

Keep matrix structure for future extensibility, only target 3.4:

```yaml
strategy:
  matrix:
    ruby-version: ["3.4"]
```

Step name uses `${{ matrix.ruby-version }}` to show version in CI output, matching original naming convention.

### 1.2 gemspec

File: `workouts-cli.gemspec`

Change:
```ruby
s.required_ruby_version = ">= 3.1"
```
To:
```ruby
s.required_ruby_version = ">= 3.4"
```

### 1.3 Dir.mktmpdir for 4 sync specs

Files to modify:
- `spec/sync/keep_integration_spec.rb` — replace `data/raw/keep/` usage with `Dir.mktmpdir`
- `spec/sync/igpsport_spec.rb` — same for `data/raw/igpsport/`
- `spec/sync/xingzhe_spec.rb` — same for `data/raw/xingzhe/`
- `spec/sync/strava_spec.rb` — same for `data/raw/strava/`

Pattern for each:
```ruby
let(:tmpdir) { Dir.mktmpdir }
after { FileUtils.rm_rf(tmpdir) }
# Replace raw_dir/storage references with tmpdir
```

## Phase 2: Dashboard + Stats Tests

### 2.1 `spec/export/dashboard_spec.rb`

```ruby
RSpec.describe Workouts::Export::Dashboard do
  # ... setup with in-memory DB, varied data

  describe "HTML structure" do
    it "contains #map container"
    it "contains #app-drawer"
    it "contains .year-pills"
    it "loads Leaflet from CDN"
    it "loads ECharts from CDN"
    it "includes <script> with JS code"
  end

  describe "JS logic (node validation)" do
    it "passes syntax check via node -e"
    it "decodePolyline handles nil/empty"
    it "decodePolyline decodes example"
    it "speedColor maps correctly across speed ranges"
    it "typeColor returns correct hex for known types"
    it "typeColor falls back to #888 for unknown types"
    it "fmtPace handles nil/zero/normal"
  end

  describe "data boundary conditions" do
    it "handles null polyline"
    it "handles single-point polyline"
    it "handles empty activity list"
    it "handles single activity"
    it "handles activities missing optional fields"
  end
end
```

Implementation approach:
1. Build memory DB with seed activities
2. Call `Dashboard#build_html` directly (not `#call` — avoid file I/O)
3. Use regex to extract JS from heredoc
4. Write JS to temp file
5. Spawn `node -e` to check syntax
6. Spawn `node -e` with inline assertions for pure functions

### 2.2 `spec/export/stats_spec.rb`

```ruby
RSpec.describe Workouts::Export::Stats do
  # ... in-memory DB

  describe "output structure" do
    it "has summary, monthly, yearly, streaks, activity_types keys"
    it "summary has total_activities, total_distance_km, total_moving_time_h"
    it "summary has avg_cadence, avg_power (nullable)"
    it "summary sport_breakdown is sorted by count desc"
    it "monthly entries have year, month, count, distance_km, moving_time_h"
    it "yearly entries have year, count, distance_km, moving_time_h, longest_km"
    it "streaks has current and all_time"
    it "activity_types is sorted array of distinct categories"
  end

  describe "edge cases" do
    it "empty DB returns empty_stats structure"
    it "single activity returns correct counts"
    it "filters by sport_category"
    it "handles nil sensor fields (hr, cadence, power)"
    it "multiple categories produce correct breakdown"
  end

  describe "format_pace" do
    it "formats 270 seconds as 4'30\""
    it "formats 65 seconds as 1'05\""
    it "formats 3600 seconds as 60'00\""
  end
end
```

### 2.3 SVG Smoke Test

File: `spec/export/svg_spec.rb`

Add to existing file:
```ruby
describe Workouts::Export::SVG::Renderer do
  it "orchestrates github style without error"
  it "passes config options through to drawer"
end
```

## Phase 3: Garmin Type Anomaly Tests

### 3.1 garmin_base_spec.rb additions

```ruby
describe "API response type handling" do
  it "handles polyline as Array instead of String"
  it "handles activityType as Hash instead of String"
  it "handles missing optional fields"
end
```

This ensures the regressions from commits `6a910b3` and `e4580b8` are covered.

## Phase 4: CI Build Validation

File: `.github/workflows/sync.yml`

In build job, after dashboard export step, add:
```yaml
- name: Validate dashboard HTML
  run: |
    # Check required DOM IDs exist
    for id in map app-drawer chart chart-small detail-overlay charts-overlay; do
      if ! grep -q "id=\"$id\"" build/index.html; then
        echo "::error::Missing DOM id: $id"
        exit 1
      fi
    done
    echo "OK: All DOM IDs present"

- name: Validate dashboard JS syntax
  run: |
    # Extract JS from HTML and check syntax
    awk '/<script>/,/<\/script>/' build/index.html | head -n -1 | tail -n +2 > /tmp/dashboard.js
    node -e "new Function(require('fs').readFileSync('/tmp/dashboard.js','utf8'))"
    echo "OK: Dashboard JS syntax valid"
```

## File Change Manifest

```
docs/test-improvement-goal.md       (new)     # This spec
docs/test-improvement-research.md   (new)     # Research + adversarial review
docs/test-improvement-impl.md       (new)     # This checklist
spec/export/dashboard_spec.rb       (new)     # ~100 lines
spec/export/stats_spec.rb           (new)     # ~60 lines
spec/export/svg_spec.rb             (modify)  # +~20 lines
spec/sync/garmin_base_spec.rb       (modify)  # +~15 lines
spec/sync/keep_integration_spec.rb  (modify)  # Dir.mktmpdir
spec/sync/igpsport_spec.rb          (modify)  # Dir.mktmpdir
spec/sync/xingzhe_spec.rb           (modify)  # Dir.mktmpdir
spec/sync/strava_spec.rb            (modify)  # Dir.mktmpdir
.github/workflows/ci.yml            (modify)  # matrix with ruby-version: ["3.4"]
.github/workflows/sync.yml          (modify)  # HTML/JS validation
workouts-cli.gemspec                (modify)  # >= 3.4
```

## Runbook

```bash
# After implementation, verify:
bundle exec rspec                      # All green
ruby -c lib/workouts.rb                # Syntax check
find lib -name '*.rb' -exec ruby -c {} \;  # All lib files

# Verify no spec writes to production data/
grep -rn "data/raw" spec/ || echo "OK: no production data writes"

# Verify CI config
grep "ruby-version" .github/workflows/ci.yml

# Verify gemspec
grep "required_ruby_version" workouts-cli.gemspec
```
