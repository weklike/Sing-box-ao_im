# 当前脚本设计说明

## 目标

把当前仓库中的脚本改造成一个 `sing-box` 单内核的多协议 all-in-one 部署工具，使用方式接近 `vless-all-in-one`，但实现完全基于 `sing-box` 官方能力。

## 支持协议

- `VLESS`
- `VMess`
- `Trojan`
- `Hysteria2`
- `TUIC`
- `NaiveProxy`
- `SOCKS5`
- `SS2022`

## 关键设计

### 1. 统一入口

只保留一个主脚本：

- `install-sing-box.sh`

它同时承担：

- 安装
- 重配
- 信息查看
- 配置校验
- 服务管理
- 卸载

### 2. 状态文件驱动

旧版本依赖仓库模板配置做定向修改。新版本改成：

- 动态生成 `/etc/sing-box/config.json`
- 使用 `/var/lib/sing-box-script/install-state.json` 保存端口、凭据、模式、分流状态和证书状态

这样做的目的：

- 便于后续重复执行时保留凭据
- 不再受旧模板结构限制
- 新协议可以直接加入生成器

### 3. 协议策略

- `VLESS` 默认走 `Reality`
- `VMess` / `Trojan` / `Hysteria2` / `TUIC` / `NaiveProxy` 统一走证书模式
- `SOCKS5` 走用户名密码认证
- `SS2022` 只开放 `2022` 系列算法

### 4. 证书策略

证书仍然使用 `acme.sh`，而不是强依赖 `sing-box` 内建 ACME：

- 兼容性更稳
- 更容易控制证书落盘位置
- 更适合当前 Bash 部署脚本模型

### 5. 输出物

脚本部署完成后固定输出：

- `/etc/sing-box/config.json`
- `/etc/sing-box/rule-set/*`
- `/var/lib/sing-box-script/install-state.json`
- `/var/lib/sing-box-script/share-links.txt`
- `/var/lib/sing-box-script/client-config.json`
- `/var/lib/sing-box-script/client-full.json`
- `/var/lib/sing-box-script/client-tun.json`
- `/var/lib/sing-box-script/acme-issue.log`
- `/var/lib/sing-box-script/deployment-summary.txt`

## 当前范围边界

已经实现：

- 多协议安装与重配
- 菜单和 CLI 双模式
- 端口自动分配
- 凭据复用
- 多用户状态持久化
- `list-users` / `add-user` / `remove-user`
- 通过状态文件 `regenerate` 重建配置
- 服务端分流策略管理
- `sing-box` 客户端配置管理
- 客户端 `selector/urltest` 策略出站
- 客户端默认 `geosite-geolocation-cn` / `geoip-cn` 直连规则
- `acme` / `self-signed` 双证书模式
- 服务校验与 systemd 管理
- 客户端分享信息导出

暂未实现：

- 面板化用户管理
- 用户级流量统计
- 订阅转换
- 到期时间和配额
- 同端口多协议复用
