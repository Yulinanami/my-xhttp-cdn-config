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

read -rp "请输入 CDN-A 域名（上行，默认 ${DEFAULT_CDN_DOMAIN}）: " CDN_A
CDN_A=${CDN_A:-$DEFAULT_CDN_DOMAIN}
[[ -z "$CDN_A" ]] && error "CDN-A 域名不能为空"

read -rp "请输入 CDN-B 域名（下行 CDN，如 cdn-b.example.com）: " CDN_B
[[ -z "$CDN_B" ]] && error "CDN-B 域名不能为空"
if [[ "$CDN_B" == "$CDN_A" ]]; then
  warn "CDN-A 与 CDN-B 相同，将按同一域名处理"
fi

echo ""
echo -e "${YELLOW}[+] CDN-A / CDN-B 回落网站${NC}"
read -rp "请输入 CDN-A 回落网站 [默认 https://www.stanford.edu]: " CDN_A_FALLBACK_URL
CDN_A_FALLBACK_URL=${CDN_A_FALLBACK_URL:-https://www.stanford.edu}
read -rp "请输入 CDN-B 回落网站 [默认 https://www.harvard.edu]: " CDN_B_FALLBACK_URL
CDN_B_FALLBACK_URL=${CDN_B_FALLBACK_URL:-https://www.harvard.edu}

normalize_proxy_origin() {
  local url="$1"
  local scheme rest host

  [[ "$url" =~ ^https?:// ]] || url="https://${url}"
  scheme="${url%%://*}"
  rest="${url#*://}"
  host="${rest%%/*}"
  host="${host%%\?*}"
  host="${host%%\#*}"

  [[ -n "$host" ]] || return 1
  printf '%s://%s' "$scheme" "$host"
}

extract_host_from_url() {
  local url="$1"
  url="${url#*://}"
  url="${url%%/*}"
  printf '%s' "$url"
}

CDN_A_FALLBACK_ORIGIN=$(normalize_proxy_origin "$CDN_A_FALLBACK_URL") || error "CDN-A 回落网站格式无效"
CDN_B_FALLBACK_ORIGIN=$(normalize_proxy_origin "$CDN_B_FALLBACK_URL") || error "CDN-B 回落网站格式无效"
CDN_A_FALLBACK_HOST=$(extract_host_from_url "$CDN_A_FALLBACK_ORIGIN")
CDN_B_FALLBACK_HOST=$(extract_host_from_url "$CDN_B_FALLBACK_ORIGIN")

if [[ "$CDN_A_FALLBACK_ORIGIN" == "$CDN_B_FALLBACK_ORIGIN" ]]; then
  warn "CDN-A / CDN-B 回落网站相同，建议分别设置不同伪装站"
fi

info "Reality 域名: $REALITY_DOMAIN"
info "原 CDN 域名:  $DEFAULT_CDN_DOMAIN"
info "CDN-A 域名:   $CDN_A"
info "CDN-B 域名:   $CDN_B"
info "CDN-A 回落:    $CDN_A_FALLBACK_ORIGIN"
info "CDN-B 回落:    $CDN_B_FALLBACK_ORIGIN"
info "XHTTP Path:   $XHTTP_PATH"
echo ""
