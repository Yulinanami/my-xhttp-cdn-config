# ==================================================
# 初始化说明与交互参数
# ==================================================

info "检测到系统: $PRETTY_NAME"

if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(eval echo "~$SUDO_USER")
else
  USER_HOME=$(getent passwd 1000 2>/dev/null | cut -d: -f6 || true)
fi
[[ -z "$USER_HOME" || ! -d "$USER_HOME" ]] && USER_HOME="/root"

echo -e "\n${CYAN}[+] XHTTP + CDN 一键部署脚本${NC}\n"
echo -e "${GREEN}[+] 推荐系统: Ubuntu 24.04 / Debian 12${NC}"
echo -e "${YELLOW}[+] 前置条件 (请确认已在 Cloudflare 完成):${NC}"
echo "  1. Reality 域名 DNS → 仅 DNS (灰色云朵)"
echo "  2. CDN 域名 DNS    → 代理开启 (橙色云朵)"
echo "  3. SSL/TLS 加密    → 完全(严格)"
echo "  4. 网络 → gRPC     → 已开启"
echo "  5. 缓存规则         → 部署完成后根据提示配置 (建议)"
if [[ "$FEATURE_CDN_ECH" == true ]]; then
  echo "  6. Edge Certificates → 如需使用 ECH 请先开启"
fi
echo ""

read -rp "请输入 Reality 域名 (如 reality.example.com): " REALITY_DOMAIN
[[ -z "$REALITY_DOMAIN" ]] && error "域名不能为空"

read -rp "请输入 CDN 域名 (如 cdn.example.com): " CDN_DOMAIN
[[ -z "$CDN_DOMAIN" ]] && error "域名不能为空"

echo ""
echo "  1) IPv4"
echo "  2) IPv6"
read -rp "请选择 IP 类型 [1/2] (默认 1): " IP_CHOICE
IP_CHOICE=${IP_CHOICE:-1}

echo ""
echo -e "${YELLOW}[+] 主动探测回落网站（建议用 VPS 所在地区选择当地大学官网，伪装能力更好）${NC}"
read -rp "请输入 Reality 域名回落网站 [默认 https://www.stanford.edu]: " REALITY_FALLBACK_URL
REALITY_FALLBACK_URL=${REALITY_FALLBACK_URL:-https://www.stanford.edu}
read -rp "请输入 CDN 域名回落网站 [默认 https://www.harvard.edu]: " CDN_FALLBACK_URL
CDN_FALLBACK_URL=${CDN_FALLBACK_URL:-https://www.harvard.edu}

if [[ "$FEATURE_XPADDING" == true ]]; then
  echo ""
  echo -e "${YELLOW}[+] xpadding 自定义填充${NC}"
  read -rp "请输入 xpadding Header 名 [默认 Referer]: " XHTTP_PADDING_HEADER
  XHTTP_PADDING_HEADER=${XHTTP_PADDING_HEADER:-Referer}
  read -rp "请输入 xpadding 参数名 [默认 x_padding]: " XHTTP_PADDING_KEY
  XHTTP_PADDING_KEY=${XHTTP_PADDING_KEY:-x_padding}
fi

if [[ "$FEATURE_CDN_ECH" == true ]]; then
  echo ""
  echo -e "${YELLOW}[+] CDN ECH（作用于 CDN-TLS）${NC}"
  read -rp "是否启用 CDN ECH [y/N]: " CDN_ECH_INPUT
  case "$CDN_ECH_INPUT" in
    [Yy]|[Yy][Ee][Ss]) CDN_ECH_ENABLED=true ;;
    *) CDN_ECH_ENABLED=false ;;
  esac
  if [[ "$CDN_ECH_ENABLED" == true ]]; then
    CDN_ECH_QUERY="cloudflare-ech.com+https://223.5.5.5/dns-query"
  else
    CDN_ECH_QUERY=""
  fi
fi

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
  echo "${scheme}://${host}"
}

extract_host_from_url() {
  local url="$1"
  url="${url#*://}"
  url="${url%%/*}"
  echo "$url"
}

REALITY_FALLBACK_ORIGIN=$(normalize_proxy_origin "$REALITY_FALLBACK_URL") || error "Reality 回落网站格式无效"
CDN_FALLBACK_ORIGIN=$(normalize_proxy_origin "$CDN_FALLBACK_URL") || error "CDN 回落网站格式无效"
REALITY_FALLBACK_HOST=$(extract_host_from_url "$REALITY_FALLBACK_ORIGIN")
CDN_FALLBACK_HOST=$(extract_host_from_url "$CDN_FALLBACK_ORIGIN")
[[ -z "$REALITY_FALLBACK_HOST" ]] && error "Reality 回落网站格式无效"
[[ -z "$CDN_FALLBACK_HOST" ]] && error "CDN 回落网站格式无效"

if [[ "$REALITY_FALLBACK_URL" != "$REALITY_FALLBACK_ORIGIN" ]]; then
  warn "Reality 回落网站已忽略路径部分，实际反代目标: $REALITY_FALLBACK_ORIGIN"
fi
if [[ "$CDN_FALLBACK_URL" != "$CDN_FALLBACK_ORIGIN" ]]; then
  warn "CDN 回落网站已忽略路径部分，实际反代目标: $CDN_FALLBACK_ORIGIN"
fi

echo ""
info "Reality: $REALITY_DOMAIN"
info "CDN:     $CDN_DOMAIN"
info "Reality 回落网站: $REALITY_FALLBACK_ORIGIN"
info "CDN 回落网站:     $CDN_FALLBACK_ORIGIN"
if [[ "$FEATURE_XPADDING" == true ]]; then
  info "xpadding Header:   $XHTTP_PADDING_HEADER"
  info "xpadding Key:      $XHTTP_PADDING_KEY"
fi
if [[ "$FEATURE_CDN_ECH" == true ]]; then
  if [[ "$CDN_ECH_ENABLED" == true ]]; then
    info "CDN ECH:          已开启"
  else
    info "CDN ECH:          未开启"
  fi
fi
echo ""
