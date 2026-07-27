# 固定二进制清单

这些清单是发布包的一部分。VPS 不查询“最新版本”，只能使用这里固定的版本、URL、归档成员路径与 SHA-256。

| 协议 | 固定版本 | 上游来源 |
|---|---:|---|
| Snell v6 Beta | 协议 v6 / Server artifact v5.0.1 | Surge 官方 v6 Beta 发布页 |
| AnyTLS（sing-box） | v1.13.14 | SagerNet GitHub Release |
| Hysteria2 | v2.10.0 | apernet GitHub Release |

更新版本必须在发布者机器上重新获取上游资产摘要、检查归档成员、更新对应清单并完整测试；不得让 VPS 自动追踪上游最新版本。

Snell 的协议版本与服务端文件版本不同：官方“Snell v6.0.0 Beta”发布条目列出的 Linux amd64 文件名为 `snell-server-v5.0.1-linux-amd64.zip`。该资产只可按 Snell v6 Beta 使用，不得误标为旧 Snell v5 协议。
