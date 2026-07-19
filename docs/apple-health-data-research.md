# Apple Health Import — Data Quality & Cross-Source Dedup Research

## 背景

`workouts import --source apple_health` 从 `data/import/apple_health/export.zip` 解析 Apple Health 导出数据，写入 DB。CI 显示导入 927 条，但 DB 仅 908 条。后续跨源对比发现 Garmin 同步数据中存在与 Apple Health 完全重合的活动。

本文档记录数据分析中的全部发现。

---

## 1. run_id Hash 碰撞导致 19 条丢失

### 算法

`lib/workouts/import/apple_health.rb:520`：

```ruby
def generate_run_id(source_name, start_date, end_date)
  s = normalize_date(start_date)
  e = normalize_date(end_date)
  Digest::MD5.hexdigest("#{source_name}|#{s}|#{e}")[0, 11]
end
```

使用 sourceName + startDate + endDate 的三元组计算 MD5 取前 11 hex（44 bits）。

### 碰撞规模

927 条原始记录中：

| 指标 | 数值 |
|---|---|
| 唯一 run_id | 908 |
| 碰撞组数 | 16 |
| 涉及记录数 | 35 |
| 被覆盖丢失 | 19 |
| 碰撞概率 | 19/927 = 2.05% |

16 组碰撞明细：

| Hash | 记录数 | Source | 类型 |
|---|---|---|---|
| `0cbbeeee16a` | 4 | Strava | 逐字节完全相同 |
| `b94e196dc95` | 3 | Keep | creationDate 差 3s/6min |
| `0bcbdd107a8` | 2 | Keep | creationDate 差 ~47min |
| `0bc6553ffc8` | 2 | Keep | creationDate 差 18s |
| `e9293f3373c` | 2 | Keep | creationDate 跨天 |
| `cd56afd6c06` | 2 | Keep | creationDate 差 ~16min |
| `e2bb2f836fe` | 2 | Keep Cycling | creationDate 差 ~3.5min |
| `5f1522ae892` | 2 | Keep | creationDate 差 ~5min |
| `8b81b3d39bf` | 2 | Strava | creationDate 差 1s |
| `6b3933c1f13` | 2 | Strava | creationDate 差 1s |
| `880b8f64b91` | 2 | Strava | IDENTICAL |
| `a00e7b93a36` | 2 | Strava | IDENTICAL |
| `b4a147c6548` | 2 | Connect | creationDate 差 ~1min + metadata 排序不同 |
| `70dfad36d77` | 2 | Connect | creationDate + metadata 排序 |
| `7a32373e11d` | 2 | Connect | creationDate + metadata 排序 |
| `f17430eeeec` | 2 | Connect | creationDate 差 ~12h |

### 根因

`upsert_activity`（`lib/workouts/sync/base.rb:141`）先查 `existing` 再决定 `insert` 或 `update`：

```ruby
existing = @db[:activities].where(run_id: attrs["run_id"]).first
if existing
  # UPDATE — 覆盖旧数据
else
  # INSERT
end
```

hash 碰撞时：第一条 insert，后续 update 覆盖，process_one 全部返回成功（无异常），call 返回 `processed=927`。DB 实为 908 条。

### 是否数据丢失

**否。** 16 组碰撞经逐条 XML diff 验证，全部是同一活动的多次重复记录（Strava 导出重复、Keep 多次同步、Connect 不同批次同步）。`update` 恰好正确去重。

---

## 2. Strava HKExternalUUID — 跨源精确去重入口

### 数据特征

Apple Health 中 Strava 源的活动包含唯一跨源标识：

```xml
<MetadataEntry key="HKExternalUUID" value="strava://activities/3056096737"/>
```

### 当前状态

- Apple Health import：`build_attrs` 接收 `meta`（`extract_metadata` 解析所有 `<MetadataEntry>`），但当前未提取或保存 `HKExternalUUID`
- Strava sync adapter：run_id 格式为 `strava_{activity_id}`（如 `strava_3056096737`）
- 两者之间**无关联字段**

### Strava 碰撞组全部可匹配

