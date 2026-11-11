# TLS 证书续期与恢复

AnyTLS 和 Hysteria2 共用证书；当前 Snell 配置不使用这张证书。证书过期时，两种 TLS 协议可能连接失败，而三项服务仍显示 `active`。

## 更新已有安装

`v0.1.6` 修复后台续期读取错误 ACME 目录的问题，并在更新管理器时保留协议程序及版本信息。

以 root 登录 VPS，执行原安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/bbcat2022/surge-proxy-installer/main/proxy-installer/bootstrap/latest.sh | bash
```

安装完成会进入菜单。选择“5) 退出”，无需重新部署或填写密码。然后通过与定时器相同的服务执行一次检查：

```bash
systemctl start proxy-installer-certificate-renew.service
systemctl status proxy-installer-certificate-renew.service --no-pager -l
journalctl -u proxy-installer-certificate-renew.service -n 80 --no-pager
```

成功执行的一次性任务结束后可能显示 `inactive (dead)`，不要求常驻 `active`。检查退出状态和日志中的 `certificate-renewal=success` 或 `certificate-renewal=not-due`。

如果签发仍失败，先检查日志、域名解析和 TCP 80 端口，包括云平台安全组；HTTP-01 续期仍需要这些条件。

## 检查恢复结果

```bash
find /etc/proxy-installer/certificates -type f -name cert.pem \
  -exec openssl x509 -in {} -noout -dates \;

systemctl is-active proxy-installer-anytls.service proxy-installer-hysteria2.service
systemctl list-timers --all proxy-installer-certificate-renew.timer --no-pager
```

证书到期时间应晚于当前时间。随后在 Surge 中分别测试 AnyTLS 和 Hysteria2 的实际连接；进程或监听正常不等于客户端连接已通过。

## 续期行为

- 数据目录固定为 `/root/.acme.sh`，不依赖当前会话的 HOME 或工作目录。
- 沿用该目录中的账号和证书记录；优先识别已有 ECC 记录，也兼容 RSA；新证书采用 ECC。
- 只检查当前配置域名的续期；找不到记录时明确报错，不将空检查视为成功。
- ACME 导出路径位于数据目录中的 `proxy-installer-export/`，不会在下次续期前被临时目录清理。
- 修正旧的临时导出位置后再续期；候选证书检查有效期和密钥匹配，通过后由事务流程安装和重启相关服务。
- 检查返回“尚未到期”时仍验证证书有效期，不接受已过期的旧文件。

如果原安装使用自定义数据目录，可通过 `ACME_HOME` 指定；手动调用和 systemd 服务必须使用同一个绝对路径。默认安装无需设置。

当前修复已覆盖 239 项本地回归、模拟后台环境和真实过期证书测试；另用官方 acme.sh 3.1.1 离线核验了无 HOME 时的 ECC 导出和无需续期分支。真实 ACME 签发、VPS 更新和 Surge 恢复连接需要在目标环境确认。
