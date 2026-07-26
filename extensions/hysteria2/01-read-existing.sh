# ==================================================
# 读取已有节点参数
# ==================================================

echo -e "\n${CYAN}[+] 添加扩展模式：Hysteria2 直连${NC}\n"
echo -e "${YELLOW}[+] 前置条件${NC}"
echo "  1. 已经成功运行主脚本"
echo "  2. Hysteria2 使用的 UDP 端口未被其他服务占用"
echo ""

find_client_files
info "读取已有客户端配置: $USER_HOME"

REALITY_LINE=$(grep -F '#reality%2Bvision' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$REALITY_LINE" ]] || error "未找到 reality+vision 节点，无法自动读取参数"

BASE_SERVER=$(strip_ipv6_brackets "$(extract_uri_server "$REALITY_LINE")")
REALITY_DOMAIN=$(get_query_param "$REALITY_LINE" "sni" || true)
[[ -n "$BASE_SERVER" ]] || error "读取 VPS IP 失败"
[[ -n "$REALITY_DOMAIN" ]] || error "读取 Reality 域名失败"

if [[ -f /etc/hysteria/config.yaml ]]; then
  HY2_PASSWORD=$(sed -n 's/^[[:space:]]*password:[[:space:]]*//p' /etc/hysteria/config.yaml | head -n1)
fi

read -rp "请输入 Hysteria2 UDP 端口 [1-65535] (默认 8443): " HY2_PORT
HY2_PORT=${HY2_PORT:-8443}
if [[ ! "$HY2_PORT" =~ ^[0-9]+$ ]] ||
   (( HY2_PORT < 1 || HY2_PORT > 65535 )); then
  error "Hysteria2 UDP 端口无效，请输入 1-65535 的整数"
fi
if [[ -f /etc/nginx/nginx.conf ]] &&
   grep -Eq "^[[:space:]]*listen[[:space:]]+${HY2_PORT}[[:space:]]+quic([[:space:]]|;)" /etc/nginx/nginx.conf; then
  error "UDP ${HY2_PORT} 已被 XHTTP H3 使用"
fi

DEFAULT_HY2_PASSWORD="${HY2_PASSWORD:-$(openssl rand -hex 16)}"
read -rp "请输入 Hysteria2 密码 [默认 ${DEFAULT_HY2_PASSWORD}]: " HY2_PASSWORD
HY2_PASSWORD=${HY2_PASSWORD:-$DEFAULT_HY2_PASSWORD}
[[ "$HY2_PASSWORD" =~ ^[A-Za-z0-9._~-]+$ ]] || error "Hysteria2 密码仅支持字母、数字与 . _ ~ -"

info "VPS IP:       $BASE_SERVER"
info "Reality 域名: $REALITY_DOMAIN"
info "Hysteria2:   UDP $HY2_PORT"
echo ""
