# sing-box all-in-one 多协议部署脚本

[English](./README.md) | [简体中文](./README_CN.md)

这个仓库已经从原来的单用途脚本，改造成了一个更接近 `vless-all-in-one` 使用方式的 `sing-box` 一体化部署脚本。

核心入口：

- `install-sing-box.sh`
  负责安装、重配、校验、查看信息、用户管理、分流管理、客户端配置导出、重启、停止、卸载
- `config.json`
  仓库内的示例配置，展示多协议 `sing-box` 服务端结构；实际部署时由脚本动态生成 `/etc/sing-box/config.json`
- `DESIGN.md`
  当前脚本设计说明

## 已支持的协议

基于 `sing-box` 官方文档和官方 Debian 包能力，脚本当前支持：

- `VLESS`
- `VMess`
- `Trojan`
- `Hysteria2`
- `TUIC`
- `NaiveProxy`
- `SOCKS5`
- `SS2022`

说明：

- `VLESS` 默认使用 `Reality` 模式，这样在没有证书时也能部署
- 如果你把 `VLESS` 切到 `tls` 模式，则也需要域名和证书
- `VMess`、`Trojan`、`Hysteria2`、`TUIC`、`NaiveProxy` 都依赖 TLS 证书
- `SOCKS5` 和 `SS2022` 不依赖域名证书
- `NaiveProxy` 在 `sing-box` 中属于较新的能力，脚本要求安装的 `sing-box` 至少为 `1.13.0`

## 现在的脚本能力

当前脚本已经实现：

- 类似 `vless-all-in-one` 的交互菜单
- 一次性部署多协议入站
- 多用户状态持久化
- 协议级用户增删管理
- 服务端分流策略管理
- `sing-box` 客户端配置管理
- 非交互命令行部署
- 自动安装官方 `SagerNet` APT 源与 `sing-box`
- 自动使用 `acme.sh` 申请和安装证书
- 自动随机分配端口，或使用你指定的端口
- 保留并复用上次部署的凭据和端口
- 输出分享链接
- 输出 `sing-box` 客户端 `outbounds` 片段
- 输出完整 `sing-box` 客户端模板
- 提供 `list-users`、`add-user`、`remove-user`、`regenerate`
- 提供 `routing-menu`、`client-menu`
- 提供 `show-info`、`validate`、`status`、`restart`、`stop`、`uninstall`

## 设计取舍

为了稳定落地，这个版本没有机械照搬参考项目的全部实现，而是按 `sing-box` 能力做了下面这些收敛：

- 每个协议使用独立监听端口
- 不做 Xray + sing-box 双内核，只保留 `sing-box`
- 不做订阅面板、流量统计、用户到期管理
- 不依赖仓库内模板去硬改 JSON，而是由脚本直接生成配置

这是刻意设计。目标是先把“多协议、可重复部署、可维护”的核心能力做稳。

## 运行要求

- 系统：`Debian 12`
- 权限：`root`
- 服务管理：`systemd`
- 网络：能访问 Debian 源、`deb.sagernet.org`、`get.acme.sh`

## 快速开始

### 1. 交互式部署

```bash
chmod +x install-sing-box.sh
./install-sing-box.sh
```

直接运行后会进入菜单。

### 2. 一次性部署全部协议

```bash
./install-sing-box.sh install \
  --protocols vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022 \
  --domain example.com \
  --email admin@example.com
```

### 3. 只部署不依赖证书的协议

```bash
./install-sing-box.sh install \
  --protocols vless,socks5,ss2022 \
  --vless-mode reality
```

### 4. 指定部分端口

```bash
./install-sing-box.sh install \
  --protocols vless,trojan,ss2022 \
  --domain example.com \
  --email admin@example.com \
  --vless-port 24443 \
  --trojan-port 24444 \
  --ss2022-port 24445
```

### 5. 查看结果

```bash
./install-sing-box.sh show-info
```

### 6. 查看用户

```bash
./install-sing-box.sh list-users
```

查看单个协议的用户：

```bash
./install-sing-box.sh list-users --protocol vmess
```

### 7. 新增用户

```bash
./install-sing-box.sh add-user --protocol vmess --user-name alice
```

例如为 `SS2022` 新增一名用户：

```bash
./install-sing-box.sh add-user --protocol ss2022 --user-name bob
```

### 8. 删除用户

```bash
./install-sing-box.sh remove-user --protocol socks5 --user-name socks-123abc
```

说明：

- 脚本不允许把某个协议的最后一个用户删空
- `add-user` / `remove-user` 后会自动重建配置并重启 `sing-box`

### 9. 从状态文件重建配置

```bash
./install-sing-box.sh regenerate
```

### 10. 校验配置

```bash
./install-sing-box.sh validate
```

### 11. 分流管理

```bash
./install-sing-box.sh routing-menu
```

当前支持的服务端分流/访问控制开关：

- `BT/PT 限制`
- `回国限制`
- `广告拦截`

