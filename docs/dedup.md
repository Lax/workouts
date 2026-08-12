# Dedup — 跨源去重（设计记录）

> **已迁移至 git-fit gem。** 文中 `lib/workouts/dedup/*`、`lib/workouts/sync/*`、`lib/workouts/import/*` 为迁移前的本地路径（现已删除），dedup 逻辑位于 git-fit（`Dedup::Service` / `Dedup::Matcher` / `Dedup::Trajectory` / `Dedup::FieldElector` / `Dedup::GroupConsolidator`），详见 git-fit 仓库 `docs/dedup-design.md`。以下保留设计记录。

本文档由 `dedup-redesign.md`（重构设计）、`dedup-research.md`（数据调研）、`dedup-roadmap.md`（执行路线图）合并而成。时间格式统一方案详见 [`docs/time-format-iso8601.md`](time-format-iso8601.md)，外部标识符方案详见 [`docs/external-id.md`](external-id.md)。

---

## 1. 概述

### 1.1 现有 DedupService 局限

Apple Health 跨源分析中发现的现有去重体系限制：

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

### 1.2 归档 DB 调研统计

基于归档 DB（2103 activities、8 sources，含 apple_health 908）：

- **813 cross-source duplicate pairs** after timezone correction
- **573/908 (63.1%)** Apple Health records have at least one duplicate
- **Up to 5 copies** per physical activity (AH + Keep + Strava + iGPSPORT + Garmin CN)
- **442 days** with at least one cross-source duplicate
- Per-source distribution: Keep=496, Strava=59, iGPSPORT=55, Garmin=46, XOSS=40, XingZhe=8, Garmin CN=1

### 1.3 去重体系层级

| 层级 | 机制 | 位置 | 覆盖 |
|---|---|---|---|
| L1 | `run_id` UNIQUE（同源内） | 各 adapter `build_attrs` | 同源去重 |
| L2 | Dedup::Service（跨源滑动窗口） | `lib/workouts/dedup/service.rb` | 全源两两匹配 |
| L3 | Dedup::Matcher（置信度） | `lib/workouts/dedup/matcher.rb` | 时间/距离/时长/类型 |
| L4 | Dedup::Trajectory（轨迹重叠） | `lib/workouts/dedup/trajectory.rb` | GPS 采样点 30% 在 50m 内 |

