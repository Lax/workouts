# CONTEXT.md 更新计划

## 改动清单

| 位置 | 操作 | 内容 |
|---|---|---|
| L55 | 改 | `GH Cache` → `每源独立 GH Cache` |
| L77 后 | 新增 | run_id/目录映射表 |
| L130-132 | 新增 | Garmin 拆分说明 |
| L252-263 | 替换 | sync job 步骤更新 |
| L330 | 替换 | combined cache → per-source + 路径示例 |

---

## 1. L55 — 架构图微调

```diff
- │           (原始 GPS 点阵备份, GH Cache)
+ │           (原始 GPS 点阵备份, 每源独立 GH Cache)
```

## 2. L77 后 — 新增数据源标识表

```markdown
### 数据源标识

| 适配器 | `source_prefix` | L1 `raw_dir` | L2 `std_dir` |
|---|---|---|---|
| Keep | `keep` | `data/raw/keep/` | `data/std/keep/` |
| iGPSPORT | `igpsport` | `data/raw/igpsport/` | `data/std/igpsport/` |
| XOSS | `xoss` | `data/raw/xoss/` | `data/std/xoss/` |
| XingZhe | `xingzhe` | `data/raw/xingzhe/` | `data/std/xingzhe/` |
| Garmin Intl | `garmin` | `data/raw/garmin/` | `data/std/garmin/` |
| Garmin CN | `garmin_cn` | `data/raw/garmin_cn/` | `data/std/garmin_cn/` |
| Strava | `strava` | `data/raw/strava/` | `data/std/strava/` |

`run_id` 格式为 `{source_prefix}_{平台ID}`（如 `garmin_12345`、`strava_98765`）。
```

## 3. L130-132 — Garmin OAuth 段后新增拆分说明

```diff
 ### Garmin OAuth 认证机制

 详见 [docs/garmin-auth.md](docs/garmin-auth.md)
+
+### Garmin Intl vs CN 目录/标识隔离
+
+两个源共享 `GarminBase`，但通过子类覆写隔离：
+
+| 属性 | Intl (`Garmin`) | CN (`GarminCN`) |
+|---|---|---|
+| `raw_dir` | `data/raw/garmin/` | `data/raw/garmin_cn/` |
+| `std_dir` | `data/std/garmin/` | `data/std/garmin_cn/` |
+| `source_prefix` → `run_id` | `garmin_#{id}` | `garmin_cn_#{id}` |
+| DB `source` | `"garmin"` | `"garmin_cn"` |
+
+`source_prefix` 方法定义在 `GarminBase`（返回 `"garmin"`），`GarminCN` 覆写返回 `"garmin_cn"`。
+`build_attrs` 通过 `source_prefix` 生成 `run_id` 和 `source`，确保 DB 层无冲突。
```

## 4. L252-263 — CI/CD sync job 步骤更新

```diff
 sync job:
   1. checkout
   2. setup Ruby + bundle
   3. restore DB cache
-  4. restore raw cache (data/raw/)
-  5. record digests (DB + raw)
-  6. workouts sync (受 SYNC__TIME_BUDGET 限制)
-  7. check changed (DB + raw)
-  8. save cache (DB + raw, if changed)
-  9. upload DB artifact (for build job)
-  10. 读 N → 算 f → 可能改 cron
+  4. record DB digest
+  5. restore Garmin token caches
+  6. restore per-source caches (7 源, 各自独立 GH Cache)
+  7. workouts sync (受 SYNC__TIME_BUDGET 限制)
+  8. 读 N → 算 f → 可能改 cron
+  9. check DB changed
+  10. save DB cache + Garmin token caches
+  11. save per-source caches (仅变动的源)
+  12. upload DB artifact (for build job)
```

## 5. L330 — 关键技术决策更新

```diff
-| `data/raw/` 使用 GH Cache | 零认证问题，7 天保留，21MB ~1s restore |
+| Per-source 独立 GH Cache | 每源独立 cache key (`workouts-raw-v1-{source}-{run_id}`)，仅变动的源写 cache。通过 `.github/actions/source-cache/` composite action 封装。数据目录示例: `data/raw/{garmin,garmin_cn,igpsport,...}/`, `data/std/{...}/` |
```

## 测试/引用检查

经审计，**无测试或引用代码需要更新**：

- `spec/` 中无测试断言 `raw_dir`、`std_dir`、`source_prefix` 或 garmin 的 `run_id`/`source`
- `garmin_base.rb:152` 的 `save_secret_to_config` 已正确使用 `@domain == "garmin.cn" ? "garmin_cn" : "garmin"`
- `strava.rb` 和 `dev/dedup_strava.rb` 的 `DUPLICATE_SOURCES` 已包含 `garmin` 和 `garmin_cn` 两个条目
- `cli/sync.rb` 的 case 语句已分别映射 `garmin` → `Garmin` 和 `garmin_cn` → `GarminCN`
