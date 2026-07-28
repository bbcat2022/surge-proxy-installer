# 程序版本清单说明

`manifests` 目录记录安装器使用的程序版本，包括下载地址、压缩包内部路径和 SHA-256。

## 清单格式

每行包含以下字段：

```text
版本|稳定性|发布日期|平台架构|适用协议|官方下载地址|SHA-256|压缩格式|压缩包内的可执行文件
```

安装器会根据以下信息列出最多三个可用版本：

- 支持当前 VPS 的 CPU 架构；
- 能够提供所选代理协议；
- 下载地址、SHA-256 和压缩包信息完整。

## 当前固定版本

| 协议 | 程序版本 | 官方来源 |
|---|---|---|
| Snell v6 Beta | v6.0.0b4 | Surge 官方 Snell v6 Beta 文件 |
| AnyTLS | sing-box v1.13.14、v1.13.13、v1.13.12 | SagerNet GitHub Release |
| Hysteria2 | v2.10.0、v2.9.3、v2.9.2 | apernet GitHub Release |

Hysteria2 从 v2.9.2 开始支持本项目使用的 Gecko 功能，因此清单中的三个版本都支持独立 Gecko 密码。

## 更新清单的要求

增加或替换版本时，仓库维护者必须：

1. 从官方来源重新下载文件；
2. 核对 SHA-256；
3. 检查压缩包内部的文件名称和路径；
4. 更新对应清单；
5. 运行全部自动化测试；
6. 重新创建 GitHub Release。

## Snell Beta 版本说明

当前固定使用的 Linux amd64 文件是：

```text
snell-server-v6.0.0b4-linux-amd64.zip
```

Snell v6 仍处于 Beta 阶段，客户端和服务端可能发生不兼容变化。更新清单前必须核对当前 Surge 客户端要求的服务端 Beta 版本。
