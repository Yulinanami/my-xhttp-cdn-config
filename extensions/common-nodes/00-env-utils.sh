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
  NGINX_RESTART_CMD="rc-service nginx restart"
else
  SERVICE_TYPE="systemd"
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

get_query_param() {
  local line="$1"
  local key="$2"
  local query part name value

  query="${line#*\?}"
  query="${query%%#*}"

  IFS='&' read -r -a parts <<< "$query"
  for part in "${parts[@]}"; do
    name="${part%%=*}"
    value="${part#*=}"
    if [[ "$name" == "$key" ]]; then
      printf '%s' "$value"
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
  local line="$1"
  local after_at hostport
  after_at="${line#*@}"
  hostport="${after_at%%\?*}"
  printf '%s' "${hostport%:443}"
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

add_candidate_home() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" ]] || return 0
  CANDIDATE_HOMES+=("$dir")
}

find_client_files() {
  local dir uid_home

  CANDIDATE_HOMES=()
  if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
    add_candidate_home "$(eval echo "~$SUDO_USER" 2>/dev/null || true)"
  fi
  add_candidate_home "${HOME:-}"
  add_candidate_home "/root"
  uid_home=$(getent passwd 1000 2>/dev/null | cut -d: -f6 || true)
  add_candidate_home "$uid_home"

  for dir in "${CANDIDATE_HOMES[@]}"; do
    if [[ -f "$dir/client-config.txt" && -f "$dir/client-config-mihomo-full.yaml" && -f "$dir/client-config-mihomo-nodes.yaml" ]]; then
      USER_HOME="$dir"
      V2RAYN_FILE="$dir/client-config.txt"
      MIHOMO_FULL_FILE="$dir/client-config-mihomo-full.yaml"
      MIHOMO_NODES_FILE="$dir/client-config-mihomo-nodes.yaml"
      MIHOMO_TARGET_FILES=("$MIHOMO_FULL_FILE" "$MIHOMO_NODES_FILE")
      return 0
    fi
  done

  error "未找到 client-config.txt / client-config-mihomo-full.yaml / client-config-mihomo-nodes.yaml，请先运行主脚本"
}
