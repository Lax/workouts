# Test Improvement — Research & Adversarial Review

## 1. Current State (pre-change)

### Spec-to-Lib Map

| Area | Lib Files | Spec Files | `it` Count | Status |
|------|-----------|------------|------------|--------|
| Config | 1 (79 lines) | 1 | 6 | All green |
| SportMapper | 1 (39 lines) | 1 | 6 | All green |
| CLI | 5 (CLI + 4 subcmd) | 2 | 15 (reg only) | Only cmd registry |
| Export JSON/CSV/SVG | 4 | 3 | 35 | JSON/CSV full, SVG partial |
| Sync (7 adapters) | ~8 files | 12 files | ~233 | All green |
| Sync Base | 1 (109 lines) | 1 | 18 | All green |
| Garmin (base+intl+CN) | 3 | 3 | 72 | All green |
| Keep | 1 | 3 | 43 | All green |
| Strava/iGPSPORT/XOSS/XingZhe | 4 | 4 | 73 | All green |
| Tally | 1 (120 lines) | 1 | 56 | All green |
| FIT Decoder | 1 | 1 | 8 | All green |
| Geo (coord + polyline) | 2 | 2 | 15 | All green |
| Parser (GPX + TCX) | 2 | 2 | 17 | All green |
| Privacy | 1 | 1 | 7 | All green |
| Scripts | 1 (shell) | 1 | 13 | All green |
| Migrate | 2 | 1 | 20 | All green |
| **Analysis::Calculator** (217 lines) | 1 | **0** | **0** | **BIG GAP** |
| **Export::Dashboard** (957 lines) | 1 | **0** | **0** | **BIG GAP** |
| **Export::Stats** (20 lines) | 1 | **0** | **0** | **thin wrapper** |
| **Export::GPX** (133 lines) | 1 | **0** | **0** | **untested** |
| **SVG drawers** (5 styles) | 6 | 1 (Github only) | 13 | **4 styles untested** |
| **Auth** (GarminToken + Strava) | 2 | **0** | **0** | **untested** |
| **DB** (connection + activity) | 2 | **0** | **0** | **untested** |

### Key Deps

| Gem | Version |
|-----|---------|
| rspec | 3.13.2 |
| sequel | 5.105.0 |
| sqlite3 | 2.9.4 |
| thor | 1.5.0 |
| faraday | 2.14.3 |
| nokogiri | 1.19.4 |
| mini_racer | 0.21.1 |

No simplecov, no webmock, no vcr, no factory_bot.

## 2. Adversarial Review — Git History Bug Analysis

### Method

Searched full git log with `--grep` for fix/bug/crash/error/broken.
Read each matching commit to classify failure type and whether a test would have caught it.

### Findings: Production Bugs by Category

#### Dashboard JS Crashes (6 bugs — highest risk)

| Commit | Bug | Would test catch? |
|--------|-----|-------------------|
| `f4c4721` | Corrupted GPS coordinates crash map bounds | YES — test with corrupt polyline |
| `6248e61` | (duplicate fix) | YES |
| `080fd2a` | Zero-spread traces (single-point noise) crash renderMap | YES — test with 1-point polyline |
| `9532495` | Null guards missing in renderChart/renderChartSmall + stale closure | YES — test with empty/null data |
| `56c6d8f` | IIFE scope isolation breaks onclick handlers | PARTIAL — syntax check would not catch; runtime test would |
| `3971f7a` | Gentler time decay + zoom-dependent line width (map rendering) | HARD — visual regression |

**Pattern**: 5/6 would be caught by data edge condition tests for the dashboard.

#### Garmin API Type Shifts (2 bugs)

| Commit | Bug | Would test catch? |
|--------|-----|-------------------|
| `6a910b3` | Garmin DI API returns polyline as array (not string) | YES — stub API returning array type |
| `e4580b8` | Garmin API returns activityType as Hash (not string) | YES — stub API returning Hash type |

**Pattern**: Type contract tests on API response parsing would catch both.

#### Data Pipeline Bugs (5 bugs)

| Commit | Bug | Would test catch? |
|--------|-----|-------------------|
| `5a1d05b` | FIT decoder missing `* 180` in semicircle conversion (GPS off) | YES — known coordinate test fixture |
| `d81e570` | iGPSPORT HR nil (not extracted from FIT) | YES — nil HR after decode |
| `38aff5f` | XingZhe polyline reads from wrong source (API vs L1 file) | HARD — integration test needed |
| `49dbc53` | Indoor activity FIT timestamp missing first_timestamp | YES — edge case in FIT decode |
| `1e1f936` | Empty config keys not skipped | YES — config nil handling test |

