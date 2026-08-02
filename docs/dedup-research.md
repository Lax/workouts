# Cross-Source Dedup — Data Quality & Scenarios Research

## 1. Overview

Workouts 系统目前聚合 8 个源的 2,103 条活动。同一条真实运动可能从多个渠道录入（Strava → Apple Health + Strava sync、Garmin 码表 + Garmin 手表 + Garmin Connect → Apple Health），导致重复记录。

现有去重体系：

| 层级 | 机制 | 位置 | 覆盖 |
|---|---|---|---|
| L1 | `run_id` UNIQUE（同源内） | 各 adapter `build_attrs` | 同源去重 |
| L2 | Dedup::Service（跨源滑动窗口） | `lib/workouts/dedup/service.rb` | 全源两两匹配 |
| L3 | Dedup::Matcher（置信度） | `lib/workouts/dedup/matcher.rb` | 时间/距离/时长/类型 |
| L4 | Dedup::Trajectory（轨迹重叠） | `lib/workouts/dedup/trajectory.rb` | GPS 采样点 30% 在 50m 内 |

本文档基于 `workouts import --source apple_health` 导入 927/908 条的数据分析，分类描述了 9 种去重场景及其缺口。

> **设计文档:** 去重重构方案详见 [`docs/dedup-redesign.md`](dedup-redesign.md)（P0-P3 四阶段、字段级选举、dedup_groups 独立表）。时间格式统一方案详见 [`docs/time-format-iso8601.md`](time-format-iso8601.md)。外部标识符方案详见 [`docs/external-id.md`](external-id.md)。

---

## 2. 数据源概览（线上，liulantao.com/workouts）

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

### 归档分支数据量

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

### Archive 分支数据字段可用性（per std point）

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

## 3. 场景 1：精准重复

同一条真实活动，在不同平台之间多次同步，产生少量数据误差和非关键数据变化。

### 触发条件

- 同一设备/源的活动通过 HealthKit 被 Apple Health 捕获
- 同一条 Strava 活动既被 Strava sync adapter 拉取，又被 Apple Health 从 Strava 同步
- Garmin Connect 既被 Garmin sync adapter 拉取，又通过 HealthKit 写入 Apple Health

### 典型案例：Apple Health(Strava) vs Strava sync

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

### 典型案例：Apple Health(Connect) vs Garmin sync

详见场景 2 中 `b4a147c6548` 组分析。

### 标识线索

- sourceName = "Strava" 且 MetadataEntry 含 `HKExternalUUID`
- sourceName = "Connect" 或 "Garmin Connect"
- start_date + distance + duration 三元组极高置信度匹配

---

## 4. 场景 2：双设备同时记录

码表和手表同时记录一次骑行，起止时间基本一致，轨迹路线高度重叠，但码表和手表 GPS 芯片精度不同导致统计值有微小差异。

### 触发条件

- Garmin Edge（码表）和 Garmin Fenix/Forerunner（手表）同时记录同一次骑行
- Apple Watch + iPhone 同时记录一次户外步行
- 码表开启、手机端 Keep/Strava app 也同时记录

### 待验证的 Garmin 设备双记录案例

基于 `_/_/garmin` 存档分支的 FIT 数据可以验证：

```ruby
# 查询策略：找同一天 start_date 差距 < 60s 的两条 garmin 活动
# 码表通常有 power/cadence 字段，手表通常有心率但无功率
# 对比轨迹重叠率
```

**数据路径**：`git checkout origin/_/_/garmin -- data/std/garmin/*.json data/raw/garmin/*.fit`

### Matcher 预期表现

| 因子 | 码表 vs 手表 | 置信度 |
|---|---|---|
| 时间相近度 35% | start 差 2-10s | ~0.98 |
| 距离相近度 35% | distance 差 1-3% | ~0.90 |
| 时长相近度 15% | moving_time 差 0-5% | ~0.95 |
| 运动类型 15% | 都是 ride | 1.0 |
| **总分** | | **~0.94** |

轨迹重叠率预计 > 90%（`Trajectory` 阈值 30% 远低于此），flag 应为 `derived`。

### 当前缺口

