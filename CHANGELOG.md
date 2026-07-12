# Changelog

## Completed

| Item | Status |
|---|---|
| Keep raw 数据持久化（838 条，21MB） | ✅ 已完成 |
| iGPSPORT 原生 GPS 调研（FIT 方案选型完成） | ✅ 已完成（选定 mini_racer + JS SDK） |
| iGPSPORT FIT raw 数据 pipeline（L1+L2+L3） | ✅ 已完成 |
| L1/L2 数据架构设计（三层模型 + 源适配矩阵） | ✅ 已完成 |
| 导出路径 `data/` → `build/` → `site/`（源数据与制品分离） | ✅ 已完成 |
| 3-job workflow（sync / build / deploy） | ✅ 已完成 |
| 原始数据 GH Cache（替代 submodule） | ✅ 已完成 |
| Keep spider_sleep 1s → 0.1s | ✅ 已完成 |
| Config 未知 key 警告 | ✅ 已完成 |
| SportMapper 三层回退 | ✅ 已完成 |
| SVG footer rebrand | ✅ 已完成 |
| LICENSE.txt + 移除 email 占位符 | ✅ 已完成 |
| GitHub Pages 部署 | ✅ 已完成 |
| 多源去重检测（confidence scoring + SVG 标注） | ✅ 已完成 |
| Strava OAuth 自动 refresh + L1/L2/L3 数据链路 | ✅ 已完成 |
| Strava 测试夹具 + 集成测试 | ✅ 已完成 |
| 品牌一致性审计 | ✅ 已完成 |
| GPX 重新导出（`export gpx` from L2） | ✅ 已完成（lib/workouts/export/gpx.rb）|
| Strava OAuth 交互式授权（`auth strava`本地HTTP） | ✅ 已完成（lib/workouts/auth/strava.rb）|
| FIT 解析 pipeline（mini_racer + @garmin/fitsdk） | ✅ 已完成（lib/workouts/fit/decoder.rb）|
| Garmin DI OAuth2 认证（Playwright + curl_cffi 降级链，session cookie 365d 持久化） | ✅ 已完成（lib/workouts/sync/garmin.rb）|