### 1.4 重构总览

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
│   └── Dedup tables (dedup_groups + dedup_group_members)
│
├── Classification (flag selection)
├── Field-level election (export-time computed, no persistence)
├── N>2 group management (union-find)
└── Quantified dedup analysis (scripts/dedup-quantify.rb)
```

---

## 2. 数据调研

### 2.1 数据源概览（线上，liulantao.com/workouts）

| Source | 数量 | 有 GPS | 有心率 | 有本地时区 |
|---|---|---|---|---|
| apple_health | 908 | 29.0% | ~5% | 21.6% |
| keep | 876 | 0% | 0% | 100% |
| strava | 100 | 86% | 73% | 100% |
| igpsport | 85 | 100% | 98% | 100% |
| garmin | 55 | 96% | 93% | 100% |
| xoss | 44 | 100% | 100% | 100% |
| xingzhe | 34 | 58% | 65% | 100% |
| garmin_cn | 1 | 100% | 100% | 100% |

### 2.2 归档分支数据量

| 分支 | Activities | 备注 |
|---|---|---|
| `_/workouts-db` | 2,103 | 完整 DB 快照（无 apple_health 前） |
| `_/_/garmin` | 38 | FIT + GPS std |
| `_/_/keep` | 876 | 解密 JSON + std |
| `_/_/strava` | 100 | JSON + std |
| `_/_/igpsport` | 85 | FIT + std |
| `_/_/xoss` | 44 | FIT + std |
| `_/_/xingzhe` | 34 | GPX + std |
| `_/_/garmin_cn` | 1 | FIT + std |

### 2.3 Archive 分支数据字段可用性（per std point）

| 分支 | lat/lng | ele | timestamp | heartRate | speed | temperature | cadence | power |
|---|---|---|---|---|---|---|---|---|
| garmin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| keep | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| strava | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| igpsport | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| xoss | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| xingzhe | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| garmin_cn | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |

---

## 3. 场景分析（9 种去重场景）

### 3.1 精准重复

同一条真实活动，在不同平台之间多次同步，产生少量数据误差和非关键数据变化。

**触发条件**

- 同一设备/源的活动通过 HealthKit 被 Apple Health 捕获
- 同一条 Strava 活动既被 Strava sync adapter 拉取，又被 Apple Health 从 Strava 同步
- Garmin Connect 既被 Garmin sync adapter 拉取，又通过 HealthKit 写入 Apple Health

**典型案例：Apple Health(Strava) vs Strava sync**

Apple Health export.xml 中 Strava 源活动包含 `HKExternalUUID`：

```xml
<MetadataEntry key="HKExternalUUID" value="strava://activities/3056096737"/>
```

Strava sync adapter 的 run_id = `strava_3056096737`。两条记录指向同一条 Strava 活动。

**对比数据**（2020-01-30 15km Running）：

| 字段 | apple_health(Strava) | strava sync | 差异 |
|---|---|---|---|
| distance | 15,011.7 m | 15,006.2 m | 0.04%（取整） |
| moving_time | 5,355s（duration） | 5,305s（Strava moving_time） | 50s / 0.9% |
| start_date | 2020-01-30 17:31:53 | 2020-01-30 17:31:53 | 一致 |
| average_heartrate | null | 165 bpm | Strava 有心率 |
| summary_polyline | null | polyline | Strava 有 GPS |
| calories | null | 1,122 kcal | Strava 有 |

**导出重复量**：~12 条（从 5 组 hash 碰撞推断）

**标识线索**

- sourceName = "Strava" 且 MetadataEntry 含 `HKExternalUUID`
- sourceName = "Connect" 或 "Garmin Connect"
- start_date + distance + duration 三元组极高置信度匹配

### 3.2 双设备同时记录

码表和手表同时记录一次骑行，起止时间基本一致，轨迹路线高度重叠，但码表和手表 GPS 芯片精度不同导致统计值有微小差异。

**触发条件**

- Garmin Edge（码表）和 Garmin Fenix/Forerunner（手表）同时记录同一次骑行
- Apple Watch + iPhone 同时记录一次户外步行
- 码表开启、手机端 Keep/Strava app 也同时记录

**Matcher 预期表现**

| 因子 | 码表 vs 手表 | 置信度 |
|---|---|---|
| 时间相近度 35% | start 差 2-10s | ~0.98 |
| 距离相近度 35% | distance 差 1-3% | ~0.90 |
| 时长相近度 15% | moving_time 差 0-5% | ~0.95 |
| 运动类型 15% | 都是 ride | 1.0 |
| **总分** | | **~0.94** |

轨迹重叠率预计 > 90%（`Trajectory` 阈值 30% 远低于此），flag 应为 `derived`。

**当前缺口**

- 无"设备类型"字段区分码表 vs 手表（FIT 的 `manufacturer` / `product` 字段未被解析到 DB）
- 无法判断哪条记录应该保留、哪条该标记为 derived
- 字段归并策略不明确：手表的心率（通常更准）vs 码表的功率/速度

### 3.3 部分重叠（包含/交叉）

#### 3.3a 包含关系

一次活动的时间窗口完全包含另一次活动。

**示例**：
- 长跑 2h（Garmin），其中 11min 步行段被 Apple Watch 单独记录为 Walking
- 骑车到健身房 → 室内训练 → 骑车回家，Apple Health 可能记成三段独立活动，Garmin 记成一段

**Matcher 问题**：
- 步行（walk）vs 长跑（run）：`cat_score = -0.67`，即使距离/时间匹配也会大幅降分
- `distance_score` 阈值 15%：步行距离 ~500m，跑步距离 ~15,000m → `diff/max = 96%` → 返回 nil 过滤

**Dedup::Trajectory 问题**：
- 步行段 GPS 100% 在跑步轨迹 50m 范围内 → 触发 `duplicate` flag
- 但反过来，跑步段的 GPS 可能只有 < 10% 在步行轨迹内（因为大部分轨迹不重叠）
- 当前 trajectory 检查只做"采样点 A 是否在 B 轨迹 50m 内"，不做双向判定

#### 3.3b 交叉关系

两活动时间窗口部分重叠，路线可能重叠也可能不同。

**示例**：
- 在操场绕圈跑的 runner 和同时在旁边散步的 walker
- 两活动在轨迹上有交叉点但整体路线不同

**Matcher 表现**：
- 时间窗口差 < 300s + elapsed_time 缓冲 → 可能进入比较
- 距离差可能很大 → `distance_score` 返回 nil 过滤
- 若距离也接近（如同路线不同配速）→ 可能误判

**缺口**：
- 轨迹重叠率的双向判定缺失
- "部分重叠"无独立 flag（当前只有 derived/duplicate/similar/overlap）

### 3.4 外部 ID 精确匹配

数据中包含其它源的数据 ID 标识。

**已知外部 ID**

| 源 | 外部 ID 字段 | 示例值 | 出现范围 |
|---|---|---|---|
| Strava（Apple Health） | `HKExternalUUID`（MetadataEntry） | `strava://activities/3056096737` | ~12 条 AH(Strava) |
| iGPSPORT | 可能通过第三方关联（待查） | — | 未知 |
| XOSS | run_id 前缀 `xoss_`；FIT 中可能有原始 ID | — | 未知 |