- 无"设备类型"字段区分码表 vs 手表（FIT 的 `manufacturer` / `product` 字段未被解析到 DB）
- 无法判断哪条记录应该保留、哪条该标记为 derived
- 字段归并策略不明确：手表的心率（通常更准）vs 码表的功率/速度

---

## 5. 场景 3：部分重叠（包含/交叉）

### 5a 包含关系

一次活动的时间窗口完全包含另一次活动。

**示例**：
- 长跑 2h（Garmin），其中 11min 步行段被 Apple Watch 单独记录为 Walking
- 骑车到健身房 → 室内训练 → 骑车回家，Apple Health 可能记成三段独立活动，Garmin 记成一段

**数据验证**：检查 2026-06-25 附近多条短距 Cycling（0.2~4.7km，时间密集）是否存在时间包含关系。

**Matcher 问题**：
- 步行（walk）vs 长跑（run）：`cat_score = -0.67`，即使距离/时间匹配也会大幅降分
- `distance_score` 阈值 15%：步行距离 ~500m，跑步距离 ~15,000m → `diff/max = 96%` → 返回 nil 过滤

**Dedup::Trajectory 问题**：
- 步行段 GPS 100% 在跑步轨迹 50m 范围内 → 触发 `duplicate` flag
- 但反过来，跑步段的 GPS 可能只有 < 10% 在步行轨迹内（因为大部分轨迹不重叠）
- 当前 trajectory 检查只做"采样点 A 是否在 B 轨迹 50m 内"，不做双向判定

### 5b 交叉关系

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

---

## 6. 场景 4：外部 ID 精确匹配

数据中包含其它源的数据 ID 标识。

### 已知外部 ID

| 源 | 外部 ID 字段 | 示例值 | 出现范围 |
|---|---|---|---|
| Strava（Apple Health） | `HKExternalUUID`（MetadataEntry） | `strava://activities/3056096737` | ~12 条 AH(Strava) |
| iGPSPORT | 可能通过第三方关联（待查） | — | 未知 |
| XOSS | run_id 前缀 `xoss_`；FIT 中可能有原始 ID | — | 未知 |

### 未发现外部 ID 的源

- Keep：MetadataEntry 中无外部 UUID
- Connect（Garmin）：无外部 UUID
- XingZhe：无

### 建议的 external_id 实施方案

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

---

## 7. 场景 5a：同路线不同运动类型

同一 GPS 轨迹，不同平台/用户标记为不同运动类型。

### 常见映射差异

| 真实运动 | Garmin | Strava | Apple Health | Keep |
|---|---|---|---|---|
| 徒步登山 | hiking | hike | hiking / walking | outdoorWalking |
| 越野跑 | trail_running | trailrun / run | running | outdoorRunning |
| 城市骑行 | cycling / road_biking | ride | cycling | cycling / outdoorCycling |
| 滑雪 | cross_country_skiing | nordicski | skiing | — |
| 室内骑行 | indoor_cycling | virtualride | cycling | cycling |

### 当前 Matcher 的表现

```ruby
cat_score = a[:sport_category] == b[:sport_category] ? 1.0 : -0.67
```

不同 category → `-0.67 × 0.15 = -0.1`，总分被拖低 0.1。若其他因子匹配度 > 0.88，仍可能达到 `derived` 阈值 0.85。

但 `-0.67` 是硬编码惩罚——hike↔walk 的差异远小于 run↔swim 的差异，应当有层次。

### 建议

引入 SportMapper 的 Levenshtein 距离或人工分类树：

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

---

## 8. 场景 5b：断线分段记录

设备在记录过程中断连或重启，导致一段连续运动被切割为多条记录。

### 触发条件

- Garmin 手表电池耗尽 → 20km 处自动保存前半段 FIT → 充电后重新记录后半段
- 蓝牙断连 → Apple Watch 和 iPhone 各自记录片段
- 运动中途暂停时间超过设备自动保存阈值

### 识别特征

- 两活动 `start_date` / `end_date` **连续或接近衔接**（差 < 30s）
- 轨迹终点与起点 GPS 坐标**在 50m 范围内**（衔接点可辨认）
- 两活动的 `sport_category`、`source` 相同
- 两活动的 `device_name` 相同（FIT 中 `product` / `manufacturer` 字段）

