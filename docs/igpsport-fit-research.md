# iGPSPORT FIT 格式调研 — Research

调研日期：2026-06-06，参考：[yihong0618/running_page](https://github.com/yihong0618/running_page)

## API 端点

| 端点 | 方式 | 结果 |
|---|---|---|
| `getDownloadUrl/{rideId}` | GET → OSS URL | ✅ 返回可下载的分享链接 |
| 实际下载内容 | HTTP GET OSS URL | ✅ FIT 二进制（`.FIT` 签名，CRC 有效） |
| `reqType=1`（GPX） | 同 URL | ❌ 返回相同 FIT 文件 |
| `reqType=2`（TCX） | 活动列表为空 | ❌ 不支持 |

**结论：仅 FIT 格式可用。** `reqType` 不影响 `getDownloadUrl` 输出，始终返回 FIT。

## 上游解析方式

`running_page` 使用 Python 官方包 `garmin-fit-sdk` 直接解析 FIT，不转 GPX：

```python
from garmin_fit_sdk import Decoder, Stream
stream = Stream.from_file(fit_path)
messages, errors = decoder.read()
for record in messages["record_mesgs"]:
    if "position_lat" in record and "position_long" in record:
        lat = record["position_lat"] / 2147483648.0
        lng = record["position_long"] / 2147483648.0
```

## FIT 解析方案选型

| 方案 | 工作量 | 依赖 | 评价 |
|---|---|---|---|
| Python subprocess | 1d | python + `garmin-fit-sdk` | ❌ 增加 Python 运行时 |
| C SDK + Ruby FFI | 3d | `fit-c-sdk` + gcc 编译 | ⚠️ 需 CI 编译步骤 |
| **JS SDK + mini_racer** | **~4d** | **`mini_racer` gem + JS bundle** | **✅ 纯 Ruby 依赖，无额外运行时** |

**选定实现：`mini_racer` + `@garmin/fitsdk`** ✅

- JS 解码器: `lib/workouts/fit/decoder.js`（Webpack 打包 @garmin/fitsdk，~150KB）
- Ruby 入口: `lib/workouts/fit/decoder.rb`（`FIT::Decoder.decode` / `.info`）
- iGPSPORT 集成: `igpsport.rb` 下载 raw FIT → 解码 → L1/L2/L3
- 测试: `spec/fit/decoder_spec.rb`
- CI 无额外步骤 — `mini_racer` 是 gem，decoder.js 是静态文件