| Hash | 外部 UUID | Strava activity |
|---|---|---|
| `0cbbeeee16a` | `strava://activities/3056096737` | `strava_3056096737` |
| `8b81b3d39bf` | `strava://activities/2989698770` | `strava_2989698770` |
| `6b3933c1f13` | `strava://activities/2993131091` | `strava_2993131091` |
| `880b8f64b91` | `strava://activities/3022320879` | `strava_3022320879` |
| `a00e7b93a36` | `strava://activities/3092737064` | `strava_3092737064` |

### 局限性

仅 Strava 源带 `HKExternalUUID`。Keep、Connect（Garmin）无类似外部 ID。

---

## 3. Connect(Garmin) ↔ Garmin 同步 — 同活动双源

### 证据

以 `b4a147c6548` 碰撞组为例：

**Apple Health（Connect 源）：**

```
run_id:   apple_health_37f07f05113
distance: 458.4 m
calories: 23 kcal
speed:    2.34 m/s
time:     196s (raw duration = elapsed)
start:    2026-06-19 15:58:01 +0800
GPS:      无
HR:       无
```

**Garmin sync（`_/_/garmin` archive branch）：**

```
run_id:   garmin_23303174649
distance: 458.4 m   ← 精确一致
calories: 23 kcal   ← 精确一致
speed:    2.338 m/s ← 一致
time:     168s (moving, 已滤暂停)
start:    2026-06-19 07:58:01 UTC = 15:58:01 +0800
GPS:      53 点, pos=(36.7578,114.9245) ~ (36.7574,114.9247), 巷道短途
HR:       106 avg / 115 max
temp:     30°C
```

### 数据互补关系

| 字段 | Apple Health(Connect) | Garmin sync | 建议合并方向 |
|---|---|---|---|
| summary_polyline | null | ✅ 53 点 polyline | 从 Garmin 补齐 |
| average_heartrate | null | 106 bpm | 从 Garmin 补齐 |
| max_heartrate | null | 115 bpm | 从 Garmin 补齐 |
| average_temperature | null | 30°C | 从 Garmin 补齐 |
| moving_time | 196s（原始时长） | 168s（过滤暂停） | 保留 Garmin 值 |
| calories | 23 kcal | 23 kcal | 一致，任取其 |

### 触发机制

Garmin Connect 通过 Apple Health 的 HealthKit 同步写回摘要数据（无 GPS、无 HR detail）。Garmin 官方 sync adapter 通过 Garmin API 获取完整 FIT。两条路径独立。

---

## 4. moving_time vs elapsed_time — 跨源时长不可比

### 当前 Matcher 实现

`lib/workouts/dedup/matcher.rb`：

| 权重 | 字段 | 说明 |
|---|---|---|
| 时间窗口（35%） | `elapsed_time` | 取较大值 + 300s 缓冲 |
| 时长相似度（15%） | `moving_time` | 差 > 较大值的 15% 返回 0 |

### 问题

Apple Health 导入的 `moving_time` 来自 XML `duration` 字段：

```ruby
# lib/workouts/import/apple_health.rb
moving_time = parse_duration(duration, duration_unit)  # 原始时长，无暂停过滤
```

Garmin/Strava sync 的 `moving_time` 经过暂停过滤（Garmin 自动暂停、Strava 移动检测）。

对比数据：

| 活动 | AH moving_time | Garmin moving_time | AH elapsed_time | Garmin elapsed_time |
|---|---|---|---|---|
| 2026-06-19 短骑 | 196s | 168s | 196s | ~196s |
| 2019-04-13 Keep 跑 | 668min (40080s) | N/A | 668min | N/A |

同源（Apple Health）中 `moving_time` = `elapsed_time`（duration=endDate-startDate）。Garmin 中两者可能差异大（含暂停）。

### 影响

当前 `duration_score` 用 `moving_time` 做跨源比较，会导致：

- AH 对 Garmin：系统性偏差（AH moving_time 总是 ≥ Garmin moving_time）
- 差 14.3%（196 vs 168）已接近 15% 阈值，足够长暂停就会误判

---

## 5. Connect 源 Metadata 排序不稳定

### 证据

`b4a147c6548` 组两记录逐字段相同，仅 XML 中 `<MetadataEntry>` 的出现顺序不同：

```
Record 1（creation=22:37:12）:
  <MetadataEntry key="HKMaximumSpeed" value="3.695"/>
  <MetadataEntry key="HKElevationAscended" value="0"/>

Record 2（creation=22:36:13）:
  <MetadataEntry key="HKElevationAscended" value="0"/>    ← 交换
  <MetadataEntry key="HKMaximumSpeed" value="3.695"/>
```