**未发现外部 ID 的源**

- Keep：MetadataEntry 中无外部 UUID
- Connect（Garmin）：无外部 UUID
- XingZhe：无

**external_id 实施方案**

```
DB migration: activities 加 external_id TEXT
索引: CREATE INDEX activities_external_id_index ON activities (external_id)

写入规则：
  Strava adapter: 写入 "strava://activities/{id}"
  Apple Health import: meta["HKExternalUUID"] 若存在则写入
  其他 adapter: 暂不写入（null）

匹配规则（Dedup::Matcher 增加）:
  if a[:external_id] && a[:external_id] == b[:external_id]
    return 1.0  # 置信度直接满
  end
```

### 3.5 同路线不同运动类型

同一 GPS 轨迹，不同平台/用户标记为不同运动类型。

**常见映射差异**

| 真实运动 | Garmin | Strava | Apple Health | Keep |
|---|---|---|---|---|
| 徒步登山 | hiking | hike | hiking / walking | outdoorWalking |
| 越野跑 | trail_running | trailrun / run | running | outdoorRunning |
| 城市骑行 | cycling / road_biking | ride | cycling | outdoorCycling |
| 滑雪 | cross_country_skiing | nordicski | skiing | — |
| 室内骑行 | indoor_cycling | virtualride | cycling | cycling |

**Matcher 表现**

```ruby
cat_score = a[:sport_category] == b[:sport_category] ? 1.0 : -0.67
```

不同 category → `-0.67 × 0.15 = -0.1`，总分被拖低 0.1。若其他因子匹配度 > 0.88，仍可能达到 `derived` 阈值 0.85。

但 `-0.67` 是硬编码惩罚——hike↔walk 的差异远小于 run↔swim 的差异，应当有层次。

**建议**：引入 SportMapper 的 Levenshtein 距离或人工分类树：

```
same_sport_group?(hike, walk)   → cat_score = 0.5
same_sport_group?(run, swim)    → cat_score = -1.0
same_sport_group?(ride, run)    → cat_score = -0.67 (不变)
```

运动类型分组：
- **步行类**：walk, hike
- **跑步类**：run, trail_run
- **骑行类**：ride, bike, ebike
- **水上类**：swim, rowing, kayaking
- **室内类**：workout, strength, elliptical

