# Garmin OAuth Auth — Design

## Architecture overview

```
GarminBase（OAuth1 纯基类）
  ├── GarminBaseDI（DI OAuth2 基类）── Garmin（garmin.com）
  └──────────────────────────────── GarminCN（garmin.cn）
```

| 类 | 域 | 认证路径 | 代码文件 |
|---|---|---|---|
| `GarminBase` | - | 共享基类方法（parse_secret_string、dump_secret、api_get 等） | `garmin_base.rb` |
| `GarminBaseDI` | - | DI OAuth2 方法（refresh_token、strategy_a/b_login） | `garmin_base_di.rb` |
| `Garmin` | garmin.com | authenticate_di → DI OAuth2 | `garmin.rb`（12 行） |
| `GarminCN` | garmin.cn | authenticate → OAuth1→OAuth2 | `garmin_cn.rb`（13 行） |

---

## garmin_cn: OAuth1→OAuth2 Chain

garmin.cn 未受 CF 封锁影响，SSO 登录可正常工作。

### Auth priority chain

```
① secret (config.yml / env SYNC__GARMIN_CN__SECRET)
   Base64([OAuth1 JSON, OAuth2 JSON]) — garth dumps() 兼容
   Parse → OAuth2 valid? → 直接用。过期 → OAuth1 refresh → 新 OAuth2
   Fail → 降级

② token 文件（data/cache/garmin_garmin_cn_tokens.json, GH Cache）
   同 ①。Fail → 删除陈旧文件 → 降级

③ SSO 登录（email+password，支持 MFA）
   成功后 → dump_secret → save_secret_to_config + save_tokens
```

### Token lifetimes

| Token | TTL | 续期方式 |
|---|---|---|
| OAuth1 token+secret | months~years | 一次性获取 |
| OAuth2 access_token | ~6h | OAuth1 refresh |
| OAuth2 refresh_token | ~90d | OAuth1 重新签名 |

### 凭据来源

| 优先级 | 来源 | CI 可用？ |
|---|---|---|
| 权威 | `SYNC__GARMIN_CN__SECRET`（GitHub Secret） | ✅ |
| 缓存 | `data/cache/garmin_garmin_cn_tokens.json`（GH Cache） | ✅ |
| 降级 | SSO 登录（email+password） | ❌ 交互式 |

---

## garmin_intl: DI OAuth2 Flow

garmin.com 的 SSO 端点 `/mobile/api/login` 已被 Garmin 关闭（返回 400），OAuth1 `/preauthorized` 端点也返回 401。CF 对 TLS 指纹严格检测，普通 HTTP 库全部 429/403。

### Auth priority chain（GarminBaseDI#authenticate）

```
① DI token 缓存（data/cache/garmin_garmin_com_tokens.json, GH Cache）
   access_token 有效 → 直接用。过期 → di_refresh。
   refresh 失败 → 清除缓存 → 降级

② auth_seed（sync.garmin.auth_seed / SYNC__GARMIN__AUTH_SEED, GitHub Secret）
   Base64 DI OAuth2 JSON → decode → save_tokens → use / di_refresh
   refresh 失败 → 清空 @access_token → 降级

③ Strategy A: curl_cffi subprocess（scripts/garmin_auth.py）
   mobile+cffi（Safari TLS, 优先）→ portal+cffi（5 指纹, 降级）
   → CAS ticket → DI OAuth2 交换 → 存缓存
   支持 MFA（env var SYNC__GARMIN__MFA_CODE 或 stdin）

④ Strategy B: Playwright subprocess（scripts/garmin_auth_playwright.py）
   Headless Chromium → SSO form → ticket → DI 交换
   Session cookies 持久化 ~1 年（data/cache/）

⑤ 全部失败 → false
```

### Token lifetimes

| Token | TTL | 续期方式 |
|---|---|---|
| DI access_token | ~18h | POST diauth.garmin.com refresh_token |
| DI refresh_token | 30d 滑动窗口 | 每次 refresh 旋转续期，每日 CI 运行即可无限延续 |

### 凭据来源

| 来源 | CI 可用？ |
|---|---|
| `SYNC__GARMIN__EMAIL` + `SYNC__GARMIN__PASSWORD`（GitHub Secrets） | ✅ Strategy A/B 入口 |
| DI token（GH Cache） | ✅ 日常续期 |
| MFA code（`SYNC__GARMIN__MFA_CODE` env var） | ⚠️ 一次性码，无法预置。推荐用 Strategy B 缓存 session |

