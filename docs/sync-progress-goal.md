# Sync Progress Display — Goal

## 第一性原理

### 核心命题

CLI `workouts sync` 执行期间，用户需要回答一个基本问题：

**现在在干什么？**

当前回答（现状）：

```
Garmin: 五 (3/15)
```

回答了"第几个"。但缺失：

| 问题 | 现状 | 目标 |
|---|---|---|
| 同步哪个活动？ | ❌ | 活动名 |
| 什么类型？ | ❌ | run/ride/hike |
| 多远？ | ❌ | 5.2km |
| 哪天？ | ❌ | 01-15 / 2024-01-15 |

### 设计原则

1. **实时反馈** — 每处理一条活动，更新同一行（`\r` 覆写），不滚动
2. **自适应频率** — 保留现有 `show_progress?` 机制，不每条都刷
3. **降级友好** — 某字段缺失时省略对应段，不崩溃
4. **源无关** — 所有 7 个适配器统一格式，但各源数据获取方式独立
5. **向后兼容** — 不改变 `report_progress` 现有调用方行为

---

## 功能定义

### 输出格式

```
{source}: {tally} ({count}/{total}) {date} | {type} | {dist_km}km | {name}
```

示例：

```
Garmin: 三 (3/15) 01-15 | run | 5.2km | Morning Run
Strava: 五 (5) 03-20 | ride | 42.1km | Century Ride
Keep: 一 (1/8) 06-01 | hike | 12.0km | Mountain Trail
```

### 字段规则

| 字段 | 来源 | 缺失时 |
|---|---|---|
| `{date}` | `start_date` → 格式化，当年 `MM-DD`，非当年 `YYYY-MM-DD` | 省略该段 |
| `{type}` | 标准化后的 `sport_category`（run/ride/hike/walk/swim/ski/workout/other） | 省略该段 |
| `{dist_km}` | `distance` / 1000，`%.1f` 格式化。distance 为 nil/0 时省略 | 省略该段和 `km` |
| `{name}` | 平台原始名称，字符级截断 30 | 回退 `"{source} Activity"` |

### 截断规则

- `{name}` 超过 30 **字符** 截断加 `…`。使用 `String#chars` 做字符级截断，非字节级
- 整行长度：源(8) + tally(4) + count(3) + total(3) + 分隔符(9) + date(10) + type(8) + dist(6) + name(30) ≈ 81

---

## 边界与反模式

### 不做

1. **不存进度到 DB** — 纯 CLI 输出，不持久化
2. **不改 CI 日志格式** — GitHub Actions log 自然显示此输出
3. **不处理非 sync 命令** — export/auth/db 等不受影响
4. **不添加 emoji** — 纯文本，保持终端兼容
5. **不改变 `\r` 覆写行为** — 保留单行进度条风格，不切到逐行日志
6. **不引入国际化** — 保持中文 tally + 英文 info 的混合现状

### 边界条件

| 场景 | 行为 |
|---|---|
| total 未知（无预计数） | 不显示 `/{total}`，仅 `(5)` |
| name 为空 | 回退 `"Garmin Activity"`（各源对应回退） |
| distance 为 nil/0 | 省略 `{dist_km}km` 段 |
| date 解析失败 | 省略 `{date}` 段 |
| name 超 30 字符 | 字符级截断加 `…` |
| sync 0 条 | CLI 仍输出 `warn: 0 activities`，不变 |
| total=所有待处理条目，synced=已处理完成 | missing_raw 重建 raw 也计入 synced |

---

## 对抗审查决议 — 全部 P0

以下 7 项对抗审查发现均已采纳为 P0。

| # | 问题 | 决议 |
|---|---|---|
| 1 | Keep `upsert_from_raw` (L125) 路径缺 `report_progress` 调用 | 修复：该路径也需调用 `report_progress`，`synced` 累计 |
| 2 | Keep 的 `sport` 是 URL 段（running/hiking/cycling），非 `sport_category` | 在 `sync_sport_type` 中预先映射 `KEEP_TYPES → TYPE_MAP`，从返回 attrs 取 `sport_category` |
| 3 | name 多字节字符截断 | 使用 `String#chars` 字符级截断 |
| 4 | `MM-DD` 跨年歧义 | 当年活动 `MM-DD`，非当年 `YYYY-MM-DD`（按当前年份判断） |
| 5 | CLI 清除行宽度 60→120 不够 | 固定 150 字符清除 |
| 6 | distance 为 0 时不应显示 `0.0km` | 确保 `nil.`? 和 `0.0` 均省略 |
| 7 | 进度语义：`total`=所有待处理条目数，`synced`=已处理完成数（含 missing_raw 重建） | missing_raw 重建 raw 时也要 `synced += 1` |

---

## 验收标准

### 1. 格式正确

每个适配器 progress 行格式为：

```
{source}: {tally} ({count}[/{total}]) [{date} | {type} | {dist_km}km | {name}]
```

方括号内为条件段。至少显示 count。

### 2. 所有适配器生效

| 适配器 | 文件 | progress 行号 |
|---|---|---|
| Garmin | `garmin_base.rb:362` | 有 date/type/dist/name |
| Strava | `strava.rb:63` | 有 date/type/dist/name |
| Keep | `keep.rb:130` | 有 date/type/dist/name（需改返回类型 + 修复 upsert_from_raw 路径） |
| iGPSPORT | `igpsport.rb:63` | 有 date/type/dist/name |
| XOSS | `xoss.rb:89` | 有 date/type/dist/name |
| XingZhe | `xingzhe.rb:108` | 有 date/type/dist/name |

### 3. 向后兼容

- 不修改 `report_progress(count)`（单参数）调用
- 不修改 `report_progress(count, total)`（双参数）调用
- 现有 `show_progress?` 逻辑不变
- `Tally` 中文数字不变

### 4. CLI 清理行长度

`cli/sync.rb:23` 的空格清除宽度从 60 → 150

### 5. Keep 无回归

- `sync_single_run_with_raw` 返回 attrs hash 而非 `true`，`nil` 仍表示失败
- `upsert_from_raw` 返回 attrs hash 而非 `true`，`nil` 仍表示失败
- 调用方 `if method()` 仍正确判别成功/失败
- `upsert_from_raw` 路径也计入 `synced` 并调用 `report_progress`

### 6. 日期无歧义

- 同一年的活动显示 `MM-DD`（如 `01-15`）
- 往年的活动显示 `YYYY-MM-DD`（如 `2023-06-01`）

### 7. 多字节截断正确

- `"晨跑-奥森公园-10km恢复跑"`（12 字符）完整显示
- `"晨跑-奥森公园-10km恢复跑-额外信息"`（16 字符）截断为 `"晨跑-奥森公园-10km恢复跑-额外信…"`

---

## 分级目标

| 层级 | 内容 | 优先级 |
|---|---|---|
| P0 | 全部 7 项对抗审查修复 + 格式正确 + 所有适配器有 info | 必须 |
