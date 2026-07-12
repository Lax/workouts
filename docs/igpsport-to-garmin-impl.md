# igpsport-to-garmin — Implementation Notes

## 命令

```
workouts migrate igpsport_to_garmin      [--dry] [--since=YYYY-MM-DD] [--limit=N]
workouts migrate igpsport_to_garmin_cn   [--dry] [--since=YYYY-MM-DD] [--limit=N]
```

## 类结构

```
Migrate::IGPSportToGarmin           ← 基类（DI OAuth2 认证 + 通用 upload/dedup/GPX）
  └── Migrate::IGPSportToGarminCN   ← CN 子类（OAuth1→OAuth2 认证覆写）
```

## 文件

| 路径 | 作用 |
|---|---|
| `lib/workouts/migrate/igpsport_to_garmin.rb` | 基类（含 International DI OAuth2 认证） |
| `lib/workouts/migrate/igpsport_to_garmin_cn.rb` | CN 子类 |
| `lib/workouts/cli/migrate.rb` | `MigrateCLI` 子命令注册 |
| `lib/workouts/cli/db.rb` | `DbCLI` 子命令注册（DB migration） |
| `spec/lib/migrate/igpsport_to_garmin_spec.rb` | 测试（全 stub、零网络） |
| `spec/fixtures/garmin/*.json` | 上传 API / token / 活动列表 fixture |
| `spec/fixtures/igpsport/sample_l2.json` | L2 标准化数据 |

## 数据流

```
DB activities (source='igpsport')
  │
  ├─ L1: upload map 检查
  │    data/migrate/igpsport_to_garmin/uploads.json  → 命中 → skip
  │
  ├─ L2: Garmin activity name 后缀匹配
  │    GET /activitylist-service/...  → 检查 activityName 含 "[iGPSPORT]"
  │
  └─ 上传
       ├─ raw FIT 存在 → POST /upload-service/upload/ (multipart)
       │                  200 + success → 记录到 upload map
       │                  失败 → 回退 GPX
       └─ GPX 回退
            L2 JSON → 构建 GPX（多路标识）→ 上传
```

## 目录

| | International | CN |
|---|---|---|
| 上传映射 | `data/migrate/igpsport_to_garmin/` | `data/migrate/igpsport_to_garmin_cn/` |
| token 文件 | `data/cache/garmin_garmin_com_tokens.json` | `data/cache/garmin_garmin_cn_tokens.json` |

## 环境变量 / Repo Variable

| 目标 | Env var | Repo Variable | 默认值 |
|---|---|---|---|
| International | `MIGRATE__IGPSPORT_TO_GARMIN__LIMIT` | `MIGRATE_IGPSPORT_TO_GARMIN_LIMIT` | 10 |
| CN | `MIGRATE__IGPSPORT_TO_GARMIN_CN__LIMIT` | `MIGRATE_IGPSPORT_TO_GARMIN_CN_LIMIT` | 10 |

## GPX 多路标识

| 元素 | 内容 | 作用 |
|---|---|---|
| `<trk><name>` | `原名称 [iGPSPORT]` | Garmin Connect 界面可见的来源标记 |
| `<trk><src>` | `igpsport_{rideId}` | GPX 1.1 标准来源字段，程序可解析 |
| `<trk><desc>` | `Imported from iGPSPORT. Source: igpsport_{rideId}` | 描述字段 |
| `<metadata><link>` | `https://igpsport.com/activity/igpsport_{rideId}` | URL 编码的完整 run_id |
| TrackPoint extensions | HR / cadence / power / temperature | Garmin 扩展格式传感器数据 |

## 去重

| 层级 | 数据源 | 条件 |
|---|---|---|
| L1 | 本地 mapping 文件 | `uploads["igpsport_12345"]` 存在 |
| L2 | Garmin activity list（同日期） | `activityName` 以 ` [iGPSPORT]` 结尾 |

## 上传映射文件

```json
{
  "uploads": {
    "igpsport_12345": {
      "garmin_activity_id": "987654321",
      "uploaded_at": "2025-06-18T00:00:00Z",
      "format": "fit"
    }
  }
}
```

## CLI 树

```
workouts
├── sync
├── auth
├── export (json / csv / stats / gpx / svg / all)
├── migrate (igpsport_to_garmin / igpsport_to_garmin_cn)
├── db (migrate)
├── init / parse / version
```

## 限制 / 后续

| 事项 | 计划 |
|---|---|
| L3 模糊匹配（时间+距离） | 后续 |
| Fake Garmin device 注入 | 暂不实现 |
| DB `upload_targets` 列 | 后续 |
