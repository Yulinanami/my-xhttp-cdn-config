# ==================================================
# 读取已有节点参数
# ==================================================

echo -e "\n${CYAN}[+] 添加扩展模式：vless+xhttp+tls (H3) | hysteria2 直连${NC}\n"
echo -e "${YELLOW}[+] 前置条件${NC}"
echo "  1. 已经成功运行主脚本"
echo "  2. 默认分开端口：Nginx 处理 XHTTP H3，hysteria2 使用独立端口"
echo "  3. 可选共用端口：hysteria2 处理 XHTTP H3 的 QUIC/TLS"
echo ""

find_client_files
info "读取已有客户端配置: $USER_HOME"

BASE_LINE=$(grep -F '#xhttp%2BReality%20%E4%B8%8A%E4%B8%8B%E8%A1%8C%E4%B8%8D%E5%88%86%E7%A6%BB' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$BASE_LINE" ]] || error "未找到 xhttp+Reality 上下行不分离节点，无法自动读取参数"
CDN_LINE=$(grep -F '#xhttp%2Btls%20%E5%8F%8C%E5%90%91CDN' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$CDN_LINE" ]] || error "未找到 xhttp+tls 双向 CDN 节点，无法自动读取 CDN 域名"

BASE_SERVER=$(strip_ipv6_brackets "$(extract_uri_server "$BASE_LINE")")
UUID2=$(extract_uri_user "$BASE_LINE")
XHTTP_PATH=$(get_query_param "$BASE_LINE" "path" || true)
REALITY_DOMAIN=$(get_query_param "$BASE_LINE" "sni" || true)
CDN_DOMAIN=$(get_query_param "$CDN_LINE" "host" || true)
ECH_PARAM=$(get_query_param "$CDN_LINE" "ech" || true)
VLESSENC_ENCRYPTION=$(get_query_param "$BASE_LINE" "encryption" || true)
XHTTP_EXTRA=$(get_query_param "$BASE_LINE" "extra" || true)

[[ -n "$UUID2" ]] || error "读取 UUID2 失败"
[[ -n "$BASE_SERVER" ]] || error "读取 VPS IP 失败"
[[ -n "$XHTTP_PATH" ]] || error "读取 XHTTP Path 失败"
[[ -n "$REALITY_DOMAIN" ]] || error "读取 Reality 域名失败"
[[ -n "$CDN_DOMAIN" ]] || error "读取 CDN 域名失败"
[[ -n "$VLESSENC_ENCRYPTION" ]] || error "读取 VLESS Encryption 失败"

if [[ -n "$ECH_PARAM" ]]; then
  read -rp "是否复用原 CDN 节点的 ECH [y/N]: "
  [[ "${REPLY,,}" == "y" ]] || ECH_PARAM=""
fi

if [[ -n "$XHTTP_EXTRA" ]]; then
  XHTTP_PADDING_KEY=$(sed -n 's/.*"xPaddingKey":[[:space:]]*"\([^"]*\)".*/\1/p' /usr/local/etc/xray/config.json | head -n1)
  XHTTP_PADDING_HEADER=$(sed -n 's/.*"xPaddingHeader":[[:space:]]*"\([^"]*\)".*/\1/p' /usr/local/etc/xray/config.json | head -n1)
  XHTTP_PADDING_PLACEMENT=$(sed -n 's/.*"xPaddingPlacement":[[:space:]]*"\([^"]*\)".*/\1/p' /usr/local/etc/xray/config.json | head -n1)
  XHTTP_PADDING_METHOD=$(sed -n 's/.*"xPaddingMethod":[[:space:]]*"\([^"]*\)".*/\1/p' /usr/local/etc/xray/config.json | head -n1)
  [[ -n "$XHTTP_PADDING_KEY" && -n "$XHTTP_PADDING_HEADER" &&
     -n "$XHTTP_PADDING_PLACEMENT" && -n "$XHTTP_PADDING_METHOD" ]] ||
    error "读取 xpadding 配置失败"
fi

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
if [[ -f "$COMMON_STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$COMMON_STATE_FILE"
fi

SAVED_QUIC_MODE="${QUIC_MODE:-separate}"

echo -e "${YELLOW}[+] QUIC 端口模式${NC}"
echo "  1) 分开端口（默认，Nginx 处理 XHTTP H3）"
echo "  2) 共用端口（hysteria2 处理 XHTTP H3）"
read -rp "请选择端口模式 [1/2] (默认 1): " QUIC_CHOICE
QUIC_CHOICE=${QUIC_CHOICE:-1}

case "$QUIC_CHOICE" in
  1)
    QUIC_MODE="separate"
    if [[ "$SAVED_QUIC_MODE" == "separate" ]]; then
      DEFAULT_XHTTP_H3_PORT="${XHTTP_H3_PORT:-443}"
      DEFAULT_HY2_PORT="${HY2_PORT:-8443}"
    else
      DEFAULT_XHTTP_H3_PORT=443
      DEFAULT_HY2_PORT=8443
    fi

    read -rp "请输入 XHTTP H3 UDP 端口 [默认 ${DEFAULT_XHTTP_H3_PORT}]: " XHTTP_H3_PORT
    XHTTP_H3_PORT=${XHTTP_H3_PORT:-$DEFAULT_XHTTP_H3_PORT}
    read -rp "请输入 hysteria2 UDP 端口 [默认 ${DEFAULT_HY2_PORT}]: " HY2_PORT
    HY2_PORT=${HY2_PORT:-$DEFAULT_HY2_PORT}
    [[ "$XHTTP_H3_PORT" != "$HY2_PORT" ]] || error "分开端口模式下两个端口不能相同"
    ;;
  2)
    QUIC_MODE="shared"
    DEFAULT_XHTTP_H3_PORT=443
    read -rp "请输入共用 UDP 端口 [默认 ${DEFAULT_XHTTP_H3_PORT}]: " XHTTP_H3_PORT
    XHTTP_H3_PORT=${XHTTP_H3_PORT:-$DEFAULT_XHTTP_H3_PORT}
    HY2_PORT=$XHTTP_H3_PORT
    warn "共用端口模式由 hysteria2 处理 XHTTP H3 的 QUIC/TLS"
    ;;
  *)
    error "端口模式只能选择 1 或 2"
    ;;
esac

[[ "$XHTTP_H3_PORT" =~ ^[0-9]+$ ]] || error "XHTTP H3 端口必须是数字"
((XHTTP_H3_PORT >= 1 && XHTTP_H3_PORT <= 65535)) || error "XHTTP H3 端口必须在 1-65535 之间"
[[ "$HY2_PORT" =~ ^[0-9]+$ ]] || error "hysteria2 端口必须是数字"
((HY2_PORT >= 1 && HY2_PORT <= 65535)) || error "hysteria2 端口必须在 1-65535 之间"

DEFAULT_HY2_PASSWORD="${HY2_PASSWORD:-$(openssl rand -hex 16)}"
read -rp "请输入 hysteria2 密码 [默认 ${DEFAULT_HY2_PASSWORD}]: " HY2_PASSWORD
HY2_PASSWORD=${HY2_PASSWORD:-$DEFAULT_HY2_PASSWORD}
[[ "$HY2_PASSWORD" =~ ^[A-Za-z0-9._~-]+$ ]] || error "hysteria2 密码仅支持字母、数字与 . _ ~ -"

info "VPS IP:         $BASE_SERVER"
info "Reality 域名:   $REALITY_DOMAIN"
info "CDN 域名:       $CDN_DOMAIN"
info "XHTTP Path:      $XHTTP_PATH"
info "XHTTP H3:       UDP $XHTTP_H3_PORT"
info "hysteria2:      UDP $HY2_PORT"
info "端口模式:       $QUIC_MODE"
echo ""