默认导出的客户端模板会额外带一层更完整的策略出站：

- `urltest` 组：`auto`
- `selector` 组：`select`
- 默认中国大陆分流规则：
  - `geosite-geolocation-cn -> direct`
  - `geoip-cn -> direct`

说明：

- 你提到的 `geosite-location-cn`，在 `sing-box` 官方规则集里实际使用的是 `geosite-geolocation-cn`
- 客户端默认 `route.final = select`
- `select` 组默认把 `auto` 放在第一位，也就是默认优先自动测速策略

### 12. 客户端配置管理

```bash
./install-sing-box.sh client-menu
```

当前客户端菜单可执行：

- 查看当前客户端信息
- 重建全部客户端文件
- 查看客户端 `outbounds` 片段
- 查看完整客户端模板（mixed）
- 查看 `TUN` 客户端模板

### 13. 查看服务状态

```bash
./install-sing-box.sh status
```

### 14. 重启服务

```bash
./install-sing-box.sh restart
```

### 15. 停止服务

```bash
./install-sing-box.sh stop
```

### 16. 卸载

```bash
./install-sing-box.sh uninstall
```

## 常用参数

- `--protocols`
  逗号分隔协议列表：
  `vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022`
- `--vless-mode reality|tls`
- `--domain`
- `--email`
- `--share-host`
- `--cert-mode acme|self-signed`
- `--acme-mode auto|standalone|alpn`
- `--naive-network tcp|udp`
- `--ss2022-method 2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305`
- `--tuic-cc cubic|new_reno|bbr`
- `--rotate-secrets`
- `--protocol`
- `--user-name`
- `--user-uuid`
- `--user-password`
- `--target-config`

完整参数见：

```bash
./install-sing-box.sh --help
```

## 部署后文件

服务端运行配置默认输出到 `/etc/sing-box`：

- `/etc/sing-box/config.json`
  运行中的服务端配置
- `/etc/sing-box/rule-set/`
  分流策略启用后使用的本地规则集
- `/etc/sing-box/ssl/fullchain.pem`
- `/etc/sing-box/ssl/key.pem`

脚本状态与客户端导出文件默认输出到 `/var/lib/sing-box-script`：

- `/var/lib/sing-box-script/install-state.json`
  脚本状态文件，保存协议、用户、端口、凭据和分流状态
- `/var/lib/sing-box-script/share-links.txt`
  分享链接
- `/var/lib/sing-box-script/client-config.json`
  `sing-box` 客户端 `outbounds` 片段
- `/var/lib/sing-box-script/client-full.json`
  完整 `sing-box` 客户端模板，带 `selector/urltest` 策略组和 `CN -> direct` 默认规则
- `/var/lib/sing-box-script/client-tun.json`
  `TUN` 客户端模板，带 `selector/urltest` 策略组和 `CN -> direct` 默认规则
- `/var/lib/sing-box-script/deployment-summary.txt`
  人类可读的部署摘要
- `/var/lib/sing-box-script/acme-issue.log`
  ACME 或 OpenSSL 证书生成日志

## 证书模式

脚本现在支持两种 TLS 证书模式：

- `acme`
  使用 `acme.sh` 申请公开证书
- `self-signed`
  使用 `openssl` 生成自签名证书

说明：

- `acme` 需要有效域名和邮箱
- `self-signed` 不依赖 ACME，证书身份可以回退到你填写的分享地址或自动探测到的公网 IPv4
- 在 `self-signed` 模式下，导出的 `sing-box` 客户端模板会自动为 TLS 类出站写入 `tls.insecure = true`

## 证书与协议关系

以下场景必须提供 `--domain` 和 `--email`：

- 启用 `VMess` 且使用 `--cert-mode acme`
- 启用 `Trojan` 且使用 `--cert-mode acme`
- 启用 `Hysteria2` 且使用 `--cert-mode acme`
- 启用 `TUIC` 且使用 `--cert-mode acme`
- 启用 `NaiveProxy` 且使用 `--cert-mode acme`
- `VLESS` 使用 `--vless-mode tls --cert-mode acme`

以下场景不强制需要证书：

- `VLESS` 使用默认 `reality`
- `SOCKS5`
- `SS2022`

## 备注

- 仓库里的 `config.json` 只是示例，不会直接部署到系统
- 如果你重复运行脚本，默认会复用上次的 UUID、密码、Reality 密钥、用户列表和端口
- 如果你需要全部重新生成，可以加 `--rotate-secrets`
- `NaiveProxy` 分享地址和不同客户端的导入方式可能略有差异，脚本同时输出了 `sing-box` 客户端片段和更完整的客户端模板
- 当前分流菜单先实现了最稳定的一层：`BT/PT 限制`、`回国限制`、`广告拦截`
- 自签名证书场景下，优先建议使用脚本导出的 `sing-box` 客户端模板，而不只是单独依赖分享链接

## License

本项目使用 [MIT License](./LICENSE)。
