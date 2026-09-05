#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="danted"
CONFIG_FILE="/etc/danted.conf"
die() { echo "错误: $*" >&2; exit 1; }
log() { echo "[socks5] $*"; }

# The script may itself arrive through stdin (curl | bash). Always read
# interactive answers from the controlling terminal instead of stdin.
if ! exec 3<>/dev/tty; then
  die "无法访问交互终端。请在 SSH 终端中直接运行此脚本。"
fi

prompt() {
  local message="$1"
  local variable="$2"
  IFS= read -r -u 3 -p "$message" "$variable" || die "读取终端输入失败。"
}

prompt_secret() {
  local message="$1"
  local variable="$2"
  IFS= read -r -s -u 3 -p "$message" "$variable" || die "读取终端输入失败。"
  echo >&3
}

[[ "${EUID}" -eq 0 ]] || die "请以 root 运行此脚本。"
command -v systemctl >/dev/null || die "需要 systemd。"
[[ -r /etc/os-release ]] || die "无法识别 Linux 发行版。"
source /etc/os-release

PKG_MGR=""
if command -v apt-get >/dev/null; then PKG_MGR=apt
elif command -v dnf >/dev/null; then PKG_MGR=dnf
elif command -v yum >/dev/null; then PKG_MGR=yum
else die "未找到 apt、dnf 或 yum。"; fi

install_packages() {
  log "安装 Dante 和检测工具..."
  case "$PKG_MGR" in
    apt) export DEBIAN_FRONTEND=noninteractive; apt-get update -y; apt-get install -y dante-server iproute2 iputils-ping curl openssl ;;
    dnf) dnf install -y dante-server iproute iputils curl openssl ;;
    yum) yum install -y dante-server iproute iputils curl openssl ;;
  esac
  command -v danted >/dev/null || command -v sockd >/dev/null || die "Dante 安装后未找到 danted/sockd。"
}

echo "监听模式："
echo "  1) IP 白名单"
echo "  2) 所有网卡（高风险）"
prompt "请选择 [1/2，默认 1]: " BIND_MODE
BIND_MODE="${BIND_MODE:-1}"
[[ "$BIND_MODE" == 1 || "$BIND_MODE" == 2 ]] || die "监听模式必须是 1 或 2。"

ALLOWLIST=""
if [[ "$BIND_MODE" == 1 ]]; then
  prompt "请输入允许访问的 IPv4/CIDR（逗号或空格分隔）: " ALLOWLIST
  [[ -n "$ALLOWLIST" ]] || die "白名单不能为空。"
  ALLOWLIST="${ALLOWLIST//,/ }"
  for net in $ALLOWLIST; do
    [[ "$net" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || die "无效 IPv4/CIDR: $net"
  done
else
  prompt "这会创建公网开放代理，请输入 YES 继续: " CONFIRM
  [[ "$CONFIRM" == YES ]] || die "未确认，已退出。"
  ALLOWLIST="0.0.0.0/0"
fi

prompt "代理端口 [1080]: " PORT
PORT="${PORT:-1080}"
[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die "端口必须是 1-65535 的数字。"

prompt "用户名（直接回车=无认证）: " PROXY_USERNAME
AUTH_METHOD="none"
if [[ -n "$PROXY_USERNAME" ]]; then
  [[ "$PROXY_USERNAME" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || die "用户名只能包含字母、数字、点、下划线和短横线。"
  prompt_secret "密码: " PROXY_PASSWORD
  [[ -n "$PROXY_PASSWORD" ]] || die "密码不能为空。"
  [[ "$PROXY_PASSWORD" != *:* ]] || die "密码不能包含冒号。"
  AUTH_METHOD="username"
  if ! id "$PROXY_USERNAME" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$PROXY_USERNAME"
  fi
  printf '%s:%s\n' "$PROXY_USERNAME" "$PROXY_PASSWORD" | chpasswd
fi

install_packages

INTERNAL_IFACE="$(ip -o route show default 2>/dev/null | awk 'NR==1 {print $5}')"
[[ -n "$INTERNAL_IFACE" ]] || INTERNAL_IFACE="$(ip -o -4 addr show scope global | awk 'NR==1 {print $2}')"
[[ -n "$INTERNAL_IFACE" ]] || die "无法确定网络接口。"

TMP_CONFIG="$(mktemp)"
trap 'rm -f "$TMP_CONFIG"' EXIT
{
  echo "logoutput: syslog"
  echo "internal: $INTERNAL_IFACE port = $PORT"
  echo "external: $INTERNAL_IFACE"
  # Dante calls the SOCKS authentication policy "socksmethod".
  echo "socksmethod: $AUTH_METHOD"
  echo "user.privileged: root"
  echo "user.notprivileged: nobody"
  echo "clientmethod: none"
  echo "client pass { from:"
  for net in $ALLOWLIST; do echo "  $net"; done
  echo "to: 0.0.0.0/0 }"
  echo "proxy pass { from:"
  for net in $ALLOWLIST; do echo "  $net"; done
  echo "to: 0.0.0.0/0 command: connect }"
} > "$TMP_CONFIG"
install -o root -g root -m 600 "$TMP_CONFIG" "$CONFIG_FILE"

systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
if ! systemctl restart "$SERVICE_NAME"; then
  systemctl restart sockd 2>/dev/null || {
    systemctl status "$SERVICE_NAME" --no-pager >&2 || true
    journalctl -u "$SERVICE_NAME" -n 40 --no-pager >&2 || true
    die "Dante 启动失败。"
  }
fi

if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
  if [[ "$BIND_MODE" == 1 ]]; then
    for net in $ALLOWLIST; do firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$net port port=$PORT protocol=tcp accept" >/dev/null; done
  else
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null
  fi
  firewall-cmd --reload >/dev/null
elif command -v ufw >/dev/null && ufw status | grep -q active; then
  if [[ "$BIND_MODE" == 1 ]]; then for net in $ALLOWLIST; do ufw allow from "$net" to any port "$PORT" proto tcp >/dev/null; done
  else ufw allow "$PORT/tcp" >/dev/null; fi
elif command -v iptables >/dev/null; then
  if [[ "$BIND_MODE" == 1 ]]; then for net in $ALLOWLIST; do iptables -C INPUT -p tcp -s "$net" --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp -s "$net" --dport "$PORT" -j ACCEPT; done
  else iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT; fi
fi

for _ in 1 2 3 4 5; do
  if systemctl is-active --quiet "$SERVICE_NAME" || systemctl is-active --quiet sockd; then
    if ss -lntH | awk -v port=":$PORT" '$4 ~ port "$" { found=1 } END { exit !found }'; then break; fi
  fi
  sleep 1
done
if ! ss -lntH | awk -v port=":$PORT" '$4 ~ port "$" { found=1 } END { exit !found }'; then
  systemctl status "$SERVICE_NAME" --no-pager >&2 || true
  journalctl -u "$SERVICE_NAME" -n 40 --no-pager >&2 || true
  die "服务未监听端口 $PORT。"
fi
PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
if [[ "$AUTH_METHOD" == username ]]; then URI="socks5://${PROXY_USERNAME}:${PROXY_PASSWORD}@${PUBLIC_IP}:${PORT}"; else URI="socks5://${PUBLIC_IP}:${PORT}"; fi
echo
echo "代理已启动：$URI"
echo "测试：curl --proxy '$URI' https://ifconfig.me"
echo "配置文件：$CONFIG_FILE"
echo "停止：systemctl disable --now $SERVICE_NAME"
