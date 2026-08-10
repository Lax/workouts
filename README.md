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
| GPX | 导入 | — | ✅ **GPX** |
| FIT | 导入 | — | ✅ **FIT** |
| TCX | 导入 | — | ✅ **TCX** |

> ✅ 已实现

---

## GitHub Pages 自动部署（推荐）

Fork 后按以下步骤，5 分钟上线运动看板。

### 快速开始

```
□ 1. 右上角 Fork 本仓库
□ 2. 仓库 → Settings → Pages → Source 选 "GitHub Actions"
□ 3. 创建 Personal Access Token
      打开 https://github.com/settings/tokens →
      Tokens (classic) → Generate new token
      勾选 repo（全部），生成后复制 token 值
□ 4. 添加到 GitHub Secrets
      仓库 → Settings → Secrets and variables → Actions → Secrets
      → New repository secret
      Name: WORKOUTS_SYNC_PAT   Value: 刚才复制的 token
□ 5. 按下方指引添加你的运动平台所需的 GitHub Secrets
□ 6. 仓库 → Actions → Sync Workouts → Run workflow
□ 7. 等待 5 分钟 → https://<你的用户名>.github.io/workouts/
```

> 所有值存入 **GitHub Secrets**（Settings → Secrets and variables → Actions → **Secrets** 标签页），不是 Variables。每条 secret 设好后 workflow 自动读取。

`gh` 命令行版本：

```bash
# 安装 GitHub CLI 并登录后：
gh secret set WORKOUTS_SYNC_PAT --body "你的_token"
```

---

## GitHub Secrets 一览

以下 secrets 按源分类。选哪个源就设对应的行。

| 源 | GitHub Secrets |
|---|---|
| 所有源共用 | `WORKOUTS_SYNC_PAT` |
| Keep | `SYNC_KEEP_PHONE`、`SYNC_KEEP_PASSWORD` |
| iGPSPORT | `SYNC_IGPSPORT_PHONE`、`SYNC_IGPSPORT_PASSWORD` |
| XOSS | `SYNC_XOSS_EMAIL`、`SYNC_XOSS_PASSWORD` |
| XingZhe | `SYNC_XINGZHE_EMAIL`、`SYNC_XINGZHE_PASSWORD` |
| Strava | `SYNC_STRAVA_CLIENT_ID`、`SYNC_STRAVA_CLIENT_SECRET`、`SYNC_STRAVA_REFRESH_TOKEN` |
| Garmin CN | `SYNC_GARMIN_CN_SECRET`（推荐）或 `SYNC_GARMIN_CN_EMAIL` + `SYNC_GARMIN_CN_PASSWORD` |
| Garmin 国际版 | `SYNC_GARMIN_AUTH_SEED` |
| Apple Health | 无（无需 Secrets） |
| 可选（地图瓦片） | `MAPBOX_TOKEN`（缺省用 Carto 暗色底图） |

---

## 各平台配置

### 密码直连型：Keep / iGPSPORT / XOSS / XingZhe

无需本地认证，填入账号密码即可。

```bash
# Keep
gh secret set SYNC_KEEP_PHONE --body "13800138000"
gh secret set SYNC_KEEP_PASSWORD --body "xxx"
# iGPSPORT
gh secret set SYNC_IGPSPORT_PHONE --body "..."
gh secret set SYNC_IGPSPORT_PASSWORD --body "..."
# XOSS
gh secret set SYNC_XOSS_EMAIL --body "..."
gh secret set SYNC_XOSS_PASSWORD --body "..."
# XingZhe
gh secret set SYNC_XINGZHE_EMAIL --body "..."
gh secret set SYNC_XINGZHE_PASSWORD --body "..."
```

<details>
<summary>网页方式添加</summary>

仓库 → Settings → Secrets and variables → Actions → Secrets → New repository secret

| 源 | Secret 1 | Secret 2 |
|---|---|---|
| Keep | `SYNC_KEEP_PHONE` | `SYNC_KEEP_PASSWORD` |
| iGPSPORT | `SYNC_IGPSPORT_PHONE` | `SYNC_IGPSPORT_PASSWORD` |
| XOSS | `SYNC_XOSS_EMAIL` | `SYNC_XOSS_PASSWORD` |
| XingZhe | `SYNC_XINGZHE_EMAIL` | `SYNC_XINGZHE_PASSWORD` |
</details>

<details>
<summary>本地同步可选</summary>