### 实测结果（2026-06-17）

- `mobile+cffi` Safari TLS 成功穿透 CF
- MFA 交互式认证成功 → DI OAuth2 token 交换成功 → 同步 2 条活动
- `portal+cffi` 5 指纹中 Safari/Edge/Chrome 返回无响应，safari_ios/chrome120 返回 403
- `auth_seed` Base64 已写入 config.yml + GitHub Secret
- 结论：curl_cffi `mobile+cffi` 对无 MFA/有 MFA 账号均可用（MFA 通过 stdin 交互）

### 首次设置（有 MFA）

```bash
./scripts/garmin_auth_local.sh
```
静态 `auth_seed` 引导 CI 完成第一次认证 → 后续 CI 使用 `data/cache/` 中的工作副本自旋。

脚本自动做：读 `config.yml` → `mobile+cffi` 穿透 CF（~60s）→ 提示输入 MFA → DI OAuth2 token 交换 → Base64 编码 → 写入 `config.yml`（`sync.garmin.auth_seed`）→ 尝试 `gh secret set SYNC_GARMIN_AUTH_SEED`

### 日常 token 同步

```bash
./scripts/garmin_auth_local.sh --sync
```

**为什么需要 `--sync`：**

1. 本地执行 `workouts sync --source garmin` 后，CI 中使用的 refresh_token **被旋转**（每次 refresh_token 调用旋转 token，旧 token 永久失效）。
2. 此时 `SYNC_GARMIN_AUTH_SEED` 中保存的旧 auth_seed 已包含被旋转过的 refresh_token。
3. 下一次 CI 运行，若 GH Cache miss（7 天缓存或 cache 全部失效），CI 回退到 `load_auth_seed` → `refresh_token()` → **失败**（refresh_token 已被本地旋转）→ 降级到 Strategy A/B
4. `auth_seed` 是 CI 冷启动的最后防线；只要 auth_seed 中的 refresh_token 比 CI 的 cache 更新即可。

**`--sync` 解决的问题：** 在后续本地完成 sync（`data/cache/garmin_garmin_com_tokens.json` 已更新）后，调用 `--sync` 将最新的 cache token 升格为下一个 auth_seed。
这确保 CI 在任何 cache miss 时都能降级到最新的 refresh_token。

**用法：** 本地 sync 后执行 `--sync`

```
scripts/garmin_auth_local.sh --sync
# 读取 data/cache/garmin_garmin_com_tokens.json
# Base64 编码 → 写 config.yml（sync.garmin.auth_seed）
# → gh secret set SYNC_GARMIN_AUTH_SEED
```

### MFA 处理

MFA 验证码通过 env var `SYNC__GARMIN__MFA_CODE` 传入 Python 脚本。**此做法仅适用于本地调试或已知验证码的有效期内**，不适合 CI 自动化。

**推荐路径：** Strategy B（Playwright）首次运行交互式 MFA 后，session cookies 缓存至 `data/cache/`，后续从 cookies 恢复无需 MFA。首次 requires 人工在 CI 中手动触发带 Secrets 的 workflow_dispatch。

### CI cache

| 缓存 | GH Cache Key | 路径 |
|---|---|---|
| DI token | `garmin-tokens-v1-garmin-{run_id}` | `data/cache/garmin_garmin_com_tokens.json` |
| CN token | `garmin-tokens-v1-garmin_cn-{run_id}` | `data/cache/garmin_garmin_cn_tokens.json` |
| Playwright browser（可选） | `garmin-playwright-browser-v1-{os}` | `~/.cache/ms-playwright` |

---

## 附录：数据传输链与关键格式

### 数据格式

#### ① CAS Service Ticket

| 属性 | 值 |
|---|---|
| 格式 | `ST-XXXXXXXXXXXXXXXXXXXXXXXXXXXX`（40+ 字符） |
| 来源 | SSO 登录成功：`response.serviceTicketId` |
| 去向 | 作为 `service_ticket` 参数 POST 到 DI token exchange |
| 有效期 | 一次性，换完即废 |
| 存储 | 仅内存，不落盘 |

#### ② DI OAuth2 Token JSON

```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "expires_in": 64800,
  "scope": "DI_COACHING_WRITE ...",
  "token_type": "Bearer",
  "di_client_id": "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2"
}
```

