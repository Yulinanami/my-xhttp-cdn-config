# ==================================================
# 基础输出与环境检测
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本"

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  error "无法识别当前系统发行版"
fi

case "$OS_ID" in
  debian|ubuntu|centos|rhel|almalinux|rocky|ol|amzn|fedora|opensuse*|sles|alpine) ;;
  *)
    error "不支持的发行版: $OS_ID，目前支持 Debian/Ubuntu/CentOS/RHEL/Fedora/openSUSE/SLES/Alpine"
    ;;
esac

if [[ "$OS_ID" == "alpine" ]]; then
  SERVICE_TYPE="openrc"
  NGINX_STOP_CMD="rc-service nginx stop"
  NGINX_START_CMD="rc-service nginx start"
  NGINX_RESTART_CMD="rc-service nginx restart"
else
  SERVICE_TYPE="systemd"
  NGINX_STOP_CMD="systemctl stop nginx"
  NGINX_START_CMD="systemctl start nginx"
  NGINX_RESTART_CMD="systemctl restart nginx"
fi

service_restart() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$1" restart || rc-service "$1" start
  else
    systemctl reset-failed "$1" >/dev/null 2>&1 || true
    systemctl restart "$1"
  fi
}

rawurlencode() {
  local string="$1"
  local encoded="" i char hex
  local LC_ALL=C

  for ((i = 0; i < ${#string}; i++)); do
    char="${string:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-])
        encoded+="$char"
        ;;
      *)
        printf -v hex '%%%02X' "'$char"
        encoded+="$hex"
        ;;
    esac
  done

  printf '%s' "$encoded"
}

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/}"
  value="${value//$'\r'/}"
  printf '%s' "$value"
}

get_query_param() {
  local line="$1"
  local key="$2"
  local query part
  local -a parts

  query="${line#*\?}"
  query="${query%%#*}"

  IFS='&' read -r -a parts <<< "$query"
  for part in "${parts[@]}"; do
    if [[ "${part%%=*}" == "$key" ]]; then
      printf '%s' "${part#*=}"
      return 0
    fi
  done
  return 1
}

extract_uri_user() {
  local line="$1"
  line="${line#vless://}"
  printf '%s' "${line%%@*}"
}

extract_uri_server() {
  local server="${1#*@}"
  server="${server%%\?*}"
  printf '%s' "${server%:443}"
}

normalize_proxy_origin() {
  local url="$1"

  [[ "$url" =~ ^https?:// ]] || url="https://${url}"
  [[ "$url" =~ ^(https?)://([^/?#]+) ]] || return 1
  printf '%s://%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

strip_ipv6_brackets() {
  local value="$1"
  value="${value#[}"
  value="${value%]}"
  printf '%s' "$value"
}

format_uri_host() {
  local value="$1"
  if [[ "$value" == *:* ]]; then
    printf '[%s]' "$value"
  else
    printf '%s' "$value"
  fi
}

find_client_files() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  else
    USER_HOME=$(getent passwd 1000 2>/dev/null | cut -d: -f6 || true)
  fi
  [[ -n "$USER_HOME" && -d "$USER_HOME" ]] || USER_HOME="/root"

  V2RAYN_FILE="$USER_HOME/client-config.txt"
  MIHOMO_FULL_FILE="$USER_HOME/client-config-mihomo-full.yaml"
  MIHOMO_NODES_FILE="$USER_HOME/client-config-mihomo-nodes.yaml"

  [[ -f "$V2RAYN_FILE" ]] || error "未找到 $V2RAYN_FILE，请先运行主脚本"
  [[ -f "$MIHOMO_FULL_FILE" ]] || error "未找到 $MIHOMO_FULL_FILE，请先运行主脚本"
  [[ -f "$MIHOMO_NODES_FILE" ]] || error "未找到 $MIHOMO_NODES_FILE，请先运行主脚本"
}
