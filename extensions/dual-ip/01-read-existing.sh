# ==================================================
# 读取已有节点参数
# ==================================================

echo -e "\n${CYAN}[+] 添加扩展模式：上行 xhttp+Reality IPv4 / IPv6 | 下行 xhttp+Reality IPv6 / IPv4${NC}\n"
echo -e "${YELLOW}[+] 前置条件${NC}"
echo "  1. 已经成功运行主脚本"
echo "  2. 这里只同步 xpadding，不需要 ECH"
echo "  3. VPS 的 IPv4 与 IPv6 都可以访问 443"
echo "  4. 两个 Reality 域名 DNS 分别指向 IPv4 / IPv6，且保持仅 DNS（灰色云朵）"
echo ""

find_client_files
info "读取已有客户端配置: $USER_HOME"

BASE_LINE=$(grep -F '#xhttp%2BReality%20%E4%B8%8A%E4%B8%8B%E8%A1%8C%E4%B8%8D%E5%88%86%E7%A6%BB' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$BASE_LINE" ]] || error "未找到 xhttp+Reality 上下行不分离节点，无法自动读取参数"

UUID2=$(extract_uri_user "$BASE_LINE")
BASE_SERVER=$(strip_ipv6_brackets "$(extract_uri_server "$BASE_LINE")")
XHTTP_PATH=$(get_query_param "$BASE_LINE" "path" || true)
VLESSENC_ENCRYPTION=$(get_query_param "$BASE_LINE" "encryption" || true)
REALITY_DOMAIN=$(get_query_param "$BASE_LINE" "sni" || true)
PUBLIC_KEY=$(get_query_param "$BASE_LINE" "pbk" || true)
SHORT_ID=$(get_query_param "$BASE_LINE" "sid" || true)
BASE_EXTRA_ENC=$(get_query_param "$BASE_LINE" "extra" || true)

CDN_LINE=$(grep -F '#xhttp%2Btls%20%E5%8F%8C%E5%90%91CDN' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
if [[ -n "$CDN_LINE" ]]; then
  DEFAULT_CDN_DOMAIN=$(get_query_param "$CDN_LINE" "host" || true)
  [[ -n "$DEFAULT_CDN_DOMAIN" ]] || DEFAULT_CDN_DOMAIN=$(get_query_param "$CDN_LINE" "sni" || true)
  [[ -n "$DEFAULT_CDN_DOMAIN" ]] || DEFAULT_CDN_DOMAIN=$(extract_uri_server "$CDN_LINE")
fi

[[ -n "$UUID2" ]] || error "读取 UUID2 失败"
[[ -n "$XHTTP_PATH" ]] || error "读取 XHTTP Path 失败"
[[ -n "$VLESSENC_ENCRYPTION" ]] || error "读取 VLESS Encryption 失败"
[[ -n "$REALITY_DOMAIN" ]] || error "读取 Reality 域名失败"
[[ -n "$PUBLIC_KEY" ]] || error "读取 Reality Public Key 失败"
[[ -n "$SHORT_ID" ]] || error "读取 Reality Short ID 失败"

[[ -f /etc/xhttp-cdn/fallback.env ]] || error "未找到主脚本回落配置，请重新运行主脚本"
# shellcheck disable=SC1090
. /etc/xhttp-cdn/fallback.env

[[ "$FALLBACK_MODE" == "proxy" || "$FALLBACK_MODE" == "static" ]] || error "主脚本回落方式无效，请重新运行主脚本"

if [[ "$BASE_SERVER" == *:* ]]; then
  DEFAULT_IPV6="$BASE_SERVER"
else
  DEFAULT_IPV4="$BASE_SERVER"
fi

if command -v curl >/dev/null 2>&1; then
  IPV4_ADDRESS=$(curl -4 -s --max-time 5 ip.sb || true)
  IPV6_ADDRESS=$(curl -6 -s --max-time 5 ip.sb || true)
fi

IPV4_ADDRESS=${IPV4_ADDRESS:-$DEFAULT_IPV4}
IPV6_ADDRESS=${IPV6_ADDRESS:-$DEFAULT_IPV6}
IPV6_ADDRESS=$(strip_ipv6_brackets "$IPV6_ADDRESS")

[[ -n "$IPV4_ADDRESS" ]] || error "IPv4 地址不能为空"
[[ "$IPV4_ADDRESS" != *:* ]] || error "IPv4 地址格式错误"
[[ -n "$IPV6_ADDRESS" ]] || error "IPv6 地址不能为空"
[[ "$IPV6_ADDRESS" == *:* ]] || error "IPv6 地址格式错误"

IPV4_URI=$(format_uri_host "$IPV4_ADDRESS")
IPV6_URI=$(format_uri_host "$IPV6_ADDRESS")

read -rp "请输入 IPv4 Reality 域名: " REALITY_DOMAIN_V4
[[ -n "$REALITY_DOMAIN_V4" ]] || error "IPv4 Reality 域名不能为空"
[[ "$REALITY_DOMAIN_V4" =~ ^[A-Za-z0-9.-]+$ && "$REALITY_DOMAIN_V4" != "." && "$REALITY_DOMAIN_V4" != ".." ]] || error "IPv4 Reality 域名格式无效"
[[ "$REALITY_DOMAIN_V4" != "$DEFAULT_CDN_DOMAIN" ]] || error "IPv4 Reality 域名不能与 CDN 域名相同"

read -rp "请输入 IPv6 Reality 域名: " REALITY_DOMAIN_V6
[[ -n "$REALITY_DOMAIN_V6" ]] || error "IPv6 Reality 域名不能为空"
[[ "$REALITY_DOMAIN_V6" =~ ^[A-Za-z0-9.-]+$ && "$REALITY_DOMAIN_V6" != "." && "$REALITY_DOMAIN_V6" != ".." ]] || error "IPv6 Reality 域名格式无效"
[[ "$REALITY_DOMAIN_V4" != "$REALITY_DOMAIN_V6" ]] || error "IPv4 / IPv6 Reality 域名不能相同"
[[ "$REALITY_DOMAIN_V6" != "$DEFAULT_CDN_DOMAIN" ]] || error "IPv6 Reality 域名不能与 CDN 域名相同"

if [[ "$FALLBACK_MODE" == "proxy" ]]; then
  [[ -n "$REALITY_FALLBACK_ORIGIN" && -n "$REALITY_FALLBACK_HOST" ]] || error "主脚本 Reality 回落网站为空，请重新运行主脚本"

  if [[ "$REALITY_DOMAIN_V4" == "$REALITY_DOMAIN" ]]; then
    FALLBACK_ORIGIN_V4="$REALITY_FALLBACK_ORIGIN"
    FALLBACK_HOST_V4="$REALITY_FALLBACK_HOST"
  else
    read -rp "请输入 ${REALITY_DOMAIN_V4} 的回落网站: " FALLBACK_ORIGIN_V4
    FALLBACK_ORIGIN_V4=$(normalize_proxy_origin "$FALLBACK_ORIGIN_V4") || error "IPv4 Reality 回落网站格式无效"
    FALLBACK_HOST_V4=${FALLBACK_ORIGIN_V4#*://}
    [[ "$FALLBACK_ORIGIN_V4" != "$REALITY_FALLBACK_ORIGIN" && "$FALLBACK_ORIGIN_V4" != "$CDN_FALLBACK_ORIGIN" ]] || error "不同入口域名不能共用回落网站"
  fi

  if [[ "$REALITY_DOMAIN_V6" == "$REALITY_DOMAIN" ]]; then
    FALLBACK_ORIGIN_V6="$REALITY_FALLBACK_ORIGIN"
    FALLBACK_HOST_V6="$REALITY_FALLBACK_HOST"
  else
    read -rp "请输入 ${REALITY_DOMAIN_V6} 的回落网站: " FALLBACK_ORIGIN_V6
    FALLBACK_ORIGIN_V6=$(normalize_proxy_origin "$FALLBACK_ORIGIN_V6") || error "IPv6 Reality 回落网站格式无效"
    FALLBACK_HOST_V6=${FALLBACK_ORIGIN_V6#*://}
    [[ "$FALLBACK_ORIGIN_V6" != "$REALITY_FALLBACK_ORIGIN" && "$FALLBACK_ORIGIN_V6" != "$CDN_FALLBACK_ORIGIN" ]] || error "不同入口域名不能共用回落网站"
  fi
  [[ "$FALLBACK_ORIGIN_V4" != "$FALLBACK_ORIGIN_V6" ]] || error "IPv4 和 IPv6 Reality 域名不能共用回落网站"
else
  prepare_static_site() {
    local domain="$1"
    mkdir -p "${STATIC_SITE_DIR}/${domain}"
    if [[ ! -f "${STATIC_SITE_DIR}/${domain}/index.html" ]]; then
      cat > "${STATIC_SITE_DIR}/${domain}/index.html" <<'INITIAL_HTML_EOF'
@@include templates/default-index.html.tmpl
INITIAL_HTML_EOF
      sed -i \
        -e "s|<title>欢迎</title>|<title>${domain}</title>|" \
        -e "s|<h1>欢迎访问</h1>|<h1>${domain}</h1>|" \
        "${STATIC_SITE_DIR}/${domain}/index.html"
      chmod 644 "${STATIC_SITE_DIR}/${domain}/index.html"
    fi
    chown "$(stat -c '%u:%g' "$USER_HOME")" \
      "${STATIC_SITE_DIR}/${domain}" \
      "${STATIC_SITE_DIR}/${domain}/index.html"
  }

  prepare_static_site "$REALITY_DOMAIN_V4"
  prepare_static_site "$REALITY_DOMAIN_V6"
  echo "IPv4 Reality 页面：${STATIC_SITE_DIR}/${REALITY_DOMAIN_V4}/index.html"
  echo "IPv6 Reality 页面：${STATIC_SITE_DIR}/${REALITY_DOMAIN_V6}/index.html"
  read -rp "确认两个域名的页面准备完成后按 Enter 继续: "
  [[ -f "${STATIC_SITE_DIR}/${REALITY_DOMAIN_V4}/index.html" ]] || error "未找到 IPv4 Reality 页面"
  [[ -f "${STATIC_SITE_DIR}/${REALITY_DOMAIN_V6}/index.html" ]] || error "未找到 IPv6 Reality 页面"
fi

info "IPv4 地址:    $IPV4_ADDRESS"
info "IPv6 地址:    $IPV6_ADDRESS"
info "IPv4 Reality: $REALITY_DOMAIN_V4"
info "IPv6 Reality: $REALITY_DOMAIN_V6"
if [[ "$FALLBACK_MODE" == "proxy" ]]; then
  info "IPv4 回落:    $FALLBACK_ORIGIN_V4"
  info "IPv6 回落:    $FALLBACK_ORIGIN_V6"
fi
info "XHTTP Path:   $XHTTP_PATH"
echo ""