```bash
git clone https://github.com/你的用户名/workouts.git
cd workouts
bundle install

git fit sync --source keep
```
</details>

---

### Strava

首次需要本地 OAuth 授权获取 refresh_token。

需要本地克隆代码完成首次授权。

```bash
git clone https://github.com/你的用户名/workouts.git
cd workouts
bundle install
```

#### 首次准备

```bash
# 1. https://www.strava.com/settings/api → Create App
#    Authorization Callback Domain 填 "localhost"

# 2. 浏览器授权
exe/workouts auth strava
# → 打开终端输出的链接
# → 点击 "Connect with Strava" → 授权
# → refresh_token 自动写入 config.yml
```

#### GitHub Secrets

```bash
gh secret set SYNC_STRAVA_CLIENT_ID --body "xxx"
gh secret set SYNC_STRAVA_CLIENT_SECRET --body "xxx"
gh secret set SYNC_STRAVA_REFRESH_TOKEN \
  --body "$(ruby -ryaml -e 'puts YAML.load_file("config/config.yml").dig("sync","strava","refresh_token")')"
```

三个缺一不可。`client_id` 和 `client_secret` 从 Strava API 控制台获取。

<details>
<summary>网页方式添加</summary>

| Secret | 值来源 |
|---|---|
| `SYNC_STRAVA_CLIENT_ID` | config.yml 里 sync.strava.client_id |
| `SYNC_STRAVA_CLIENT_SECRET` | config.yml 里 sync.strava.client_secret |
| `SYNC_STRAVA_REFRESH_TOKEN` | config.yml 里 sync.strava.refresh_token |
</details>

<details>
<summary>本地同步可选</summary>

```bash
git fit sync --source strava
```
</details>

---

### Garmin CN

需要本地克隆代码完成首次认证。

```bash
git clone https://github.com/你的用户名/workouts.git
cd workouts
bundle install
```

#### 首次准备

```bash
# 编辑 config.yml：
sync:
  garmin_cn:
    email: "13800138000"
    password: "xxx"

# 交互式认证
exe/workouts auth garmin_cn
# → 根据提示输入短信/邮箱验证码
# → secret 自动写入 config.yml（sync.garmin_cn.secret）
```

#### GitHub Secrets

```bash
gh secret set SYNC_GARMIN_CN_SECRET \
  --body "$(ruby -ryaml -e 'puts YAML.load_file("config/config.yml").dig("sync","garmin_cn","secret")')"
```

<details>
<summary>备选：email + password（不推荐，遇到 MFA 会卡住）</summary>

```bash
gh secret set SYNC_GARMIN_CN_EMAIL --body "13800138000"
gh secret set SYNC_GARMIN_CN_PASSWORD --body "xxx"
```
</details>

<details>
<summary>Token 生命周期</summary>

| Token | 有效期 | 说明 |
|---|---|---|
| OAuth1 token+secret | months~years | 根凭证，一次获取，长期有效 |
| OAuth2 access_token | ~6h | OAuth1 自动续期 |
| OAuth2 refresh_token | ~90d | OAuth1 重新签名 |

OAuth1 是链条的根，一次 auth 后自动续期，维护成本极低。
</details>

<details>
<summary>本地同步可选</summary>

```bash
git fit sync --source garmin_cn
```
</details>

---

### Garmin 国际版

garmin.com 受 Cloudflare 防护，认证需要额外工具。这是最复杂的源。

需要本地克隆代码并安装依赖完成首次认证。

```bash
git clone https://github.com/你的用户名/workouts.git
cd workouts
bundle install
playwright install chromium   # Playwright 策略 B 运行时
```

#### 首次准备

```bash
# 编辑 config.yml：
sync:
  garmin:
    email: "your@email.com"
    password: "xxx"

# 交互式认证（git fit auth garmin，默认 Playwright 策略 B）
git fit auth garmin
# → 自动登录 garmin.com
# → 如有 MFA，终端输入验证码
# → auth_seed 自动写入 config.yml
```

#### GitHub Secrets

```bash
gh secret set SYNC_GARMIN_AUTH_SEED \
  --body "$(ruby -ryaml -e 'puts YAML.load_file("config/config.yml").dig("sync","garmin","auth_seed")')"
```

#### ⚠️ 本地与远程票据冲突

本地 sync 会旋转 refresh_token 导致 GitHub Actions 的 token 失效。

**自动部署用户不受影响**——只要不在本地跑 `git fit sync --source garmin`，GitHub Actions 每天自动 sync 自行续期 token。

