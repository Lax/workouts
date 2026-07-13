# Per-source Cache + Garmin 拆分 — 实施计划

## 改动清单

| # | 文件 | 操作 |
|---|---|---|
| 1 | `.github/actions/source-cache/action.yml` | 新建 — 复合 action |
| 2 | `lib/workouts/sync/base.rb` | 删除 garmin 归一化 (lines 33, 47) |
| 3 | `lib/workouts/sync/garmin_base.rb` | 提取 `source_prefix` 方法, 替换 `run_id`/`source` 硬编码 |
| 4 | `lib/workouts/sync/garmin_cn.rb` | 覆写 `raw_dir`, `std_dir`, `source_prefix` |
| 5 | `.github/workflows/sync.yml` | 替换合并 cache → 7 per-source cache 块 |

---

## 1. `.github/actions/source-cache/action.yml` — 新建

Per-source cache 复合 action，封装 restore/check/save。

```yaml
name: Source Cache
description: Per-source cache restore/save with change detection
inputs:
  source:
    description: 'Source name'
    required: true
  phase:
    description: 'restore or save'
    required: true
  before_count:
    description: 'File count before sync (for save phase)'
    required: false
    default: ''
outputs:
  before_count:
    value: ${{ steps.before.outputs.count }}
  changed:
    value: ${{ steps.check.outputs.changed }}
runs:
  using: composite
  steps:
    - uses: actions/cache/restore@v4
      if: inputs.phase == 'restore'
      id: restore
      with:
        path: |
          data/raw/${{ inputs.source }}/
          data/std/${{ inputs.source }}/
        key: workouts-raw-v1-${{ inputs.source }}-${{ github.run_id }}
        restore-keys: workouts-raw-v1-${{ inputs.source }}-
    - name: Record before digest
      if: inputs.phase == 'restore'
      id: before
      shell: bash
      run: |
        count=$(find data/raw/${{ inputs.source }} data/std/${{ inputs.source }} \
          -type f 2>/dev/null | wc -l)
        echo "count=$count" >> $GITHUB_OUTPUT
    - name: Check changed
      if: inputs.phase == 'save'
      id: check
      shell: bash
      run: |
        after=$(find data/raw/${{ inputs.source }} data/std/${{ inputs.source }} \
          -type f 2>/dev/null | wc -l)
        before="${{ inputs.before_count }}"
        if [ -z "$before" ] || [ "$before" -ne "$after" ] 2>/dev/null; then
          echo "changed=true"
        else
          echo "changed=false"
        fi >> $GITHUB_OUTPUT
    - uses: actions/cache/save@v4
      if: inputs.phase == 'save' && steps.check.outputs.changed == 'true'
      with:
        path: |
          data/raw/${{ inputs.source }}/
          data/std/${{ inputs.source }}/
        key: workouts-raw-v1-${{ inputs.source }}-${{ github.run_id }}
```

## 2. `lib/workouts/sync/base.rb` — 删除归一化

Lines 33 和 47，各删一行:

```ruby
def raw_dir
  src = self.class.name.split("::").last.downcase
  # 删除: src = "garmin" if src.start_with?("garmin")
  File.join("data", "raw", src)
end

def std_dir
  src = self.class.name.split("::").last.downcase
  # 删除: src = "garmin" if src.start_with?("garmin")
  File.join("data", "std", src)
end
```

## 3. `lib/workouts/sync/garmin_base.rb` — 提取 source_prefix

在 `build_attrs` 之前或 `GarminBase` 类内新增:

```ruby
def source_prefix
  "garmin"
end
```

修改 `build_attrs` (lines 421, 442):

```ruby
# line 421 改前
run_id: "garmin_#{activity_id}",
# line 421 改后
run_id: "#{source_prefix}_#{activity_id}",

# line 442 改前
source: "garmin"
# line 442 改后
source: source_prefix
```

## 4. `lib/workouts/sync/garmin_cn.rb` — 覆写

在 `GarminCN` 类内新增:

```ruby
def raw_dir
  File.join("data", "raw", "garmin_cn")
end

def std_dir
  File.join("data", "std", "garmin_cn")
end

def source_prefix
  "garmin_cn"
end
```

## 5. `.github/workflows/sync.yml` — 替换 cache

### 删除

- Lines 38-45: `actions/cache/restore@v4` (id: `source-cache`)
- Lines 47-55: `Record source digest` 中的 source 部分 (保留 DB digest)
- Lines 145-150: `Check source changed`
- Lines 170-176: `actions/cache/save@v4` (source-cache)

### 新增 — Restore 块 (Garmin token caches 之后, Sync 之前)

```yaml
      - id: cache-keep
        uses: ./.github/actions/source-cache
        with:
          source: keep
          phase: restore

      - id: cache-igpsport
        uses: ./.github/actions/source-cache
        with:
          source: igpsport
          phase: restore

      - id: cache-xoss
        uses: ./.github/actions/source-cache
        with:
          source: xoss
          phase: restore

      - id: cache-xingzhe
        uses: ./.github/actions/source-cache
        with:
          source: xingzhe
          phase: restore

      - id: cache-garmin
        uses: ./.github/actions/source-cache
        with:
          source: garmin
          phase: restore

      - id: cache-garmin-cn
        uses: ./.github/actions/source-cache
        with:
          source: garmin_cn
          phase: restore

      - id: cache-strava
        uses: ./.github/actions/source-cache
        with:
          source: strava
          phase: restore
```

### 新增 — Save 块 (cron push 之后, upload-artifact 之前)

```yaml
      - uses: ./.github/actions/source-cache
        with:
          source: keep
          phase: save
          before_count: ${{ steps.cache-keep.outputs.before_count }}

      - uses: ./.github/actions/source-cache
        with:
          source: igpsport
          phase: save
          before_count: ${{ steps.cache-igpsport.outputs.before_count }}

      - uses: ./.github/actions/source-cache
        with:
          source: xoss
          phase: save
          before_count: ${{ steps.cache-xoss.outputs.before_count }}

      - uses: ./.github/actions/source-cache
        with:
          source: xingzhe
          phase: save
          before_count: ${{ steps.cache-xingzhe.outputs.before_count }}

      - uses: ./.github/actions/source-cache
        with:
          source: garmin
          phase: save
          before_count: ${{ steps.cache-garmin.outputs.before_count }}

      - uses: ./.github/actions/source-cache
        with:
          source: garmin_cn
          phase: save
          before_count: ${{ steps.cache-garmin-cn.outputs.before_count }}

      - uses: ./.github/actions/source-cache
        with:
          source: strava
          phase: save
          before_count: ${{ steps.cache-strava.outputs.before_count }}
```

### 保留不变

- DB cache restore/save
- DB digest
- Garmin token caches
- `db_changed` output
- DB artifact upload
- 所有 build/deploy job

## 迁移

首次部署后，Garmin CN 活动会产生重复记录。提供一次性清理命令:

```bash
sqlite3 data/workouts.db "DELETE FROM activities WHERE source = 'garmin' AND run_id LIKE 'garmin_%' AND id IN (SELECT a.id FROM activities a LEFT JOIN activities b ON b.run_id = 'garmin_cn_' || SUBSTR(a.run_id, 8) WHERE a.source = 'garmin' AND b.id IS NOT NULL);"
```

或删 DB 全量重建。
