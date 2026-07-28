# 通过 GitHub Release 安装和管理

本文分为两部分：先由仓库维护者创建 Release，再由 VPS 使用者通过一条 SSH 命令安装管理器。

## 一、创建 GitHub Release

在发布者电脑上进入项目目录并检查发布包：

```bash
cd proxy-installer
bash packaging/release.sh
```

将代码推送到 GitHub 后，创建一个名称类似 `proxy-installer-v0.1.0` 的 Git 标签。仓库中的 `.github/workflows/release.yml` 会自动：

1. 运行测试；
2. 生成 `proxy-installer-local.tar.gz`；
3. 生成同名的 `.sha256` 校验文件；
4. 将两个文件发布到同一个 GitHub Release。

## 二、在 VPS 上安装管理器

安装环境必须满足以下条件：

- Debian 13 amd64；
- 已通过 SSH 登录；
- 当前用户是 `root`，或已执行 `sudo -i`。

从 Release 页面取得压缩包的 SHA-256 后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/bootstrap/install.sh \
  | sudo bash -s -- \
      --release-url https://github.com/<owner>/<repo>/releases/download/<tag>/proxy-installer-local.tar.gz \
      --sha256 <release-tarball-sha256> \
      --version <tag>
```

请替换以下内容：

- `<owner>`：GitHub 用户名或组织名；
- `<repo>`：仓库名；
- `<commit-sha>`：发布时对应的完整 Git 提交编号；
- `<tag>`：Release 使用的标签；
- `<release-tarball-sha256>`：同一个 Release 中 `.sha256` 文件记录的校验值。

安装脚本会完成以下工作：

- 安装管理器需要的系统依赖；
- 下载对应的 Release 文件；
- 将管理器安装到 `/opt/proxy-installer`；
- 创建 `/etc/proxy-installer/config.yaml`；
- 创建 `proxy-installer` 管理命令。

这一步只安装管理器，不会部署任何代理协议。

## 三、写入代理配置

以下命令会检查参数并保存配置，但不会启动服务：

```bash
sudo proxy-installer --configure-snell 443 '<snell-psk>' domain node.example.com
sudo proxy-installer --configure-anytls 8443 '<anytls-password>' node.example.com true false
sudo proxy-installer --configure-hysteria2 9000 '<hy2-password>' node.example.com 20000-20100 10 true '<independent-gecko-password>' 100
sudo proxy-installer --status
```

注意：

- 请用单引号包住密码，避免其中的特殊字符被 Shell 解释；
- AnyTLS 与 Hysteria2 当前共用同一套证书，因此两者必须填写同一个域名；
- Hysteria2 的 Gecko 密码与 Hysteria2 主密码相互独立。

## 四、检查部署条件

运行：

```bash
sudo proxy-installer --deploy-preflight
```

该命令只读取系统和配置，不会安装程序或修改服务。它会检查运行环境，显示已启用的协议，并提示证书和端口方面的要求。

还可以运行完整的本地检查和部署预览：

```bash
sudo proxy-installer --preacceptance /var/lib/proxy-installer/preacceptance-report.txt
sudo proxy-installer --plan-deploy snell,anytls,hysteria2 443 8443 9000 20000-20100
```

第二条命令只显示将要使用的端口和协议，不会修改 VPS。

## 五、当前开发限制

正式的 `proxy-installer --deploy <服务器公网 IP> --confirm` 执行流程仍在开发中。现在即使检查全部通过，也不代表程序文件、证书、systemd 服务或防火墙规则已经写入 VPS。

完整部署入口开放后，管理器会先显示将要进行的修改，并要求确认后执行。

## Snell v6 Beta 版本说明

本项目安装的是 Snell v6 Beta 协议。官方发布页中的 Linux amd64 服务端文件名为 `snell-server-v5.0.1-linux-amd64.zip`，其中 `v5.0.1` 是服务端文件版本，不表示安装的是 Snell v5 协议。

Snell v6 Beta 可能继续发生不兼容变化。升级服务端时，应同时使用与其匹配的 Surge Beta 客户端。