### 3.6 断线分段记录

设备在记录过程中断连或重启，导致一段连续运动被切割为多条记录。

**触发条件**

- Garmin 手表电池耗尽 → 20km 处自动保存前半段 FIT → 充电后重新记录后半段
- 蓝牙断连 → Apple Watch 和 iPhone 各自记录片段
- 运动中途暂停时间超过设备自动保存阈值

**识别特征**

- 两活动 `start_date` / `end_date` **连续或接近衔接**（差 < 30s）
- 轨迹终点与起点 GPS 坐标**在 50m 范围内**（衔接点可辨认）
- 两活动的 `sport_category`、`source` 相同
- 两活动的 `device_name` 相同（FIT 中 `product` / `manufacturer` 字段）

**合并策略**

```
if
  a.source == b.source &&
  a.sport_category == b.sport_category &&
  (a.end_date - b.start_date).abs < 30s &&
  distance(a.end_coords, b.start_coords) < 50m
then
  conflict = derived
  # 合并字段：distance + moving_time + elevation_gain + calories
```

**数据验证**：无现成数据，当前记录中没有明显断线的例子。

### 3.7 手动创建的活动

用户在平台 A 手动创建一条活动，内容和平台 B 自动记录的完全相同。

**示例**

- 用户忘记戴手表，在 Strava 网页手动输入 10km 跑步
- Garmin Connect 上手动合并两段 FIT 为一条活动
- 用户导出 GPX 后重新导入到另一个平台（通过 `import gpx`）

**识别难度**

- 无外部 ID
- 时间、距离、类型完全一致
- GPS 可能缺失（手动录入不提供）
- Matcher 可以匹配到（distance + time 高度一致），但阈值选择困难

### 3.8 服务端去重后残留

源平台自身做了去重，但重复数据通过不同同步路径进入 Workouts。

**示例**

- Strava 合并了两条重复 Garmin 活动（内部去重），但 Apple Health 在 Strava 去重前已经同步过
- Garmin 端去重后删除了一条 FIT，但 Apple Health 的 Connect 同步仍在

**识别特征**

- 同 `external_id` 匹配（Strava 场景）
- 非同源时：时间+距离匹配，但 metadata 差异提示不同同步批次

### 3.9 每日重复训练

不同日期的相同训练计划（如同路线 5km 跑步、同路线通勤骑行），数据极其相似但不是同一活动。

**这是 Matcher 的 false positive 高风险场景**

| 字段 | Day 1 | Day 2 | 差异 |
|---|---|---|---|
| start | 07:00 | 07:00 | 差 24h（超出窗口 → 不比较） |
| route | 同路线 | 同路线 | GPS 几乎重叠 |
| distance | 5.02 km | 5.08 km | 1.2% |
| moving_time | 25:30 | 26:10 | 2.6% |

**现有防御**

```ruby
t_diff = time_diff_abs(a[:start_date], b[:start_date])
max_diff = [300, (a[:elapsed_time] || 0).to_i, (b[:elapsed_time] || 0).to_i].max
return 0.0 if t_diff > max_diff
```

`max_diff` = max(300, elapsed_time) ≈ 300~3600s。
- 同一天不同时间（如早 7:00 和晚 7:00）：差 12h → 远大于 max_diff → 正确排除
- 连续两天同时间：差 24h → 正确排除
- 但若 `elapsed_time` 很大（如 10h 徒步），`max_diff = 36000`，跨天或可能被纳入窗口 → 此时轨迹重叠率很高 → 误判为 duplicate

**建议**：在 Trajectory 判定中增加 `start_date` 间隔惩罚因子，间隔 > 2h 的即使轨迹重叠也降级为 `similar`。

---

## 4. 重构设计

### P0 — 基础设施

#### 时间窗口

**Current:** `group_by { |a| parse_time(a[:start_date]).to_date }` → compare only within same calendar date.

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

