# proxy-installer

Local implementation workspace for the Surge installer redevelopment. It contains isolated resource primitives, protocol adapters and transaction orchestration; it does not perform an unapproved VPS change.

The YAML configuration tool remains the only YAML reader/writer. Bash coordinates plans and transactions; Python does not call systemd, firewall, certificate or network tools.

## 真实验收前的本地门禁

运行以下命令会执行全套隔离测试、构建并解包冒烟验证，并生成明确标示“尚未进行真实验收”的报告：

```bash
./bin/preacceptance.sh --verify --report ./dist/preacceptance-report.txt
```

该结果只表示可以进入经授权的 Debian 13 / iOS Surge 验收，不能替代真实连接、证书、systemd 或防火墙验证。

详细的本地覆盖范围与仍待真实验证的边界见 [本地真实验收前覆盖说明](docs/local-preacceptance-coverage.md)。

## GitHub Release 安装

将当前工作区初始化并推送为 GitHub 仓库。推送 `proxy-installer-v*` Tag 后，仓库附带的 GitHub Actions 会运行测试、生成压缩包和 SHA-256，并创建 Release。VPS 的单条引导安装命令、校验要求和后续管理方式见 [GitHub Release 安装与管理方式](docs/github-release-install.md)。

目前可在 VPS 上完成“安装管理器 → 写入配置 → 只读预检”；真正写入二进制、证书、systemd 与防火墙的 `deploy` 事务仍在实现中，不能把预检结果当作服务已部署。

## 公开仓库内容约束

发布前运行 `python3 tools/publication_guard.py --root .. --mode staged`。根目录编号需求文档、实际配置、证书、令牌和构建产物均不得提交。将 VPS IP、真实测试域名等逐行写入本机 `.private-upload-denylist`；该文件已被 Git 忽略，检查器会拒绝任何包含这些值的待提交文件。