另外两次 Connect 同步 (`70dfad36d77` 和 `7a32373e11d`) 共享同一对 creation 时间戳（`22:50:54` / `16:46:34`），说明同一批次生成时元数据顺序随机。

影响：不影响解析（`extract_statistics` 用 type/sum/unit 而非位置），但 hash-based 比较会视为不同。

---

## 6. 数据质量缺口

| 问题 | 影响范围 | 说明 |
|---|---|---|
| 无 GPS 轨迹 | 71% (645/908) | Connect/Keep 源只同步摘要，不带 workout route GPX |
| 无本地时区 | 78.4% (712/908) | `start_date_local` 为 null，缺少 `HKTimeZone` 元数据 |
| 无心率数据 | ~95% | 仅活动时间匹配到心率样本的才有值 |
| 跨源重复 | ~50 条 | Connect/Strava/Keep 数据与对应 adapter 重复 |

### GPS 缺失原因

Apple Health 中仅 `HKWorkoutRoute`（单独 GPX 文件）包含轨迹。Connect/Keep 源不生成 Route，只有 Strava 源才有。导入逻辑通过 `match_routes_by_time` 关联 Route 和 Workout，时间窗口 5 分钟。

---

## 7. 后续深入方向

### 7.1 `external_id` 列 + 跨源去重改造

**范围**：apple_health(Strava) ↔ strava sync

**步骤**：
1. DB migration：`activities` 加 `external_id TEXT`
2. Apple Health import：`build_attrs` 从 `meta["HKExternalUUID"]` 提取
3. Strava adapter 写入 `external_id` 为 `strava://activities/{id}`
4. Dedup::Matcher 增加精确匹配：`external_id` 相同 → confidence=1.0, flag=derived
5. 导出时归并：Garmin/Strava 的 GPS+HR 补齐 apple_health 缺失字段

### 7.2 Dedup::Matcher 时长字段切换

`duration_score` 改用 `elapsed_time`（或 `[moving_time, elapsed_time].max`），消除暂停过滤造成的跨源差异。

### 7.3 run_id hash 算法改进

`generate_run_id` 加入 `workoutActivityType` 作为区分因子，降低同名源+同时段活动的碰撞概率。但同时会降低对真正重复活动的去重能力——需评估是否值得。

### 7.4 Apple Health 与 Garmin 存档数据合并

`_/_/garmin` archive branch 包含 38 个活动的完整 GPS/HR/temperature 数据。评估后可以选择：
- Dedup 时用 Garmin 数据补齐 apple_health 的 Connect 源缺失字段
- 或者直接用 Garmin 数据替代 apple_health 的 Connect 源记录

### 7.5 Import 报告诚实化

当前 `call` 返回 `processed=927` 但实际写入 908。可以在返回前做 `@db[:activities].where(source:"apple_health").count` 得到真实值。涉及 `lib/workouts/import/apple_health.rb:41~56`。

---

## 附录：导出数据概况

### 线上活动构成（liulantao.com/workouts/activities.json）

| 源 | 数量 | 占比 |
|---|---|---|
| apple_health | 908 | 43.2% |
| keep | 876 | 41.7% |
| strava | 100 | 4.8% |
| igpsport | 85 | 4.0% |
| garmin | 55 | 2.6% |
| xoss | 44 | 2.1% |
| xingzhe | 34 | 1.6% |
| garmin_cn | 1 | 0.0% |

### Apple Health 类型分布

| category | 数量 | 原始 HK 类型 |
|---|---|---|
| run | 362 | HKWorkoutActivityTypeRunning |
| walk | 248 | HKWorkoutActivityTypeWalking |
| ride | 241 | HKWorkoutActivityTypeCycling |
| workout | 57 | HKWorkoutActivityTypeTraditionalStrengthTraining |

### 日期范围

最早：2015-08-06，最晚：2026-07-13，覆盖 ~11 年。

### Garmin 存档分支

- 分支：`_/_/garmin`
- std 文件数：38
- 可用字段 per point：`positionLat`, `positionLong`, `altitude`, `heartRate`, `speed`, `timestamp`, `distance`, `temperature`