### 合并策略

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

### 数据验证

**无现成数据**，当前记录中没有明显断线的例子。需要关注 Garmin 长距离活动（>50km）的起止时间衔接。

---

## 9. 场景 5c：手动创建的活动

用户在平台 A 手动创建一条活动，内容和平台 B 自动记录的完全相同。

### 示例

- 用户忘记戴手表，在 Strava 网页手动输入 10km 跑步
- Garmin Connect 上手动合并两段 FIT 为一条活动
- 用户导出 GPX 后重新导入到另一个平台（通过 `import gpx`）

### 识别难度

- 无外部 ID
- 时间、距离、类型完全一致
- GPS 可能缺失（手动录入不提供）
- Matcher 可以匹配到（distance + time 高度一致），但阈值选择困难

### 数据验证

`workouts import --source gpx` 导入的文件会生成 `run_id = gpx_{sha256[0..12]}`。如果这些 GPX 原本就是从 Garmin 导出的，`distance`、`start_date` 可能一致，但无可靠的外部 ID 确认。

---

## 10. 场景 5d：服务端去重后残留

源平台自身做了去重，但重复数据通过不同同步路径进入 Workouts。

### 示例

- Strava 合并了两条重复 Garmin 活动（内部去重），但 Apple Health 在 Strava 去重前已经同步过
- Garmin 端去重后删除了一条 FIT，但 Apple Health 的 Connect 同步仍在

### 识别特征

- 同 `external_id` 匹配（Strava 场景）
- 非同源时：时间+距离匹配，但 metadata 差异提示不同同步批次

---

## 11. 场景 5e：每日重复训练

不同日期的相同训练计划（如同路线 5km 跑步、同路线通勤骑行），数据极其相似但不是同一活动。

### 这是 Matcher 的 false positive 高风险场景

| 字段 | Day 1 | Day 2 | 差异 |
|---|---|---|---|
| start | 07:00 | 07:00 | 差 24h（超出窗口 → 不比较） |
| route | 同路线 | 同路线 | GPS 几乎重叠 |
| distance | 5.02 km | 5.08 km | 1.2% |
| moving_time | 25:30 | 26:10 | 2.6% |

### 现有防御

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

## 12. Dedup 字段缺口

### 当前 DB schema 缺失的字段

| 字段 | 用途 | 来源 |
|---|---|---|
| `device_name` / `product` | 辨别码表 vs 手表 | FIT 的 `manufacturer` + `product` mesg |
| `external_id` | 跨源精确匹配 | MetadataEntry / adapter run_id |
| `start_date_tz` | 本地时区 | Apple Health `HKTimeZone` / Garmin `time_zone_offset` |

### Matcher 结构缺失

- **sport_category 层次化比较**：替代当前二值比较
- **轨迹拼接判定**：端点连续 + 同设备 → 可合并
- **时间间隔惩罚**：跨天/跨小时的轨迹重叠应该降级

---

## 13. 归档分支数据获取

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

---

## 14. 下一步建议

根据 `docs/apple-health-data-research.md` 和本文档的调研：

| 优先级 | 任务 | 涉及文件 |
|---|---|---|
| P0 | `external_id` 列 + Strava UUID 匹配 | `lib/workouts/dedup/matcher.rb`, `lib/workouts/import/apple_health.rb`, `lib/workouts/sync/base.rb` |
| P1 | `duration_score` 切 `elapsed_time` | `lib/workouts/dedup/matcher.rb:17` |
| P1 | SportMapper 类型分组（同类降惩罚） | `lib/workouts/sport_mapper.rb`, `lib/workouts/dedup/matcher.rb` |
| P2 | `generate_run_id` 加 `workoutActivityType` | `lib/workouts/import/apple_health.rb:520` |
| P2 | Trajectory 双向判定 + 部分重叠 flag | `lib/workouts/dedup/trajectory.rb` |
| P3 | 双设备 Garmin FIT 归档数据交叉验证 | `_/_/garmin` 数据 |
| P3 | Import call 返回真实写入数 | `lib/workouts/import/apple_health.rb:56` |
