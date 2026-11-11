# Surge Proxy Installer

这是一个面向个人 VPS 的代理服务安装与管理工具，目标是在 Debian 13 amd64 上部署和管理：

- Snell v6 Beta
- AnyTLS
- Hysteria2（支持端口跳跃和独立 Gecko 密码）

项目已完成部署入口和本地自动化测试。根据用户已有验收反馈，三种协议均已在 Debian 13 VPS 上部署，并通过 iOS Surge 连接。更新、卸载、恢复和长期证书续期等场景仍需逐项补充真实验收。

项目整体状态、目录和后续文档维护规则见[根目录项目说明](../README.md)。

`v0.1.6` 修复证书后台续期的目录差异，兼容已有 ECC/RSA 记录，拒绝启用过期证书；管理器升级会保留已安装的协议程序和版本信息。已有证书过期时，按[证书续期与恢复说明](docs/certificate-renewal.md)操作。修复已进行本地回归，真实 VPS 恢复连接待确认。

## 当前可用内容

- 通过 GitHub Release 安装管理器
- 写入 Snell、AnyTLS 和 Hysteria2 配置
- 查看当前配置状态
- 检查 Debian 版本、CPU 架构、端口、域名和程序版本等部署条件
- 生成部署预览
- 申请 TLS 证书并部署代理服务
- 每日检查并自动更新 TLS 证书
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

该命令只验证本次本地代码与发布包，不会重新执行 VPS 部署。已有三协议连接结果不能代替新改动的真实验收；证书续期、systemd 重启恢复、防火墙细节和故障回滚等场景仍需按范围验证。

具体覆盖范围见 [本地检查范围与真实测试边界](docs/local-preacceptance-coverage.md)。

## 从 GitHub Release 安装

向仓库推送名称符合 `proxy-installer-v*` 的 Git 标签后，GitHub Actions 会自动运行测试、生成压缩包及 SHA-256，并创建 Release。

Release 创建后，在 VPS 上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/bbcat2022/surge-proxy-installer/main/proxy-installer/bootstrap/latest.sh | sudo bash
```

安装完成后会自动进入菜单；再次执行同一条命令可更新管理器。详细使用方法见 [GitHub Release 安装与管理说明](docs/github-release-install.md)。

## 代码结构说明

- `tools/config_tool.py`：唯一允许读取和修改主配置文件的组件。
- `lib/adapters`：根据配置生成三种协议所需的运行配置。
- `lib/resources`：处理程序文件、证书、systemd 服务和防火墙规则。
- `lib/orchestrators`：安排各模块的安装顺序。
- `tests`：验证各模块及完整操作流程。
