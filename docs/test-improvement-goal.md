# Test Improvement — Goal & Spec

## 1. User Story

```
As maintainer (Lax),
I want regression protection on critical output paths,
so that the daily CI-generated Pages site won't break from code changes.

As CI pipeline,
I want faster feedback and focused validation,
so that core pipeline health is confirmed in <6 min instead of ~18 min.
```

## 2. Scenarios

```
Scenario A — Dashboard JS Robustness (regression guard)
Given: normal / empty / anomalous data (null polyline, zero-spread traces, single-point GPS)
When: export dashboard generates index.html
Then: page loads without console errors, map renders, charts render, filters work

Scenario B — Export Pipeline Data Contract
Given: 1~2000 activity records in DB
When: export stats + export dashboard run sequentially
Then: stats.json format matches dashboard JS consumption expectations, all required fields present

Scenario C — SVG Github Style Output
Given: at least 1 activity in DB
When: export svg --style github
Then: valid SVG file output (Nokogiri valid + contains key elements)

Scenario D — CI Matrix Efficiency
Given: CI triggers (push/PR/schedule)
When: test execution
Then: only Ruby 3.4 (matching production), total test time reduced

Scenario E — Sync Adapter Type Anomaly Guard
Given: API returns unexpected type (Hash vs String, Array vs String)
When: sync executes
Then: no crash, meaningful error message output
```

## 3. Requirements

| ID | Requirement | Pri | Risk Driver |
|----|-------------|-----|-------------|
| F1 | Dashboard JS doesn't crash under data edge cases (null, empty, boundary) | **P0** | 6 historical JS crashes |
| F2 | Dashboard output HTML contains all required DOM element IDs | **P0** | JS depends on element existence |
| F3 | export stats format consistent with dashboard JS consumer | **P0** | Data contract fracture |
| F4 | SVG github export remains valid SVG after code changes | **P1** | Pages core output |
| F5 | CI test matrix simplified to Ruby 3.4 only | **P1** | 18min -> ~6min |
| F6 | Sync adapters handle unexpected API types (Hash vs String) without crash | **P1** | 2 historical failures |
| F7 | Calculator core path smoke test (output structure correct) | **P2** | 217 lines untested |
| F8 | Dashboard JS syntax validated in CI | **P2** | Low prob, high impact |
| F9 | export all pipeline end-to-end test | **P2** | Multi-output consistency |
| F10 | Remove spec writes to `data/raw/` production dirs (Dir.mktmpdir) | **P2** | Test pollution |
| F11 | CI build job validates more output formats (not just SVG) | **P3** | CI blind spot |
| NF1 | Test execution time <= 5 min (single version) | non-func | CI efficiency |
| NF2 | No new gem dependencies | non-func | Minimize deps |
| NF3 | Zero external network in tests | non-func | Existing constraint |

## 4. Design Decisions

```
Decision 1: Dashboard JS Test Approach
- Option A: Extract JS from Ruby heredoc -> node -e isolated test
- Option B: Extract via regex in Ruby spec -> ExecJS/mini_racer
- Option C: Verify generated HTML structure + key function existence (no JS exec)
- Conclusion: A + C. Extract JS via regex from build_html, write temp file,
  `node -e "new Function(code)"` syntax check + Node assert for pure functions.
  Also verify HTML element structure in Ruby spec.
  Rationale: zero new gems (node is on CI ubuntu-latest), pure functions isolatable.

Decision 2: Ruby Version Matrix
- Option A: Ruby 3.4 only
- Option B: 3.3 + 3.4
- Option C: Keep 3.2 + 3.3 + 3.4
- Conclusion: A. Rationale: (1) not a published gem, (2) Docker + prod uses 3.4,
  (3) build job already 3.4, (4) all 413 tests green across all 3 versions,
  (5) 3.3 -> 3.4 has no compat issues.

Decision 3: SVG Drawer Test Scope
- Option A: Test all 5 styles
- Option B: GithubDrawer only (current)
- Option C: Github + smoke test for Renderer orchestration
- Conclusion: B + Renderer smoke. Rationale: other 4 styles have 1 commit each,
  never changed, personal tool.

Decision 4: Dashboard JS Test Granularity
- Option A: Unit test each JS function
- Option B: Integration: empty data, normal data, anomalous polyline
- Conclusion: B. Rationale: all 6 historical crashes were data edge conditions
  (null, empty array, single point), not individual function logic errors.

Decision 5: Coverage Tool
- Option A: Add SimpleCov
- Option B: No coverage tool, risk-based test allocation
- Conclusion: B. Rationale: SimpleCov encourages numbers game; adversarial
  review shows coverage != risk.
```

## 5. Spec (File-Level Changes)

| File | Type | Description |
|------|------|-------------|
| `docs/test-improvement-goal.md` | **new** | This document |
| `docs/test-improvement-research.md` | **new** | Adversarial review record |
| `docs/test-improvement-impl.md` | **new** | Implementation checklist |
| `spec/export/dashboard_spec.rb` | **new** | Dashboard integration test (~100 lines) |
| `spec/export/stats_spec.rb` | **new** | Stats export + Calculator indirect coverage (~60 lines) |
| `spec/export/svg_spec.rb` | **modify** | Add Renderer orchestration smoke test (~20 lines) |
| `.github/workflows/ci.yml` | **modify** | Matrix 3.2/3.3/3.4 -> 3.4 only |
| `.github/workflows/sync.yml` | **modify** | Build job: add HTML/JS validation step |
| `spec/sync/keep_integration_spec.rb` | **modify** | `rm_rf` -> `Dir.mktmpdir` |
| `spec/sync/igpsport_spec.rb` | **modify** | same |
| `spec/sync/xingzhe_spec.rb` | **modify** | same |
| `spec/sync/strava_spec.rb` | **modify** | same |
| `workouts-cli.gemspec` | **modify** | `required_ruby_version` -> `>= 3.4` |

## 6. Acceptance

```
Dashboard:
  - [ ] `bundle exec rspec spec/export/dashboard_spec.rb` all green
  - [ ] Simulated null polyline -> no JS exception
  - [ ] Simulated empty activity list -> page renders without crash
  - [ ] HTML contains all 6 required DOM IDs (map, app-drawer, chart, etc.)

Stats/Calculator:
  - [ ] `bundle exec rspec spec/export/stats_spec.rb` all green
  - [ ] Empty DB returns `{ summary: {}, monthly: [], yearly: [], streaks: {}, activity_types: [] }`
  - [ ] Mixed sport type breakdown correct

SVG:
  - [ ] Renderer orchestration smoke test passes
  - [ ] `bundle exec rspec spec/export/svg_spec.rb` all green

CI:
  - [ ] `.github/workflows/ci.yml` only ruby-version: "3.4"
  - [ ] CI run time <= 6 min (was ~18 min)
  - [ ] Build job adds HTML/JS validation step

Garmin type anomaly:
  - [ ] `bundle exec rspec spec/sync/garmin_base_spec.rb` includes type anomaly tests

Spec isolation:
  - [ ] No spec writes to `data/raw/` or `data/std/`
  - [ ] All file ops use `Dir.mktmpdir`

gemspec:
  - [ ] `required_ruby_version = ">= 3.4"`
```