如果本地和 GitHub Actions 同时使用同一账号，每次本地 sync 后必须紧接：

```bash
git fit sync --source garmin
git fit auth garmin --sync
```

<details>
<summary>Token 生命周期</summary>

| Token | 有效期 | 说明 |
|---|---|---|
| DI access_token | ~18h | refresh_token 续 |
| DI refresh_token | **30 天滑动窗口** | 每次 refresh 旋转，连续 30 天不刷则死 |

GitHub Actions 每天跑 = 自动续期。停了 30+ 天需重新完整认证。
</details>

<details>
<summary>本地同步可选</summary>

```bash
git fit sync --source garmin
```

注意：email + password 只用于本地首次认证，不进 GitHub Secrets。
</details>

---

### Apple Health 导入

#### 1. 从 iPhone 导出数据

健康 App → 右上角头像 → 导出所有健康数据 → export.zip

⚠️ export.zip 包含全量健康数据（心率、睡眠、血氧等），
   远不止运动记录。仓库私有则分支也私有。
   如需对外分享仓库，导入后建议删除该分支。

#### 2. 存入专用分支

```bash
git checkout --orphan GitFit/import/apple_health
mkdir -p data/import/apple_health
# 放入 export.zip

# ≥ 100MB 需先启用 LFS：
#   git lfs track "data/import/apple_health/export.zip"
#   git add .gitattributes

git add data/import/apple_health/export.zip
git commit -m "Add Apple Health export"
git push origin GitFit/import/apple_health
git checkout main   # 切回主分支
```

分支不存在时 GitHub Actions 静默跳过。无需额外 Secrets。

#### 3. 导入后清理

确认数据已导入后，可安全删除该分支：

```bash
git push origin --delete GitFit/import/apple_health
```

Apple Health 按 XML 的 sourceName 字段自动忽略 Strava / Keep / Garmin Connect 等 App 的活动，避免重复。

<details>
<summary>本地导入详解 + 强制重新导入</summary>

```bash
# 本地导入（已迁移至 git-fit）
git fit import apple_health

# 强制重新导入（删除 cache 后重跑 workflow）
gh actions-cache delete imported-v1-apple-health
```
</details>

---

### 2bulu（两步路）导入

本地文件导入，无网络请求。数据源为两步路 App/网页导出的 `.2tk` / `.kml` 文件。

#### 1. 存入专用分支

```bash
git checkout --orphan GitFit/import/2bulu
mkdir -p data/import/2bulu
# 放入 .2tk / .kml 文件

git add data/import/2bulu
git commit -m "Add 2bulu import data"
git push origin GitFit/import/2bulu
git checkout main   # 切回主分支
```

分支不存在时 GitHub Actions 静默跳过。

#### 2. 导入行为

- 每次 sync 检查分支数据文件（`.2tk` / `.kml`）是否变化；仅 SHA256SUMS / 标记文件变化不触发导入
- run_id = `2bulu_{YYYYMMDD}_{sha[0,12]}`（日期前缀 + 内容哈希去重）
- 运动类型：TrackTypeId=8 / SportTypeId 3、18 → `hike`，24 → `run`
- 坐标 WGS-84，无需 GCJ-02 纠偏

<details>
<summary>本地导入详解 + 强制重新导入</summary>

```bash
# 本地导入（已迁移至 git-fit）
git fit import tbulu

# 强制重新导入（删除 cache 后重跑 workflow）
gh actions-cache delete import-2bulu-v1-detect
```
</details>

---

### 本地文件导入

纯本地操作，无网络要求。

```bash
# 批量导入：文件放入 data/import/{gpx,fit,tcx}/ 后执行
git fit import --source gpx          # 所有 GPX 文件
git fit import --source fit          # 所有 FIT 文件
git fit import --source tcx          # 所有 TCX 文件
git fit import --source gpx,fit,tcx  # 三种格式一次导入

# GPX 无内嵌运动类型，用 --sport 指定
git fit import --source gpx --sport run

# 单文件解析（调试用，委托 git fit parse，仅支持 GPX/TCX）
git fit parse activity.gpx --save
git fit parse activity.tcx --save
```

默认读取目录：`data/import/gpx/` · `data/import/fit/` · `data/import/tcx/`

`run_id` = `{source}_` + SHA256 文件内容前缀，内容不变则重复导入自动跳过。

---

## 部署 GitHub Pages

已在快速开始中配置完成。确认以下三点即可：

