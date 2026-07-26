# ==================================================
# 读取已有节点参数
# ==================================================

echo -e "\n${CYAN}[+] 添加扩展模式：XHTTP H3 / H2-H3 上下行分离${NC}\n"
echo -e "${YELLOW}[+] 前置条件${NC}"
echo "  1. 已经成功运行主脚本"
echo "  2. Nginx 已启用 HTTP/3"
echo "  3. XHTTP H3 使用的 UDP 端口未被其他服务占用"
echo ""

find_client_files
info "读取已有客户端配置: $USER_HOME"

BASE_LINE=$(grep -F '#xhttp%2BReality%20%E4%B8%8A%E4%B8%8B%E8%A1%8C%E4%B8%8D%E5%88%86%E7%A6%BB' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$BASE_LINE" ]] || error "未找到 xhttp+Reality 上下行不分离节点，无法自动读取参数"
CDN_LINE=$(grep -F '#xhttp%2BTLS%2BH2' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$CDN_LINE" ]] || error "未找到 xhttp+TLS+H2 节点，无法自动读取参数"

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

read -rp "请输入 XHTTP H3 UDP 端口 [1-65535] (默认 443): " XHTTP_H3_PORT
XHTTP_H3_PORT=${XHTTP_H3_PORT:-443}
if [[ ! "$XHTTP_H3_PORT" =~ ^[0-9]+$ ]] ||
   (( XHTTP_H3_PORT < 1 || XHTTP_H3_PORT > 65535 )); then
  error "XHTTP H3 UDP 端口无效，请输入 1-65535 的整数"
fi
if [[ -f /etc/hysteria/config.yaml ]] &&
   grep -Eq "^[[:space:]]*listen:[[:space:]]*:${XHTTP_H3_PORT}[[:space:]]*$" /etc/hysteria/config.yaml; then
  error "UDP ${XHTTP_H3_PORT} 已被 Hysteria2 使用"
fi

info "VPS IP:       $BASE_SERVER"
info "CDN 域名:     $CDN_DOMAIN"
info "XHTTP Path:   $XHTTP_PATH"
info "XHTTP H3:     UDP $XHTTP_H3_PORT"
echo ""
