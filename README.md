# Surge Proxy Installer

面向个人 VPS 的代理服务安装与管理脚本。通过 SSH 登录 Debian 13 amd64 后，执行一条安装命令即可安装管理器，并按需部署 Snell v6、AnyTLS 和 Hysteria2。

仓库：[bbcat2022/surge-proxy-installer](https://github.com/bbcat2022/surge-proxy-installer)

## 安装与使用

支持环境：Debian 13 amd64、systemd，以及 root 权限。使用 AnyTLS 或 Hysteria2 前，需要将域名解析到 VPS，并开放证书签发和所选协议需要的端口。

使用有 sudo 权限的账号执行：

```bash
curl -fsSL https://raw.githubusercontent.com/bbcat2022/surge-proxy-installer/main/proxy-installer/bootstrap/latest.sh | sudo bash
```

已经使用 root 登录时：

```bash
curl -fsSL https://raw.githubusercontent.com/bbcat2022/surge-proxy-installer/main/proxy-installer/bootstrap/latest.sh | bash
```

安装完成后自动进入菜单。选择“配置并部署代理服务”，使用 `1`、`2`、`3` 单选，或输入 `1,2,3` 多选。按提示填写域名、地址和端口；四类密码留空后直接回车可随机生成。最后输入 `DEPLOY` 确认部署。

后续通过以下命令进入管理菜单：

```bash
proxy-installer
```

再次执行安装命令可以更新管理器并保留已有配置；代理程序的版本与管理器分别管理。完整命令、端口要求和证书操作见[安装与管理说明](proxy-installer/docs/github-release-install.md)。

## 当前功能

- 选择部署 Snell v6、AnyTLS、Hysteria2 或它们的组合。
- 密码自定义或随机生成。
- Hysteria2 端口跳跃可开关；范围格式为 `20000-20100`，间隔默认 30 秒。
- Gecko 使用独立密码，包大小固定为 512–1200。
- AnyTLS 与 Hysteria2 共用同一域名的 TLS 证书。
- 查看状态、导出 Surge 配置、手动检查和自动续期证书。
- 下载固定版本程序，校验文件并通过事务流程部署和检查服务。

## 项目状态

本次维护版本为 `proxy-installer-v0.1.6`，修复后台证书续期使用错误目录的问题，并在更新管理器时保留已安装的协议程序及版本信息。清单中的 Snell 服务端为 `v6.0.0b4`；其他程序版本见[程序版本清单](proxy-installer/manifests/README.md)。这些是项目固定版本，不表示当前上游最新版本。

根据用户的既有验收反馈，Debian 13 VPS 上的一键安装、菜单部署和 Surge 配置使用路径已经运行，Snell v6、AnyTLS、Hysteria2 均已通过 iOS Surge 连接。

后续运行中发现证书自动续期失败，证书过期后影响 AnyTLS、Hysteria2。此次修复已增加目录、ECC/RSA、连续续期和过期证书测试；修复后的 VPS 恢复连接仍需确认。已有安装请参照[证书续期与恢复说明](proxy-installer/docs/certificate-renewal.md)。

更新、卸载、历史恢复、系统重启、故障回滚及证书长期自动续期仍需逐项补充真实验收证据；Hysteria2 端口跳跃和 Gecko 的独立行为也不因基本连接成功而自动视为全部验收。具体边界见[测试覆盖与真实验收状态](proxy-installer/docs/local-preacceptance-coverage.md)。

## 仓库结构

```text
.
├── AGENTS.md                   # 项目级协作和文档维护规则
├── README.md                   # 项目入口与当前状态
├── .github/workflows/          # 自动检查与 Release 构建
└── proxy-installer/            # 安装管理器源码
    ├── bin/                    # 正式入口、开发入口与检查脚本
    ├── bootstrap/              # GitHub 一键安装入口
    ├── lib/                    # 协议、资源、事务和流程编排
    ├── tools/                  # 配置工具与发布内容检查
    ├── manifests/              # 程序版本、下载地址和校验信息
    ├── tests/                  # 自动化测试
    ├── packaging/              # 构建和解包检查
    └── docs/                   # 安装说明与验收说明
```

## 本地开发与检查

开发前阅读根目录和子项目的 `AGENTS.md`。测试使用 Python 3 和 PyYAML；GitHub 自动检查使用 Python 3.11。需要准备本地依赖时，可在仓库根目录执行：

```bash
python3 -m pip install --target .python-packages -r proxy-installer/requirements-dev.txt
```

运行自动化测试：

```bash
bash proxy-installer/bin/test.sh
```

运行测试、构建和解包检查，并生成本地报告：

```bash
bash proxy-installer/bin/preacceptance.sh --verify --report proxy-installer/dist/preacceptance-report.txt
```

本地检查不连接 VPS，也不证明新改动已经在真实环境通过。

## 文档与迭代

- [子项目说明](proxy-installer/README.md)：实现结构与检查入口。
- [安装与管理说明](proxy-installer/docs/github-release-install.md)：VPS 安装和管理命令。
- [程序版本清单](proxy-installer/manifests/README.md)：当前固定程序及更新要求。
- [测试覆盖与真实验收状态](proxy-installer/docs/local-preacceptance-coverage.md)：已确认结果与待验证范围。
- [真实验收记录模板](proxy-installer/docs/debian13-acceptance-record-template.md)：记录新增环境或场景的验收结果。
- [证书续期与恢复说明](proxy-installer/docs/certificate-renewal.md)：更新管理器后恢复证书并检查后台任务。

后续涉及功能、菜单、参数、依赖、支持环境或验收结论的迭代，应同步更新对应说明。具体维护规则见 [AGENTS.md](AGENTS.md)。

文档更新：2026-11-11。