**Why ±1 day?** 当前窗口实际是 0 天（同日期分组）。扩展到 ±1 天覆盖：
- Midnight-crossing activities (start 23:50, end 00:30)
- Activities separated by a few hours (morning run → evening run, same day)
- Activities with one source recording start time a few hours off from another (rare but documented in Garmin dual-device scenarios)

O(N²) comparison 仍成立（2103 activities → ~2.2M pairs worst case），但 `b_start > window_end` 提前 break 保持可控。

#### parse_time: Unified ISO 8601

**Current:**
```ruby
def parse_time(val)
  return nil unless val
  Time.parse(val.to_s)
rescue
  nil
end
```

✅ 已兼容 `"%Y-%m-%d %H:%M:%S"` 和 ISO 8601 格式。`Time.parse` handles both。

时间格式迁移后（见 `docs/time-format-iso8601.md`），仅剩带 zone 后缀的 ISO 8601。post-migration 无需兼容层。

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

#### Duration: Use `[moving_time, elapsed_time].max`

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

**Why max?** `moving_time` without pause filtering ≈ `elapsed_time`，而带 pause filtering 的 `moving_time` < `elapsed_time`。`max` 使两种类型收敛到总活动时长。时长比较变为：

```ruby
duration_a = effective_duration(a)
duration_b = effective_duration(b)
if duration_a > 0 && duration_b > 0
  duration_diff = (duration_a - duration_b).abs / [duration_a, duration_b].max
  duration_score = duration_diff <= 0.15 ? (1 - duration_diff) * 0.15 : 0
end
```

#### sport_category: Hierarchical Groups

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

**Compatibility matrix**（独立于组归属）:

| A \ B | run | ride | hike | walk | swim | ski | workout | other |
|---|---|---|---|---|---|---|---|---|
| **run** | +0.15 | -0.10 | -0.05 | -0.05 | -0.10 | -0.10 | -0.10 | -0.10 |
| **ride** | -0.10 | +0.15 | -0.10 | -0.10 | -0.10 | -0.10 | -0.10 | -0.10 |
| **hike** | -0.05 | -0.10 | +0.15 | +0.15 | -0.10 | -0.05 | -0.10 | -0.05 |
| **walk** | -0.05 | -0.10 | +0.15 | +0.15 | -0.10 | -0.10 | -0.10 | -0.05 |
| **swim** | -0.10 | -0.10 | -0.10 | -0.10 | +0.15 | -0.10 | -0.10 | -0.10 |

### P1 — 精确匹配通道（external_id）

详见 `docs/external-id.md` 完整规格。

**DedupService 集成:**

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

**Expected yield:** ~27 exact pairs (Strava↔AH)。

### P2 — GPS 轨迹匹配

**Current State**

`Trajectory#duplicate?` reads L2 JSON files, samples every 10th point, checks if ≥30% of sampled points are within 50m of the other trajectory. This is a **containment** test。

**Limitations**

- Only binary yes/no (≥30% threshold)
- No similarity scoring (how close are the trajectories on a 0-1 scale?)
- No partial overlap detection (30% threshold too binary)
- Hardcoded 10-point stride, 50m radius
- No cross-overlap detection (A overlaps B in section 1, B overlaps A in section 3)
- L2 files may be missing → silently skips

#### Douglas-Peucker 简化

提取"特征点"，3000 点降至 20-50 关键点，同时保留整体形状。作为 DTW 和 Hausdorff 的输入。

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

#### DTW（Dynamic Time Warping）

两条简化轨迹之间的相似度分数。返回归一化分数 [0, 1]，1 = 形状完全相同（与采样点数无关）。

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

#### Hausdorff 距离

两个点集之间的最大偏差。用于检测部分重叠。

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

#### Overlap Ratio（增强现有）

用连续分数替代二值 ≥30% 阈值：

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

#### 复合评分模型

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

#### Flag 分类（更新）

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

**最终 flag 集**

