# 一键 SOCKS5 代理安装脚本

`install-socks5.sh` 面向你自己管理的 Linux 服务器，自动安装并配置 Dante SOCKS5 服务。

## 直接执行

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/你的仓库/main/install-socks5.sh | sudo bash
```

脚本会依次询问监听模式、端口和用户名。端口直接回车使用 `1080`；用户名直接回车表示无认证，输入用户名后再输入密码即启用认证。

监听模式 `1` 要求输入 IPv4/CIDR 白名单，例如 `203.0.113.10` 或 `203.0.113.0/24`，多个值用空格或逗号分隔。模式 `2` 监听所有网卡，必须输入大写 `YES` 确认。

## 安全提示

无认证且监听所有网卡会形成公网开放代理，可能被滥用、导致流量与封禁风险。生产环境建议使用白名单和用户名密码认证，并在云厂商安全组中同步限制来源 IP。脚本不会把密码提交到 GitHub，但会将认证写入服务器本地账号数据库；请使用专用账号和强密码。

## 支持与排障

支持使用 `apt`、`dnf` 或 `yum` 的 systemd Linux。服务状态：

```bash
systemctl status danted
journalctl -u danted -n 100 --no-pager
```

停止服务：`systemctl disable --now danted`。配置文件位于 `/etc/danted.conf`。

## GitHub

仓库只应包含脚本和文档，不要提交服务器生成的配置或任何密码。推送前设置远程：

```bash
git remote add origin git@github.com:USER/REPO.git
git push -u origin main
```