| 字段 | 来自 | 去向 | 设计原因 |
|---|---|---|---|
| `access_token` | `diauth.garmin.com` 响应 | `Authorization: Bearer` 请求头 | OAuth2 bearer token，~18h |
| `refresh_token` | 同一次响应 | refresh 请求 body | 30d 滑动窗口，每次 refresh 旋转续期 |
| `di_client_id` | JWT payload 的 `client_id` 声明 | refresh 的 `client_id` 参数 + Basic auth | **refresh 时必须用签发 token 的那个 client_id**（Garmin 季度轮换），用错返回 401 |
| `expires_at` | 脚本/Ruby 计算 | `access_token_valid?` 判断 | `time() + expires_in` |

#### ③ DI Token Exchange 请求

```
POST https://diauth.garmin.com/di-oauth2-service/oauth/token
Authorization: Basic base64(client_id + ":")   ← ""空 secret，DI 协议要求
Content-Type: application/x-www-form-urlencoded
Cache-Control: no-cache                          ← 阻止 CF 缓存 stale token
User-Agent: GCM-Android-5.23                    ← Android app UA

client_id=GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2
service_ticket=ST-XXXX                            ← 不是 "ticket"！
grant_type=https://connectapi.garmin.com/.../service_ticket
service_url=https://mobile.integration.garmin.com/gcm/android  ← 必须匹配 SSO 登录的 service
```

#### ④ auth_seed 编码链

```
DI Token JSON (来自 diauth.garmin.com)
  │  JSON.dump
  ▼
JSON 文本
  │  Base64.strict_encode64
  ▼
Base64 文本 → config.yml（sync.garmin.auth_seed）
           → GitHub Secret（SYNC_GARMIN_AUTH_SEED）
           → env var（SYNC__GARMIN__AUTH_SEED）

CI 中 decode:
  Base64.strict_decode64 → JSON.parse → @access_token → save_tokens(data/cache/)
```

### 传输链

```
用户邮箱+密码
  ▼
SSO: POST /mobile/api/login（或 /portal/api/login）
  │  ← MFA? stdin 输入验证码
  ▼
CAS Service Ticket (ST-XXXX)
  ▼
POST diauth.garmin.com/di-oauth2-service/oauth/token
  Headers: Authorization: Basic + Garmin-UA + Cache-Control
  Body: client_id + service_ticket + grant_type + service_url
  │  ← service_url 必须与 SSO 登录一致（混用返回 400）
  ▼
DI OAuth2 Token JSON
  ├─ access_token → data/cache/ → Ruby api_get
  ├─ refresh_token → refresh_token()
  └─ di_client_id → refresh Basic auth
  ▼
┌────────── 每日 CI ──────────┐
│ load_tokens(data/cache/)    │
│ access_token 有效?          │
│ ├─ 是 → api_get              │
│ └─ 否 → refresh_token() →   │
│      新 token → save_tokens │
│      30d 滑动窗口            │
└────────────────────────────┘
  ▼
Garmin API: Authorization: Bearer eyJ...
```

### 设计决策

| 决策 | 原因 |
|---|---|
| `Authorization: Basic base64(client_id:)` | DI OAuth2 协议，client_id 作用户名，空串作密码。与 OAuth1 consumer secret 签名无关 |
| `service_url` 必须匹配 SSO | Garmin 验证 ticket 和 exchange 来自同一流程。mobile 用 `mobile.integration.garmin.com`，portal 用 `connect.garmin.com/app` |
| `service_ticket` 不是 `ticket` | Garmin 的特定参数命名（与其他 SSO API 不一致） |
| `Cache-Control: no-cache` | 防止 Cloudflare 缓存过期 token |
| `di_client_id` 存入 token JSON | 刷新时**必须用签发 token 的那个 client_id**，不能写死 |
| 30d refresh_token 滑动窗口 | 每次 refresh 返回新 refresh_token 并旋转旧 token。连续 30 天未刷新则失效，需重新用 `auth_seed` 或 SSO 引导 |
| `auth_seed`（非 `refresh_token`）命名 | 因为它存的是**整个 DI OAuth2 token JSON 的 Base64**（access + refresh + client_id），不是单一 refresh_token 字符串。与 Strava 的 `refresh_token`（真刷新令牌）语义分离 |

### DI Exchange 故障排查

| HTTP | 可能原因 |
|---|---|
| 400 | `service_ticket` 参数名写错（写成了 `ticket`） |
| 400 | 缺失 `service_url` 参数 |
| 400 | 缺失 `Authorization: Basic` 请求头 |
| 401 | DI client_id 已作废（Garmin 季度轮换） |
| 401 | `service_url` 与 SSO 登录时使用的不一致 |
| 429 | CF 速率限制（增加 delay） |
