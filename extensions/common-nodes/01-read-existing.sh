# ==================================================
# 读取已有节点参数
# ==================================================

echo -e "\n${CYAN}[+] 添加扩展模式：vless+ws+tls (CDN) | hysteria2 直连${NC}\n"
echo -e "${YELLOW}[+] 前置条件${NC}"
echo "  1. 已经成功运行主脚本"
echo "  2. vless+ws+tls 复用主脚本的 CDN 域名，走 443 端口"
echo "  3. hysteria2 直连使用 VPS IP 与已有证书，默认走 UDP 443 端口"
echo "  4. 请确保防火墙 / 安全组已放行 hysteria2 使用的 UDP 端口"
echo ""

find_client_files
info "读取已有客户端配置: $USER_HOME"

BASE_LINE=$(grep -F '#xhttp%2BReality%20%E4%B8%8A%E4%B8%8B%E8%A1%8C%E4%B8%8D%E5%88%86%E7%A6%BB' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$BASE_LINE" ]] || error "未找到 xhttp+Reality 上下行不分离节点，无法自动读取参数"

BASE_SERVER=$(strip_ipv6_brackets "$(extract_uri_server "$BASE_LINE")")
UUID2=$(extract_uri_user "$BASE_LINE")
XHTTP_PATH=$(get_query_param "$BASE_LINE" "path" || true)
REALITY_DOMAIN=$(get_query_param "$BASE_LINE" "sni" || true)

CDN_LINE=$(grep -F '#xhttp%2Btls%20%E5%8F%8C%E5%90%91CDN' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$CDN_LINE" ]] || error "未找到 xhttp+tls 双向CDN 节点，无法自动读取 CDN 域名"

CDN_DOMAIN=$(get_query_param "$CDN_LINE" "host" || true)
[[ -n "$CDN_DOMAIN" ]] || CDN_DOMAIN=$(get_query_param "$CDN_LINE" "sni" || true)
[[ -n "$CDN_DOMAIN" ]] || CDN_DOMAIN=$(extract_uri_server "$CDN_LINE")

CDN_ECH_PARAM=$(get_query_param "$CDN_LINE" "ech" || true)

[[ -n "$UUID2" ]] || error "读取 UUID2 失败"
[[ -n "$BASE_SERVER" ]] || error "读取 VPS IP 失败"
[[ -n "$XHTTP_PATH" ]] || error "读取 XHTTP Path 失败"
[[ -n "$REALITY_DOMAIN" ]] || error "读取 Reality 域名失败"
[[ -n "$CDN_DOMAIN" ]] || error "读取 CDN 域名失败"

[[ -f /etc/xhttp-cdn/fallback.env ]] || error "未找到主脚本回落配置，请重新运行主脚本"
# shellcheck disable=SC1090
. /etc/xhttp-cdn/fallback.env

case "$FALLBACK_MODE" in
  proxy)
    [[ -n "$REALITY_FALLBACK_ORIGIN" ]] || error "主脚本 Reality 回落网站为空，请重新运行主脚本"
    ;;
  static)
    [[ -f "${STATIC_SITE_DIR}/${REALITY_DOMAIN}/index.html" ]] || error "未找到 Reality 域名页面"
    ;;
  *)
    error "主脚本回落方式无效，请重新运行主脚本"
    ;;
esac

# 读取历史扩展参数，保证重复运行时保持一致
COMMON_STATE_DIR="/etc/xhttp-cdn"
COMMON_STATE_FILE="${COMMON_STATE_DIR}/common-nodes.env"
STATE_WS_PATH=""
STATE_HY2_PASSWORD=""
if [[ -f "$COMMON_STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$COMMON_STATE_FILE"
  STATE_WS_PATH="${WS_PATH:-}"
  STATE_HY2_PASSWORD="${HY2_PASSWORD:-}"
fi

DEFAULT_WS_PATH="${STATE_WS_PATH:-/$(openssl rand -hex 4)}"
read -rp "请输入 WebSocket 路径 [默认 ${DEFAULT_WS_PATH}]: " WS_PATH
WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}
[[ "$WS_PATH" == /* ]] || WS_PATH="/${WS_PATH}"
[[ "$WS_PATH" != "$XHTTP_PATH" ]] || error "WebSocket 路径不能与 XHTTP 路径相同"
[[ "$WS_PATH" =~ ^/[A-Za-z0-9._/-]+$ ]] || error "WebSocket 路径仅支持字母、数字与 . _ - /"

DEFAULT_HY2_PASSWORD="${STATE_HY2_PASSWORD:-$(openssl rand -hex 16)}"
read -rp "请输入 hysteria2 密码 [默认 ${DEFAULT_HY2_PASSWORD}]: " HY2_PASSWORD
HY2_PASSWORD=${HY2_PASSWORD:-$DEFAULT_HY2_PASSWORD}
[[ "$HY2_PASSWORD" =~ ^[A-Za-z0-9._~-]+$ ]] || error "hysteria2 密码仅支持字母、数字与 . _ ~ -"

read -rp "请输入 hysteria2 UDP 端口 [默认 443]: " HY2_PORT
HY2_PORT=${HY2_PORT:-443}
[[ "$HY2_PORT" =~ ^[0-9]+$ ]] || error "hysteria2 端口必须是数字"
((HY2_PORT >= 1 && HY2_PORT <= 65535)) || error "hysteria2 端口必须在 1-65535 之间"

info "CDN 域名:       $CDN_DOMAIN"
info "VPS IP:         $BASE_SERVER"
info "Reality 域名:   $REALITY_DOMAIN"
info "WebSocket 路径: $WS_PATH"
info "hysteria2 端口: $HY2_PORT/udp"
if [[ "$FALLBACK_MODE" == "static" ]]; then
  info "hysteria2 伪装: ${STATIC_SITE_DIR}/${REALITY_DOMAIN}"
else
  info "hysteria2 伪装: $REALITY_FALLBACK_ORIGIN"
fi
echo ""