| Flag | Meaning | Condition |
|---|---|---|
| `derived` | Same activity, different source | external_id=1.0 OR confidence≥0.85 |
| `duplicate` | High overlap, trajectory equivalent | ≥0.15 + containment==equivalent |
| `contained` | One trajectory ⊂ the other | ≥0.15 + partial containment |
| `partial` | 30-70% overlap | ≥0.15 + partial containment |
| `cross` | Points intersect, minimal overlap | ≥0.15 + cross containment |
| `similar` | Same time/dist, different route | ≥0.15 + disjoint |

### P3 — 生产化

#### CLI 入口

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

#### 日志格式

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

#### JSON 日志输出

`--log FILE` 指定或默认：

```
data/dedup/2026-07-19T100000Z.json
```

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

#### Runner 自动触发

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

#### Dedup 分组表

**不存 `activities` 表。** 组归属放独立表，保持 `activities` schema 干净：

```sql
CREATE TABLE dedup_groups (
  id         INTEGER PRIMARY KEY,
  group_id   TEXT NOT NULL UNIQUE,       -- SHA256(sorted_run_ids)[0,16]
  created_at DATETIME,
  updated_at DATETIME
);

CREATE TABLE dedup_group_members (
  id           INTEGER PRIMARY KEY,
  group_id     TEXT NOT NULL REFERENCES dedup_groups(group_id),
  run_id       TEXT NOT NULL REFERENCES activities(run_id),
  source       TEXT NOT NULL,
  flag         TEXT,                     -- derived/duplicate/similar/contained/partial/cross
  confidence   REAL,                    -- max confidence for this member in this group
  UNIQUE(group_id, run_id)
);

-- Fast lookup: find group for a given run_id
CREATE INDEX idx_dedup_member_run_id ON dedup_group_members(run_id);
```

**Group assignment（首次匹配后）:**

```ruby
def assign_dedup_group(matched_pairs)
  # Union-Find over all matched run_ids
  groups = consolidate(matched_pairs)

  groups.each do |group_id, run_ids|
    members = @db[:activities].where(run_id: run_ids).all
    write_group(group_id, members)
  end
end

def write_group(group_id, members)
  @db[:dedup_groups].insert_conflict(
    constraint: :dedup_groups_group_id_key,
    insert: { group_id: group_id, created_at: Time.now.utc, updated_at: Time.now.utc }
  )

  members.each do |m|
    @db[:dedup_group_members].insert_conflict(
      constraint: :dedup_group_members_group_id_run_id_key,
      insert: {
        group_id: group_id,
        run_id: m[:run_id],
        source: m[:source],
        flag: m[:_dedup_flag],
        confidence: m[:_dedup_confidence]
      }
    )
  end
end
```

**Incremental dedup:** 后续运行只比较不在 `dedup_group_members` 中的记录：

```sql
SELECT a.* FROM activities a
WHERE a.run_id NOT IN (
  SELECT run_id FROM dedup_group_members
)
```

---

## 5. 字段级选举

### 概念

在 `dedup_group` 内，没有单一源拥有全部最佳数据。不选举单条 canonical record，而是**逐字段选举**：

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

### 选举规则

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

Lower number = higher priority。

### 选举实现

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

### Composite Record 持久化

**决策：export 时计算，不持久化（无 DB 表、无文件缓存）。**

Rationale:
- **Not in DB**: DB 有自己的 GH Cache 备份机制（per-source cache digests）。持久化 composite 会在选举逻辑变化时频繁失效缓存，触发不必要重建。`dedup_groups` + `dedup_group_members`（"primary" 数据）仅当 DedupService 重跑时变化，频率低。
- **No file cache**: 选举是纯函数（确定性算法 + 相同输入 = 相同输出）。重算代价可忽略：~0.1ms/group × ~500 groups = **~50ms total**。
- **Export-time only**: JSON/SVG/Stats exporters 组装输出时按需计算 composite。

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

Export 流程:

