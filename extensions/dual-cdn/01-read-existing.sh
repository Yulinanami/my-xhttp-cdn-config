# ==================================================
# 读取已有节点参数
# ==================================================

echo -e "\n${CYAN}[+] 添加扩展模式：上行 CDN-A | 下行 CDN-B${NC}\n"
echo -e "${YELLOW}[+] 前置条件${NC}"
echo "  1. 已经成功运行主脚本"
echo "  2. CDN-A / CDN-B 域名 DNS → 代理开启（橙色云朵）"
echo "  3. CDN-A / CDN-B 所在 Cloudflare 区域已开启 gRPC"
echo "  4. SSL/TLS 加密 → 完全（严格）"
echo ""

find_client_files
info "读取已有客户端配置: $USER_HOME"

BASE_LINE=$(grep -F '#xhttp%2Btls%20%E5%8F%8C%E5%90%91CDN' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$BASE_LINE" ]] || error "未找到 xhttp+TLS 双向 CDN 节点，无法自动派生 CDN-A 参数"

REALITY_LINE=$(grep -F '#reality%2Bvision' "$V2RAYN_FILE" | head -n1 | tr -d '\r' || true)
[[ -n "$REALITY_LINE" ]] || error "未找到 reality+vision 节点，无法读取 Reality 域名"

UUID2=$(extract_uri_user "$BASE_LINE")
DEFAULT_CDN_DOMAIN=$(get_query_param "$BASE_LINE" "host" || true)
[[ -n "$DEFAULT_CDN_DOMAIN" ]] || DEFAULT_CDN_DOMAIN=$(get_query_param "$BASE_LINE" "sni" || true)
[[ -n "$DEFAULT_CDN_DOMAIN" ]] || DEFAULT_CDN_DOMAIN=$(extract_uri_server "$BASE_LINE")
XHTTP_PATH=$(get_query_param "$BASE_LINE" "path" || true)
VLESSENC_ENCRYPTION=$(get_query_param "$BASE_LINE" "encryption" || true)
BASE_EXTRA_ENC=$(get_query_param "$BASE_LINE" "extra" || true)
ECH_PARAM=$(get_query_param "$BASE_LINE" "ech" || true)
REALITY_DOMAIN=$(get_query_param "$REALITY_LINE" "sni" || true)
VPS_SERVER=$(extract_uri_server "$REALITY_LINE")

[[ -n "$UUID2" ]] || error "读取 UUID2 失败"
[[ -n "$DEFAULT_CDN_DOMAIN" ]] || error "读取默认 CDN 域名失败"
[[ -n "$XHTTP_PATH" ]] || error "读取 XHTTP Path 失败"
[[ -n "$VLESSENC_ENCRYPTION" ]] || error "读取 VLESS Encryption 失败"
[[ -n "$REALITY_DOMAIN" ]] || error "读取 Reality 域名失败"
[[ -n "$VPS_SERVER" ]] || error "读取 VPS 地址失败"

if [[ -n "$ECH_PARAM" ]]; then
  read -rp "是否复用原 CDN 节点的 ECH [y/N]: "
  [[ "${REPLY,,}" == "y" ]] || ECH_PARAM=""
fi

[[ -f /etc/xhttp-cdn/fallback.env ]] || error "未找到主脚本回落配置，请重新运行主脚本"
# shellcheck disable=SC1090
. /etc/xhttp-cdn/fallback.env

[[ "$FALLBACK_MODE" == "proxy" || "$FALLBACK_MODE" == "static" ]] || error "主脚本回落方式无效，请重新运行主脚本"

read -rp "请输入 CDN-A 域名（上行，默认 ${DEFAULT_CDN_DOMAIN}）: " CDN_A
CDN_A=${CDN_A:-$DEFAULT_CDN_DOMAIN}
[[ -z "$CDN_A" ]] && error "CDN-A 域名不能为空"
[[ "$CDN_A" =~ ^[A-Za-z0-9.-]+$ && "$CDN_A" != "." && "$CDN_A" != ".." ]] || error "CDN-A 域名格式无效"
[[ "$CDN_A" != "$REALITY_DOMAIN" ]] || error "CDN-A 域名不能与 Reality 域名相同"

read -rp "请输入 CDN-B 域名（下行 CDN，如 cdn-b.example.com）: " CDN_B
[[ -z "$CDN_B" ]] && error "CDN-B 域名不能为空"
[[ "$CDN_B" =~ ^[A-Za-z0-9.-]+$ && "$CDN_B" != "." && "$CDN_B" != ".." ]] || error "CDN-B 域名格式无效"
[[ "$CDN_B" != "$REALITY_DOMAIN" ]] || error "CDN-B 域名不能与 Reality 域名相同"
if [[ "$CDN_B" == "$CDN_A" ]]; then
  warn "CDN-A 与 CDN-B 相同，将按同一域名处理"
fi

if [[ "$FALLBACK_MODE" == "proxy" ]]; then
  [[ -n "$CDN_FALLBACK_ORIGIN" && -n "$CDN_FALLBACK_HOST" ]] || error "主脚本 CDN 回落网站为空，请重新运行主脚本"

  if [[ "$CDN_A" == "$DEFAULT_CDN_DOMAIN" ]]; then
    CDN_A_FALLBACK_ORIGIN="$CDN_FALLBACK_ORIGIN"
    CDN_A_FALLBACK_HOST="$CDN_FALLBACK_HOST"
  else
    read -rp "请输入 ${CDN_A} 的回落网站: " CDN_A_FALLBACK_ORIGIN
    CDN_A_FALLBACK_ORIGIN=$(normalize_proxy_origin "$CDN_A_FALLBACK_ORIGIN") || error "CDN-A 回落网站格式无效"
    CDN_A_FALLBACK_HOST=${CDN_A_FALLBACK_ORIGIN#*://}
    [[ "$CDN_A_FALLBACK_ORIGIN" != "$REALITY_FALLBACK_ORIGIN" && "$CDN_A_FALLBACK_ORIGIN" != "$CDN_FALLBACK_ORIGIN" ]] || error "不同入口域名不能共用回落网站"
  fi

  if [[ "$CDN_B" == "$CDN_A" ]]; then
    CDN_B_FALLBACK_ORIGIN="$CDN_A_FALLBACK_ORIGIN"
    CDN_B_FALLBACK_HOST="$CDN_A_FALLBACK_HOST"
  elif [[ "$CDN_B" == "$DEFAULT_CDN_DOMAIN" ]]; then
    CDN_B_FALLBACK_ORIGIN="$CDN_FALLBACK_ORIGIN"
    CDN_B_FALLBACK_HOST="$CDN_FALLBACK_HOST"
  else
    read -rp "请输入 ${CDN_B} 的回落网站: " CDN_B_FALLBACK_ORIGIN
    CDN_B_FALLBACK_ORIGIN=$(normalize_proxy_origin "$CDN_B_FALLBACK_ORIGIN") || error "CDN-B 回落网站格式无效"
    CDN_B_FALLBACK_HOST=${CDN_B_FALLBACK_ORIGIN#*://}
    [[ "$CDN_B_FALLBACK_ORIGIN" != "$REALITY_FALLBACK_ORIGIN" && "$CDN_B_FALLBACK_ORIGIN" != "$CDN_FALLBACK_ORIGIN" ]] || error "不同入口域名不能共用回落网站"
    [[ "$CDN_B_FALLBACK_ORIGIN" != "$CDN_A_FALLBACK_ORIGIN" ]] || error "CDN-A 和 CDN-B 不能共用回落网站"
  fi
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

  prepare_static_site "$CDN_A"
  [[ "$CDN_B" == "$CDN_A" ]] || prepare_static_site "$CDN_B"
  echo "CDN-A 页面：${STATIC_SITE_DIR}/${CDN_A}/index.html"
  echo "CDN-B 页面：${STATIC_SITE_DIR}/${CDN_B}/index.html"
  read -rp "确认各域名页面准备完成后按 Enter 继续: "
  [[ -f "${STATIC_SITE_DIR}/${CDN_A}/index.html" ]] || error "未找到 CDN-A 页面"
  [[ -f "${STATIC_SITE_DIR}/${CDN_B}/index.html" ]] || error "未找到 CDN-B 页面"
fi

info "Reality 域名: $REALITY_DOMAIN"
info "原 CDN 域名:  $DEFAULT_CDN_DOMAIN"
info "CDN-A 域名:   $CDN_A"
info "CDN-B 域名:   $CDN_B"
if [[ "$FALLBACK_MODE" == "proxy" ]]; then
  info "CDN-A 回落:   $CDN_A_FALLBACK_ORIGIN"
  info "CDN-B 回落:   $CDN_B_FALLBACK_ORIGIN"
fi
info "XHTTP Path:   $XHTTP_PATH"
echo ""
