# Workouts CLI

运动数据聚合工具。从 Strava、Keep、iGPSPORT、XOSS、XingZhe、Garmin CN、Garmin 国际版 同步，以及 Apple Health、GPX、FIT、TCX 本地导入，统一存入 SQLite，然后部署为可视化仪表盘。

数据流：`多渠道同步 → SQLite → GitHub Pages 仪表盘`

> 在线预览：[lax.github.io/workouts/](https://lax.github.io/workouts/) — 交互式地图 + 统计图表，每日自动更新

---

## 支持的源

| 源 | 方式 | 认证方式 | 源数据格式L1 ( → L2 JSON → L3 DB) |
|---|---|---|---|
| Strava | 同步 | OAuth2 refresh_token | **JSON**，GPX，FIT，TCX |
| Keep | 同步 | 手机号 + 密码 | **JSON**（AES解密+GCJ-02→WGS84） |
| iGPSPORT | 同步 | 手机号 + 密码 | **FIT**，GPX，TCX |
| XOSS | 同步 | 邮箱 + JWT | **FIT** |
| XingZhe | 同步 | 邮箱 + RSA 加密密码 | **JSON** |
| Garmin CN | 同步 | SSO + OAuth1→OAuth2 (secret) | **FIT**，GPX，TCX，CSV |
| Garmin 国际版 | 同步 | DI OAuth2 (auth_seed) | **FIT**，GPX，TCX，CSV |
| Apple Health | 导入 | — | ✅ **export.zip**（XML + GPX） |
| GPX | 导入 | — | △ |
| FIT | 导入 | — | ○ |
| TCX | 导入 | — | △ |

> ✅ 已实现  △ 部分可用（parse CLI）  ○ 待实现

---

## 前置准备

根据你的使用方式选择入口。

### 方案 A：纯 CI 部署（零本地命令）

1. 拥有仓库的写入权限（用于 workflow 更新 cron、归档数据）
2. 根据下方场景添加 GitHub Secrets
3. Actions → Run workflow → 等 5 分钟上线

### 方案 B：本地开发 / 首次认证

```bash
git clone https://github.com/Lax/workouts.git
cd workouts
bundle install

exe/workouts init          # 可选，生成 config.yml 方便本地编辑
exe/workouts db migrate    # 可选，手动建表（sync 自动跑）
```

## 选择你的源

根据你最常用的运动平台，找到下方入口。每个入口包含完整的"本地同步 + CI 部署"流程。

### 密码直连型：Keep / iGPSPORT / XOSS / XingZhe

最简的方式——填入账号密码即可同步，无额外认证步骤。

```bash
# 编辑 config.yml：
sync:
  keep:
    phone: "138xxxx"
    password: "xxx"
```

同步：

```bash
exe/workouts sync --source keep
```

CI Secrets（每个源全要设）：

| 源 | Secret 1 | Secret 2 |
|---|---|---|
| Keep | `SYNC_KEEP_PHONE` | `SYNC_KEEP_PASSWORD` |
| iGPSPORT | `SYNC_IGPSPORT_PHONE` | `SYNC_IGPSPORT_PASSWORD` |
| XOSS | `SYNC_XOSS_EMAIL` | `SYNC_XOSS_PASSWORD` |
| XingZhe | `SYNC_XINGZHE_EMAIL` | `SYNC_XINGZHE_PASSWORD` |

```bash
# 页面：https://github.com/<user>/<repo>/settings/secrets/actions
# CLI：
gh secret set SYNC_KEEP_PHONE --body "138xxxx"
gh secret set SYNC_KEEP_PASSWORD --body "xxx"
```

---

### Strava

需要创建 Strava API 应用后走 OAuth 授权。

```bash
# 1. strava.com → Settings → API → Create App
#    Authorization Callback Domain 填 "localhost"

# 2. 编辑 config.yml：
sync:
  strava:
    client_id: "xxx"
    client_secret: "xxx"

# 3. 浏览器授权
exe/workouts auth strava
# → 打开终端输出的链接
# → 点击 "Connect with Strava" → 授权
# → refresh_token 自动写入 config.yml

exe/workouts sync --source strava
```

CI Secrets：

```
SYNC_STRAVA_CLIENT_ID       →  config.yml 里 sync.strava.client_id
SYNC_STRAVA_CLIENT_SECRET   →  config.yml 里 sync.strava.client_secret
SYNC_STRAVA_REFRESH_TOKEN   →  config.yml 里 sync.strava.refresh_token
```

三个缺一不可。`auth strava` 命令会自动写入 refresh_token，其余两个从 Strava API 控制台获取。

---

### Garmin CN

交互式登录一次即可长期使用。

```bash
# 编辑 config.yml：
sync:
  garmin_cn:
    email: "138xxxx"
    password: "xxx"

# 交互式认证（Ruby 内 SSO，不需浏览器）
exe/workouts auth garmin_cn
# → 根据提示输入短信/邮箱验证码
# → secret 自动写入 config.yml（sync.garmin_cn.secret）

exe/workouts sync --source garmin_cn
```

#### Token 生命周期

| Token | 有效期 | 说明 |
|---|---|---|
| OAuth1 token+secret | months~years | 根凭证，一次获取，长期有效 |
| OAuth2 access_token | ~6h | OAuth1 自动续期 |
| OAuth2 refresh_token | ~90d | OAuth1 重新签名 |

OAuth1 是链条的根，一次 auth 后自动续期，维护成本极低。

#### CI Secrets

推荐（1 个）：

```
SYNC_GARMIN_CN_SECRET  →  config.yml 里 sync.garmin_cn.secret 的值
```

<details>
<summary>备选：email + password（不推荐，遇到交互式 MFA 会卡住）</summary>

```
SYNC_GARMIN_CN_EMAIL     →  sync.garmin_cn.email
SYNC_GARMIN_CN_PASSWORD  →  sync.garmin_cn.password
```
</details>

```bash
gh secret set SYNC_GARMIN_CN_SECRET \
  --body "$(ruby -ryaml -e 'puts YAML.load_file("config/config.yml").dig("sync","garmin_cn","secret")')"
```

---

### Garmin 国际版

garmin.com 受 Cloudflare 防护，认证需要额外 Python 工具。这是最复杂的源。

#### 前置依赖

```bash
pip install -r scripts/requirements.txt
playwright install chromium
```

#### 首次设置

```bash
# 编辑 config.yml：
sync:
  garmin:
    email: "your@email.com"
    password: "xxx"

# 认证脚本（Playwright 开启无头浏览器）
./scripts/garmin_auth_local.sh
# → 自动登录 garmin.com
# → 如有 MFA，终端输入验证码
# → auth_seed 自动写入 config.yml
# → 如已登录 gh CLI，自动设 GH Secret

exe/workouts sync --source garmin
```

#### ⚠️ 本地与远程票据冲突

```
本地 sync 后 refresh_token 被旋转（OAuth2 设计如此），
旧 auth_seed 里的 refresh_token 作废。
下次 CI 冷启动会 400 错误。
```

**必须跟着跑：**

```bash
exe/workouts sync --source garmin
./scripts/garmin_auth_local.sh --sync   # 把最新 token 推成新 auth_seed
```

#### Token 生命周期

| Token | 有效期 | 说明 |
|---|---|---|
| DI access_token | ~18h | refresh_token 续 |
| DI refresh_token | **30 天滑动窗口** | 每次 refresh 旋转，连续 30 天不刷则死 |

CI 每天跑 = 自动续期。CI 停了 30+ 天或本地 sync 后忘跑 `--sync` → auth_seed 失效，需重新完整认证。

**最佳习惯：** 本地 sync 后紧接 `--sync`，一行搞定：

```bash
exe/workouts sync --source garmin && ./scripts/garmin_auth_local.sh --sync
```

#### CI Secrets

```
SYNC_GARMIN_AUTH_SEED  →  config.yml 里 sync.garmin.auth_seed 的值
```

注意：email + password 只用于本地脚本，不进 CI。

---

### Apple Health 导入

从 iOS 健康 App 导出数据后本地或 CI 导入。

#### 本地

```bash
# iPhone 健康 App → 右上角头像 → 导出所有健康数据 → export.zip
mkdir -p data/import/apple_health
cp ~/Downloads/export.zip data/import/apple_health/

exe/workouts sync --source apple_health
# 自动忽略 Strava / Keep / Garmin Connect 等 App 录入的活动
# （按 Apple Health 导出中的 sourceName 字段判断）
```

无需凭据。`serve` 子命令可启动 HTTP 上传界面：

```bash
exe/workouts serve start
# 打开 http://localhost:8080，拖拽上传 export.zip
```

#### CI

<details>
<summary>需将 export.zip 推送到 Git LFS 分支 →</summary>

需要有仓库写入权限的 PAT。如用 gh CLI：先 `gh auth login`。

```bash
git checkout --orphan data/import/apple_health
git lfs track "data/import/apple_health/export.zip"
mkdir -p data/import/apple_health
# 放入 export.zip
git add .gitattributes data/import/apple_health/export.zip
git commit -m "Add Apple Health export"
git push origin data/import/apple_health
```

之后 CI 自动拉取导入。分支不存在时静默跳过。
</details>

无需 CI Secrets。

---

### 本地文件导入

```bash
exe/workouts parse activity.gpx --save
exe/workouts parse activity.tcx --save
exe/workouts parse activity.fit --save  # 待实现
```

纯本地操作。

---

## 部署 GitHub Pages

```bash
# 1. 仓库 → Settings → Pages → Source: GitHub Actions

# 2. 公共 Secrets（所有场景都需要）
#    WORKOUTS_SYNC_PAT
#      GitHub Settings → Developer settings → Personal access tokens
#      → Tokens (classic) → Generate new token，勾选 repo（全选）
#      添加为仓库 Secret。workflow 更新 cron、归档数据都要用它推代码。
#
#    MAPBOX_TOKEN（可选）
#      地图瓦片 token，缺省用 Carto 暗色底图。不设不影响功能。

# 3. 根据所选源添加对应的 Source Secrets
#    （每个场景的 CI Secrets 部分有具体说明）

# 4. 触发同步
#    Actions → Sync Workouts → Run workflow
#    等待 ~5 分钟

# 5. https://<user>.github.io/workouts/  ← 你的运动看板
```

以后每天自动同步、构建、部署，零维护。

---

## 配置参考

<details>
<summary>展开：配置层级 / 环境变量命名 / 导出路径 →</summary>

### 配置层级（优先级从高到低）

1. 环境变量（`SYNC__KEEP__PHONE`，双下划线分隔层级）
2. `config/config.yml`
3. 代码内默认值

### 导出路径

| 格式 | 默认路径 |
|---|---|
| JSON | `site/activities.json` |
| CSV | `site/workouts.csv` |
| SVG | `site/svg/` |
| Stats | `site/stats.json` |

详见 `.env.example` 和 `config/config.yml.example`。
</details>

---

## 常用命令

<details>
<summary>展开：全部 CLI 命令 →</summary>

| 命令 | 说明 |
|---|---|
| `sync` | 同步所有已配置的来源 |
| `sync --source strava` | 只同步特定来源 |
| `sync --act run` | 只同步某种运动类型 |
| `auth garmin_cn` | 交互式登录 |
| `export json` | 导出 JSON |
| `export csv` | 导出 CSV |
| `export svg --style github` | 生成 SVG 海报（5 种风格） |
| `export stats` | 导出统计摘要 |
| `export gpx` | 从 L2 重新导出 GPX |
| `export all` | 执行所有导出 |
| `init` | 生成默认配置 |
| `parse activity.gpx --save` | 解析本地 GPX/TCX 并写入 DB |
| `version` | 查看版本 |

SVG 5 种风格：`github` / `grid` / `circular` / `month-of-life` / `year-summary`。
</details>

---

## Docker

<details>
<summary>展开 →</summary>

```bash
docker compose run --rm workouts sync
docker compose run --rm workouts export svg --style github
docker compose run --rm workouts export json
```

凭据通过环境变量传入（参见 `docker-compose.yml`），数据挂载 `./data:/app/data`。
</details>

---

## 常见问题

<details>
<summary>展开 →</summary>

**sync 报错 "no credential for source"**
  配置未找到。检查 config.yml 或环境变量是否已设置。

**Garmin Intl 报 400/401**
  auth_seed 过期。重新运行 `./scripts/garmin_auth_local.sh` 完整认证。

**Apple Health 找不到 export.zip**
  检查 `data/import/apple_health/export.zip` 是否存在。CI 下检查对应 LFS 分支。

**部署后页面 404**
  确认 Settings → Pages → Source = "GitHub Actions"，workflow 已成功执行。

**SQLite gem 编译失败**
  `apt install libsqlite3-dev`（Ubuntu/Debian）或 `brew install sqlite3`（macOS）。
</details>

---

## 进阶阅读

- [数据架构](docs/data-architecture.md)
- [Garmin OAuth 设计](docs/garmin-auth.md)
- [项目完整设计](CONTEXT.md)
