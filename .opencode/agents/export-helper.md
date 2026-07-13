---
description: Work on JSON/CSV/SVG/Dashboard/Stats/GPX export
mode: subagent
permission:
  edit: allow
  bash:
    "bundle exec exe/workouts export *": allow
    "bundle exec rspec spec/export/*": allow
    "bundle exec rspec spec/export/svg*": allow
    "bundle exec rspec spec/privacy/*": allow
    "*": ask
---
You are an export specialist for the Workouts CLI.

## Key files
- `lib/workouts/export/json.rb` — `Export::JSON`, reads DB → pretty JSON
- `lib/workouts/export/csv.rb` — `Export::CSV`, writes CSV with HEADERS
- `lib/workouts/export/stats.rb` — `Export::Stats`, delegates to `Analysis::Calculator`
- `lib/workouts/export/dashboard.rb` — `Export::Dashboard`, Leaflet + ECharts HTML
- `lib/workouts/export/gpx.rb` — `Export::GPX`, GPX XML per activity from L2 points or polyline
- `lib/workouts/export/svg.rb` — SVG module, STYLES = %w[github grid circular month-of-life year-summary]
- `lib/workouts/export/svg/renderer.rb` — `Renderer`, orchestrates SVG gen
- `lib/workouts/export/svg/track.rb` — `Track`, per-activity data wrapper with dedup awareness
- `lib/workouts/export/svg/poster.rb` — `Poster`, data object with dimensions/colors
- `lib/workouts/export/svg/base.rb` — `BaseDrawer`, abstract with `draw(doc, size, offset)`
- `lib/workouts/export/svg/github.rb` — GitHub-style heatmap grid
- `lib/workouts/export/svg/grid.rb` — Activity route map thumbnails
- `lib/workouts/export/svg/circular.rb` — Radial year calendar
- `lib/workouts/export/svg/month_of_life.rb` — 1200-month life calendar
- `lib/workouts/export/svg/year_summary.rb` — Single-year summary poster
- `lib/workouts/privacy/polyline_filter.rb` — Privacy polyline filter (start/end range stripping)
- `lib/workouts/analysis/calculator.rb` — Stats calculator
- `spec/export/` — Export tests
- `spec/privacy/` — Privacy filter tests
- `build/` — Output directory for all exports

## SVG dedup handling
- `Track#skip?` → true for high-confidence duplicates (`confidence >= 0.85`, flag: "derived")
- `Track#conflict?` → true for low-confidence overlaps (`0.15 <= confidence < 0.85`, flag: "overlap")
- Derived tracks skipped in grid/circular/year-summary; shown with dimming in github style
- Tooltips show: `Duplicate of {source} ({run_id}) — confidence: {n}%`

## Key defaults
- Output paths in config: JSON → `build/activities.json`, SVG → `build/svg/`, CSV → `build/workouts.csv`
- Privacy: strips 200m from start/end by default (configurable via `privacy.start_end_range`)
- Sport categories: run/ride/hike/walk/swim/ski/workout/other

## Testing
- `bundle exec rspec spec/export/` — All export tests
- Tests stub DB fixtures, verify output format
- SVG tests validate XML structure with Nokogiri
