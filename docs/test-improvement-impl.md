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

## Phase 2: Stats Tests

> **Note**: Dashboard JS tests were migrated from Ruby dashboard_spec.rb to vitest in 2026-07 (Ruby Dashboard class deleted). See `packages/web/tests/polyline.test.ts`, `colorMode.test.ts`, `formatters.test.ts`.

### 2.1 `spec/export/stats_spec.rb`

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

## File Change Manifest

```
docs/test-improvement-goal.md       (new)     # This spec
docs/test-improvement-research.md   (new)     # Research + adversarial review
docs/test-improvement-impl.md       (new)     # This checklist
packages/web/tests/state.test.ts    (new)     # Frontend unit tests (vitest)
spec/export/stats_spec.rb           (new)     # ~60 lines
spec/export/svg_spec.rb             (modify)  # +~20 lines
spec/sync/garmin_base_spec.rb       (modify)  # +~15 lines
spec/sync/keep_integration_spec.rb  (modify)  # Dir.mktmpdir
spec/sync/igpsport_spec.rb          (modify)  # Dir.mktmpdir
spec/sync/xingzhe_spec.rb           (modify)  # Dir.mktmpdir
spec/sync/strava_spec.rb            (modify)  # Dir.mktmpdir
.github/workflows/ci.yml            (modify)  # matrix with ruby-version: ["3.4"]
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