```
Export JSON/SVG/Stats:
  activities ← dedup_groups LEFT JOIN dedup_group_members (via .run_id)
  group_id non-null?
    → read dedup_group_members for that group
    → FieldElector.elect(field, values) for each field
    → composite[:dedup_group] = group_id
    → composite[:member_sources] = [{ source, run_id, flag, confidence }, ...]
    → use composite activities row in output
  group_id null?
    → use original activities row directly
```

---

## 6. N>2 分组管理

### 默认：pair-wise 匹配

DedupService 产生 pair-wise matches。每条记录累积自己的 `duplicate_info` 数组。

5-source group 示例：

```
apple_health_a1b2c3.duplicate_info = [
  { source: "strava", run_id: "strava_123", confidence: 1.0, flag: "derived" },
  { source: "keep",   run_id: "keep_456",   confidence: 0.91, flag: "derived" },
  { source: "igpsport", run_id: "igpsport_789",  confidence: 0.85, flag: "derived" },
  { source: "garmin_cn", run_id: "garmin_cn_999", confidence: 0.36, flag: "contained" },
]
```

### Group consolidation（post-processing）

所有 pair-wise matches 完成后，通过 **union-find** 合并分组：

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

找出所有 5-source、4-source 组，无需显式 N 维比较。

### Group-level actions

- **dedup_groups + dedup_group_members write**: 给所有成员分配同一 group ID
- **Field-level election**: 在 export 时跨所有组员运行
- **Canonical selection**（可视化用）: export 时选最高分源或 composite
- **Duplicate_info enrichment**（可选）: 把缺失的 cross-refs 回填进 `activities.duplicate_info`（保留在 activities 表以兼容 SVG hover labels）

### Edge cases

- **False positive chain**: A matches B (0.85), B matches C (0.85), but A does NOT match C (0.05)。Union-find 把三者并为一组。**Mitigation for high stakes**: 组内全对需超过 `derived` 最低阈值。对 `similar`/`partial`，链式分组可接受。

---

## 7. 执行路线图

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

### Key Decisions

| Decision | Value |
|---|---|
| Time format | ISO 8601 with zone: start_date UTC Z, start_date_local +08:00 |
| AH run_id | 7+4: MD5[source+start+end][0,7] + MD5[source+creation+start+end][0,4] |
| dedup groups | Separate dedup_groups + dedup_group_members tables (not activities.dedup_group_id) |
| Field election | Computed at export time, not persisted (50ms for ~500 groups) |
| external_id scope | AH↔Strava only (HKExternalUUID bridge, 27 pairs) |
| Garmin Intl/CN time | Defensive .utc only, no functional change needed |

---

## 8. 迁移路径与验证

### Migration Path

**Phase 1: P0（基础设施）**
1. Update `parse_time` in DedupService (already compatible, add defensive `.utc`)
2. Change `effective_duration` to `[moving, elapsed].max`
3. Replace `group_by date` with sliding ±1 day window
4. Add hierarchical sport_category groups
5. Deploy, run on existing data, verify no regressions

**Phase 2: P1（external_id）**
1. Add `external_id` column via DB migration
2. Update Strava adapter: extract `detail["external_id"]`
3. Update Apple Health adapter: extract `meta["HKExternalUUID"]`
4. Update DedupMatcher: exact match channel
5. Run AH↔Strava comparison analysis script
6. Define merge strategy based on analysis results

**Phase 3: P2（GPS 轨迹）**
1. Add Douglas-Peucker to Trajectory
2. Add DTW similarity to Trajectory
3. Add Hausdorff distance to Trajectory
4. Enhance existing overlap detection with continuous score
5. Add containment_relation method (equivalent/contained/partial/cross/disjoint)
6. Integrate composite scoring into Matcher
7. Update flag classification

**Phase 4: P3（生产化）**
1. Add `workouts dedup` CLI (support `--incremental`, `--export-composites`, `--status`)
2. Add detailed logging + JSON output (`data/dedup/YYYY-MM-DDTHHMMSSZ.json`)
3. Integrate Runner auto-trigger
4. Create `dedup_groups` + `dedup_group_members` tables via migration
5. Implement incremental dedup: skip records already in `dedup_group_members`
6. Implement field-level election (view-only, computed at export time)
7. Implement union-find group consolidation
8. Export JSON/SVG/Stats: integrate composite election into output pipeline

