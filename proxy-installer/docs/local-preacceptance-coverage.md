# 本地真实验收前覆盖说明

本文件只记录隔离测试已覆盖的开发事实；所有项目的 Debian 13 / iOS Surge 真实验证仍为 `not-run`，不得据此标记为 `verified`。

| 范围 | 本地实现与证据 | 本地状态 | 真实状态 |
|---|---|---|---|
| 环境、菜单、结果 | `lib/core`、`lib/interface`；`tests/unit` | tested | not-run |
| YAML、状态、修订恢复 | `tools/config_tool.py`、`lib/config/state.sh`；配置/状态/回退测试 | tested | not-run |
| 三协议适配器 | `lib/adapters`；Snell、AnyTLS、Hysteria2 单元测试 | tested | not-run |
| 二进制候选 | 校验、raw/zip/tar.gz 成员提取、试运行与恢复；`test_binary_resource.py` | tested | not-run |
| 证书 | DNS/80 只读预检、候选原子切换与事务恢复；证书资源/编排测试 | tested | not-run |
| 防火墙 | TCP/UDP/range 的 manual/auto 计划，事务回调回滚；资源/部署/配置应用测试 | tested | not-run |
| 服务与健康 | unit 原子写入、操作替身、监听/版本/日志门禁；资源测试 | tested | not-run |
| Surge 导出 | 片段、二维码、权限与导出失败的 partial-success 语义；导出测试 | tested | not-run |
| 部署、变更、更新、卸载 | 统一事务、锁、回滚、部分成功、故障注入；integration 测试 | tested | not-run |
| 打包门禁 | 全量 unittest、源码包构建与解包冒烟；`bin/preacceptance.sh --verify` | tested | not-run |

## 进入真实验收的限制

- 真实操作必须另行明确授权，并指定 Debian 13 amd64 VPS、域名、风险范围和恢复方案。
- 仅能在计划预览、快照与确认完成后，执行脚本管理的资源；不能操作无关服务或云安全组。
- `preacceptance` 的 `pass` 只表示本地候选验收门禁通过；真实 systemd、下载、ACME、监听、防火墙和 iOS Surge 连接仍需逐项记录。