**Pattern**: 4/5 would be caught by edge case tests in existing spec files.

#### CI/Deploy (5 bugs — ops, not code)

Permission, PAT format, credentials — no test can prevent these.

### Churn Analysis (git log --oneline --follow commit counts)

| File | Commits | Primary Risk |
|------|---------|--------------|
| `lib/workouts/sync/garmin_base.rb` | 22 | Auth contract changes |
| `lib/workouts/cli.rb` | 18 | Command routing |
| `lib/workouts/export/dashboard.rb` | 13 | JS crashes + style changes |
| `lib/workouts/sync/keep.rb` | 13 | API response parsing |
| `lib/workouts/export/svg/github.rb` | 6 | Histogram rendering |
| `lib/workouts/analysis/calculator.rb` | 2 | Stable — low risk |
| `lib/workouts/export/svg/circular.rb` | 1 | Stall — never changed |
| `lib/workouts/export/svg/grid.rb` | 1 | Stall — never changed |
| `lib/workouts/export/svg/month_of_life.rb` | 1 | Stall — never changed |
| `lib/workouts/export/svg/year_summary.rb` | 1 | Stall — never changed |

### Key Insight

**Coverage != risk.** The highest-churn, highest-bug areas (Dashboard, Garmin) are NOT the most untested. The untested Calculator (217 lines, 2 commits, 0 bugs) is low risk. The tested Garmin (72 tests, 22 commits, 2 bugs) is high churn but well-guarded.

The real gaps:
1. Dashboard JS edge conditions (6 historical bugs, 0 tests) — **highest ROI**
2. Garmin API type contract (2 historical bugs partially tested) — **good ROI**
3. Data pipeline edge cases (5 historical bugs, mostly covered) — **low ROI for new tests**
4. CI matrix waste (3 versions, only 1 used in prod) — **easy win**

## 3. Production Environment

| Layer | Ruby | Notes |
|-------|------|-------|
| Docker image | 3.4 | `FROM ruby:3.4-slim` |
| CI sync job | 3.4 | Runs daily schedule |
| CI build job | 3.4 | `ruby-version: '3.4'` |
| CI ci.yml matrix | 3.2 / 3.3 / 3.4 | **MISMATCH with prod** |
| gemspec | >= 3.1 | **Outdated requirement** |
| Local dev | varies (likely 3.4) | Developer machine |

**Conclusion**: Ruby 3.4 is the only version that runs in production. Testing 3.2+3.3 adds CI cost with zero production value.

## 4. Decision Record

### DR-001: Dashboard JS Test via Node.js
- **Context**: 550 lines JS inline in Ruby heredoc. 6 historical crashes.
- **Options**:
  - A) Extract JS -> temp file, `node -e "new Function(code)"` + Node assert
  - B) MiniRacer/ExecJS in Ruby (already have mini_racer dep)
  - C) Only verify HTML structure, skip JS execution
- **Chosen**: A. Rationale: node is always available in CI ubuntu-latest. No new deps. Pure JS functions testable in isolation.
- **Risk**: If CI runner ever drops node, this breaks. Mitigation: simple, node is core to ubuntu.

### DR-002: Single Ruby Version (3.4)
- **Context**: gemspec says >= 3.1, CI tests 3 versions, prod uses 3.4.
- **Options**:
  - A) 3.4 only (match prod)
  - B) 3.3 + 3.4 (one-version buffer)
  - C) Keep all 3
- **Chosen**: A. Rationale: private tool, not a published gem. Prod consistency > theoretical compat.
- **Risk**: If someone clones and uses Ruby 3.3, some syntax might not work. Mitigation: Docker is the primary execution method.

### DR-003: No SimpleCov
- **Context**: Coverage tool not configured. Query: should we add it?
- **Options**:
  - A) Add SimpleCov, set threshold
  - B) Keep no coverage tool
- **Chosen**: B. Rationale: coverage is a lagging indicator. Risk-based test allocation (from adversarial review) is more valuable than a %. Adding SimpleCov encourages writing tests for coverage rather than for risk reduction.

### DR-004: Unchanged SVG Drawers (4 styles) Stay Untested
- **Context**: circular, grid, month_of_life, year_summary each have 1 commit (initial creation), zero changes.
- **Options**:
  - A) Write basic smoke tests for all 4
  - B) Only test Renderer orchestration + Github
- **Chosen**: B. Rationale: zero-churn code doesn't need tests. If someone starts changing them, tests can be added then.