### Verification

| Test | What | How |
|---|---|---|
| P0 regression | Same results on existing data | Run DedupService before/after, compare match counts |
| P1 precision | external_id matches always correct | Verify 27 pairs match exactly with confidence=1.0 |
| P2 sensitivity | Trajectory matching catches edge cases | Known 5-source group on 2026-06-18 must be detected |
| P3 incremental | `dedup_group_members` filters matched records | Run twice, second run should compare only new records |
| Field election | Composite record computed at export time | Each field should have a value from the best source, verified via `workouts dedup --export-composites` |
| N>2 consolidation | Union-find groups correctly | Manual verification on known day with multiple duplicates |
| Cache independence | dedup_composites not persisted | Verify GH Cache digest unchanged after DedupService re-run with no new data |

**Acceptance criteria**

1. All 19 previously lost AH records are now imported and matched
2. 27 AH↔Strava pairs detected with confidence=1.0
3. 5-source group on 2026-06-18 consolidated into one dedup_group
4. Field-level composite (computed at export) contains temperature (from AH) + power (from Strava) + polyline (from AH)
5. Second DedupService run processes only records NOT in `dedup_group_members`
6. Export JSON includes composite records; deduped groups have `dedup_group` + `member_sources` fields

---

## 9. 量化分析

> 原 `scripts/dedup-quantify.rb` 独立分析脚本已删除，其报告逻辑摘要保留于此。脚本功能：连接 DB、过滤 `distance > 100`，产出三节跨源重复报告。运行方式：`--db PATH`（默认 `$GIT_FIT_DATABASE_PATH` 或 `data/db/workouts.db`）。

### 报告结构（脚本实际实现）

**1. OVERLAP MATRIX** — 按同日期分组，跨源两两比较，满足以下条件的计为 precision duplicate pair：

- `start_date` 差 < 5s
- distance 相对差 < 1%（`|d_a - d_b| / max(d_a, d_b)`）

对角线上为该源总数，非对角线为源对间重复对数量。

**2. FIELD COMPLETENESS BY SOURCE** — 各源每字段非空占比（%）：`average_heartrate` / `average_power` / `average_cadence` / `average_temperature` / `elevation_gain`。用于识别各源数据质量缺口（哪个源缺 HR / 功率 / 踏频 / 温度）。

**3. DEDUP GROUP STATS** — 若 DB 存在 `dedup_groups` + `dedup_group_members` 表：组数、成员数、平均每组成员数、flag 分布（derived/duplicate/similar/contained/partial/cross）。无表时报 `dedup_groups table not found - run migration 008`。

### 设计维度（原规划，未全部实现）

| Dimension | Method |
|---|---|
| **AH/Strava/Keep precision duplicates** | time<5s + dist<1% + duration<5% → precision match（已实现前两项） |
| **Garmin multi-device** (Edge+Fenix) | GPS trajectory containment/partial/cross vs Keep + AH |
| **Keep auto-generated** (workout type) | dist≤1km + duration<10min + zero GPS |
| **Cross-platform GPX/FIT/TCX uploads** | Same distance + duration + device + trail similarity |
| **DedupService validation** | Compare heuristic match results to known ground truth |

---

## 10. 归档数据获取（调研方法）

```bash
# 将所有源存档 checkout 到临时目录
for src in garmin keep strava igpsport xoss xingzhe garmin_cn; do
  git checkout origin/_/_/$src -- data/std/$src/ data/raw/$src/
done

# DB 快照
git checkout origin/_/db/workouts-db -- data/db/workouts.db
cp data/db/workouts.db data/workouts.archive.db  # 备份后恢复当前 DB
```

各分支 std 目录已包含标准化 GPS 点阵，可直接用于 Trajectory 对比分析。
