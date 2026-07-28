# Surge Proxy Installer

这是一个面向个人 VPS 的代理服务安装与管理工具，目标是在 Debian 13 amd64 上部署和管理：

- Snell v6 Beta
- AnyTLS
- Hysteria2（支持端口跳跃和独立 Gecko 密码）

项目已完成完整部署入口和本地自动化测试，下一阶段是在真实 Debian 13 VPS 和 iOS Surge 上验收。

## 当前可用内容

- 通过 GitHub Release 安装管理器
- 写入 Snell、AnyTLS 和 Hysteria2 配置
- 查看当前配置状态
- 检查 Debian 版本、CPU 架构、端口、域名和程序版本等部署条件
- 生成部署预览
- 申请 TLS 证书并部署代理服务
- 导出可供 Surge 使用的代理配置
- 运行真实 VPS 测试前的全套本地检查

各项命令和安装方式见 [GitHub Release 安装与管理说明](docs/github-release-install.md)。

## 运行本地检查

在 `proxy-installer` 目录中执行：

```bash
./bin/preacceptance.sh --verify --report ./dist/preacceptance-report.txt
```

该命令会：

1. 运行全部自动化测试；
2. 构建发布压缩包；
3. 解压并检查发布包能否正常启动；
4. 生成一份本地检查报告。

检查通过只表示代码已具备进入真实 VPS 测试的条件，不代表代理服务已经在 Debian 13 上成功运行。证书申请、systemd 服务、防火墙规则和 iOS Surge 连接仍需在真实环境中逐项验证。

具体覆盖范围见 [本地检查范围与真实测试边界](docs/local-preacceptance-coverage.md)。

## 从 GitHub Release 安装

向仓库推送名称符合 `proxy-installer-v*` 的 Git 标签后，GitHub Actions 会自动运行测试、生成压缩包及 SHA-256，并创建 Release。

VPS 上的一条命令安装方式和安装后的配置方法，见 [GitHub Release 安装与管理说明](docs/github-release-install.md)。

## 代码结构说明

- `tools/config_tool.py`：唯一允许读取和修改主配置文件的组件。
- `lib/adapters`：根据配置生成三种协议所需的运行配置。
- `lib/resources`：处理程序文件、证书、systemd 服务和防火墙规则。
- `lib/orchestrators`：安排各模块的安装顺序。
- `tests`：验证各模块及完整操作流程。
