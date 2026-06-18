# igpsport-to-garmin — Implementation Notes

## 命令

```
workouts export igpsport_to_garmin      [--dry] [--since=YYYY-MM-DD] [--limit=N]
workouts export igpsport_to_garmin_cn   [--dry] [--since=YYYY-MM-DD] [--limit=N]
```

## 文件

| 路径 | 作用 |
|---|---|
| `lib/workouts/export/igpsport_to_garmin.rb` | 核心上传器 |
| `lib/workouts/cli/export.rb` | CLI 命令注册（`igpsport_to_garmin` / `igpsport_to_garmin_cn`） |
| `spec/lib/export/igpsport_to_garmin_spec.rb` | 测试（全 stub、零网络） |
| `spec/fixtures/garmin/upload_{success,failure}.json` | 上传 API fixture |
| `spec/fixtures/garmin/activity_list.json` | 活动列表 fixture（含 `[iGPSPORT]` 后缀条目） |
| `spec/fixtures/garmin/di_tokens.json` | DI OAuth2 token fixture |
| `spec/fixtures/igpsport/sample_l2.json` | L2 标准化数据（3 个 trackpoints） |

## 数据流

```
DB activities (source='igpsport')
  │
  ├─ L1: upload map 检查
  │    data/export/igpsport_garmin/uploads.json  → 命中 → skip
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

## Authentication

### Garmin International (target: :intl)

复用 `data/cache/garmin_garmin_com_tokens.json`（DI OAuth2 token）：

1. 加载 token 文件 → 检查 `expires_at`
2. 未过期 → 直接使用
3. 过期 → POST `diauth.garmin.com/di-oauth2-service/oauth/token` 刷新
4. 刷新结果写回 token 文件

### Garmin CN (target: :cn)

复用 `data/cache/garmin_garmin_cn_tokens.json`（OAuth1 + OAuth2 token）：

1. 加载 token 文件 → 提取 `oauth2.access_token`
2. 未过期 → 直接使用
3. 过期 → 从 `oauth1` 提取 OAuth1 token → HMAC-SHA1 签名的 OAuth2 exchange
4. 更新 token 文件

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

`data/export/igpsport_garmin/uploads.json`：

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

## 批量控制

通过 `--limit=N` 控制每次上传数量，默认 10。分别由两个 env var 控制：

| 目标 | Env var | Repo Variable | 默认值 |
|---|---|---|---|
| International | `SYNC__IGP2GARMIN__LIMIT` | `SYNC_IGP2GARMIN_LIMIT` | 10 |
| CN | `SYNC__IGP2GARMIN_CN__LIMIT` | `SYNC_IGP2GARMIN_CN_LIMIT` | 10 |

CLI 中可通过 Workflow env 传递，例如：
```yaml
env:
  SYNC__IGP2GARMIN__LIMIT: ${{ vars.SYNC_IGP2GARMIN_LIMIT || 10 }}
```

## 限制 / 后续

| 事项 | 计划 |
|---|---|
| L3 模糊匹配（时间+距离） | 后续 |
| Fake Garmin device 注入 | 暂不实现（原始 FIT 可直接上传） |
| DB `upload_targets` 列 | 后续 |
| 活动 GPX 回退缺少 FIT 时自动构建 | 已实现（从 L2 JSON） |


