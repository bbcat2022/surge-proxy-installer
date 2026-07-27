# GitHub Release 安装与管理方式

发布者先运行：

```bash
cd proxy-installer
bash packaging/release.sh
```

将整个工作区推送到 GitHub 仓库后，创建形如 `proxy-installer-v0.1.0` 的 Tag。仓库内的 `.github/workflows/release.yml` 会测试、打包并将 `dist/proxy-installer-local.tar.gz` 和同名 `.sha256` 文件发布为同一个 GitHub Release 的资产。不要只上传未校验的脚本。

VPS 必须是 Debian 13 amd64，并已通过 SSH 以 root 或 `sudo -i` 登录。读取 Release 的 SHA-256 值后，执行：

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/bootstrap/install.sh \
  | sudo bash -s -- \
      --release-url https://github.com/<owner>/<repo>/releases/download/<tag>/proxy-installer-local.tar.gz \
      --sha256 <release-tarball-sha256> \
      --version <tag>
```

`<commit-sha>` 应是发布时固定的完整 Git 提交 SHA，而不是可移动的分支名；`<release-tarball-sha256>` 必须来自同一 Release 的 `.sha256` 资产。

引导脚本会安装必要的本地依赖、校验 Release 包、安装管理器到 `/opt/proxy-installer`、初始化 `/etc/proxy-installer/config.yaml`，并创建 `proxy-installer` 管理命令。它**不会**在此时部署代理协议。

先写入所需协议配置，然后运行只读预检；它会验证运行环境、读取并脱敏展示已启用协议，以及提示证书和端口条件：

```bash
sudo proxy-installer --deploy-preflight
```

正式 `deploy` 事务仍在开发中；预检通过不代表协议服务已经被写入或启动。

安装后先运行：

```bash
sudo proxy-installer --preacceptance /var/lib/proxy-installer/preacceptance-report.txt
sudo proxy-installer --plan-deploy snell,anytls,hysteria2 443 8443 9000 20000-20100
```

第二条命令只输出预览。真实部署入口完成后，管理器会要求输入配置、展示影响和得到明确确认后才修改 systemd、证书或防火墙。

## 已安装后的配置命令

以下命令只校验并写入 `desired` 配置，不启动服务：

```bash
sudo proxy-installer --configure-snell 443 '<snell-psk>' domain node.example.com
sudo proxy-installer --configure-anytls 8443 '<anytls-password>' node.example.com true false
sudo proxy-installer --configure-hysteria2 9000 '<hy2-password>' node.example.com 20000-20100 10 true '<independent-gecko-password>' 100
sudo proxy-installer --status
```

密码必须使用单引号包裹，避免被当前 shell 解释。`--status` 默认脱敏，不会打印密码、PSK 或 Gecko 密码。

> Snell 使用官方 v6 Beta 协议。其官方发布页列出的 Linux amd64 服务端文件名为 `snell-server-v5.0.1-linux-amd64.zip`；这是服务端文件版本，不是协议版本。该 Beta 可能有不兼容变更，升级 Snell 服务端时必须同时升级 Surge Beta 客户端。