- Settings → Pages → Source = "GitHub Actions"
- Actions → Sync Workflows 最后一次运行绿色通过
- 访问 `https://<你的用户名>.github.io/workouts/`

之后每天自动同步、构建、部署，零维护。

---

## 配置参考

<details>
<summary>展开：配置层级 / 环境变量命名 / 导出路径 →</summary>

### 配置层级（优先级从高到低）

1. 环境变量（`GIT_FIT_KEEP_PHONE`，与 git-fit gem 一致，见 `git fit init` 模板）
2. `config/config.yml`
3. git-fit 代码内默认值

### 导出路径

| 格式 | 默认路径 |
|---|---|
| JSON | `site/activities.json`（摘要）+ `site/tracks.json`（polyline 映射，可选） |
| CSV | `site/workouts.csv` |
| Stats | `site/stats.json` |

详见 `.env.example` 和 `config/config.yml.example`。
</details>

---

## 常用命令

<details>
<summary>展开：全部 CLI 命令 →</summary>

| 命令 | 说明 |
|---|---|
| `git fit sync` | 同步所有已配置的来源 |
| `git fit sync --source strava` | 只同步特定来源 |
| `git fit sync --act run` | 只同步某种运动类型 |
| `git fit import --source apple_health` | 导入 Apple Health（export.zip）|
| `git fit import --source gpx,fit,tcx` | 批量导入本地 GPX/FIT/TCX 文件 |
| `git fit import --source gpx --sport run` | 导入 GPX 并指定 sport_category 为 run |
| `git fit export json` | 导出 JSON |
| `git fit export csv` | 导出 CSV |
| `git fit export stats` | 导出统计摘要 |
| `git fit dedup` | 全源去重匹配 |
| `exe/workouts auth garmin` | Garmin 国际版认证（委托 git fit auth garmin，支持 `-A`/`-B`/`--auto`/`--sync`/`--mfa-code`）|
| `exe/workouts auth garmin_cn` | Garmin CN 认证（委托 git fit auth garmin_cn）|
| `exe/workouts auth strava` | Strava 授权（委托 git fit auth strava）|
| `exe/workouts auth xoss\|xingzhe` | 不支持交互式认证 — sync 时自动认证（见 git-fit auth-model）|
| `exe/workouts init` | 生成默认配置（委托 git fit） |
| `exe/workouts parse activity.gpx --save` | 解析本地 GPX/TCX 并写入 DB（委托 git fit） |
| `exe/workouts version` | 查看版本（本地） |
</details>

---

## Docker

<details>
<summary>展开 →</summary>

```bash
docker compose run --rm workouts sync
docker compose run --rm workouts export json
```

容器入口为 `git fit`（git-fit gem），因此上面命令等价于 `git fit sync` / `git fit export json`。凭据通过环境变量传入（`GIT_FIT_*` 前缀，参见 `docker-compose.yml`），数据挂载 `./data:/app/data`。
</details>

---

## 常见问题

<details>
<summary>展开 →</summary>

**第一次运行 workflow 失败**
  最常见原因是 GitHub Secrets 没设全。检查 Settings → Secrets and variables → Actions → Secrets，确保你选的源对应的所有 secret 都存在。然后重新运行 workflow。

**GitHub Secrets 设置后需要多久生效**
  立即生效。下次 workflow 运行时自动读取。

**sync 报错 "no credential for source"**
  配置未找到。检查 GitHub Secrets 是否存在，或者 env 变量名是否正确。

**Garmin Intl 报 400/401**
  auth_seed 过期。重新运行 `git fit auth garmin` 完整认证后重新推送 secret。

**Apple Health 找不到 export.zip**
  检查 `GitFit/import/apple_health` 分支是否存在，且包含 `data/import/apple_health/export.zip`。

**部署后页面 404**
  确认 Settings → Pages → Source 选了 "GitHub Actions"（不是 "Deploy from a branch"），且 workflow 的 build 和 deploy job 都已成功。

**WORKOUTS_SYNC_PAT 需要什么权限**
  勾选 `repo`（全部）。workflow 仅在 `sync-scheduler.yml`（自适应 cron 调整）中使用它来修改 `.github/workflows/sync.yml`。

**SQLite gem 编译失败**
  `apt install libsqlite3-dev`（Ubuntu/Debian）或 `brew install sqlite3`（macOS）。
</details>

---

## 进阶阅读

- [数据架构](docs/data-architecture.md)
- [Garmin OAuth 设计](docs/garmin-auth.md)
- [项目完整设计](CONTEXT.md)
