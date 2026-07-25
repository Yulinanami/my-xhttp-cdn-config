# ==================================================
# 初始化说明与交互参数
# ==================================================

info "检测到系统: $PRETTY_NAME"

if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
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
[[ "$REALITY_DOMAIN" =~ ^[A-Za-z0-9.-]+$ && "$REALITY_DOMAIN" != "." && "$REALITY_DOMAIN" != ".." ]] || error "Reality 域名格式无效"

read -rp "请输入 CDN 域名 (如 cdn.example.com): " CDN_DOMAIN
[[ -z "$CDN_DOMAIN" ]] && error "域名不能为空"
[[ "$CDN_DOMAIN" =~ ^[A-Za-z0-9.-]+$ && "$CDN_DOMAIN" != "." && "$CDN_DOMAIN" != ".." ]] || error "CDN 域名格式无效"
[[ "$REALITY_DOMAIN" != "$CDN_DOMAIN" ]] || error "Reality 域名和 CDN 域名不能相同"

echo ""
echo "  1) IPv4"
echo "  2) IPv6"
read -rp "请选择 IP 类型 [1/2] (默认 1): " IP_CHOICE
IP_CHOICE=${IP_CHOICE:-1}

normalize_proxy_origin() {
  local url="$1"
  [[ "$url" =~ ^https?:// ]] || url="https://${url}"
  [[ "$url" =~ ^(https?)://([^/?#]+) ]] || return 1
  printf '%s://%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

echo ""
echo -e "${YELLOW}[+] 主动探测回落方式${NC}"
echo "  1) Nginx 反向代理网站（默认）"
echo "  2) 使用自己的静态页面"
read -rp "请选择回落方式 [1/2] (默认 1): " FALLBACK_CHOICE

case "${FALLBACK_CHOICE:-1}" in
  1)
    FALLBACK_MODE="proxy"
    read -rp "请输入 Reality 域名回落网站 [默认 https://www.stanford.edu]: " REALITY_FALLBACK_ORIGIN
    REALITY_FALLBACK_ORIGIN=$(normalize_proxy_origin "${REALITY_FALLBACK_ORIGIN:-https://www.stanford.edu}") ||
      error "Reality 回落网站格式无效"
    read -rp "请输入 CDN 域名回落网站 [默认 https://www.harvard.edu]: " CDN_FALLBACK_ORIGIN
    CDN_FALLBACK_ORIGIN=$(normalize_proxy_origin "${CDN_FALLBACK_ORIGIN:-https://www.harvard.edu}") ||
      error "CDN 回落网站格式无效"
    [[ "$REALITY_FALLBACK_ORIGIN" != "$CDN_FALLBACK_ORIGIN" ]] ||
      error "Reality 域名和 CDN 域名不能共用同一个回落网站"
    REALITY_FALLBACK_HOST=${REALITY_FALLBACK_ORIGIN#*://}
    CDN_FALLBACK_HOST=${CDN_FALLBACK_ORIGIN#*://}
    ;;
  2)
    FALLBACK_MODE="static"
    STATIC_SITE_DIR="${USER_HOME}/dist"
    for domain in "$REALITY_DOMAIN" "$CDN_DOMAIN"; do
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
        info "已生成 ${STATIC_SITE_DIR}/${domain}/index.html"
      fi
      chown "$(stat -c '%u:%g' "$USER_HOME")" \
        "${STATIC_SITE_DIR}/${domain}" \
        "${STATIC_SITE_DIR}/${domain}/index.html"
    done
    echo ""
    echo "Reality 页面：${STATIC_SITE_DIR}/${REALITY_DOMAIN}/index.html"
    echo "CDN 页面：    ${STATIC_SITE_DIR}/${CDN_DOMAIN}/index.html"
    echo "可用 SingleFile 抓取网页后分别上传。"
    read -rp "确认两个域名的页面准备完成后按 Enter 继续: "
    [[ -f "${STATIC_SITE_DIR}/${REALITY_DOMAIN}/index.html" ]] || error "未找到 Reality 域名页面"
    [[ -f "${STATIC_SITE_DIR}/${CDN_DOMAIN}/index.html" ]] || error "未找到 CDN 域名页面"
    ;;
  *)
    error "回落方式只能选择 1 或 2"
    ;;
esac

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

echo ""
info "Reality: $REALITY_DOMAIN"
info "CDN:     $CDN_DOMAIN"
if [[ "$FALLBACK_MODE" == "static" ]]; then
  info "回落方式: 本地静态页面"
else
  info "回落方式: Nginx 反向代理"
  info "Reality 回落网站: $REALITY_FALLBACK_ORIGIN"
  info "CDN 回落网站:     $CDN_FALLBACK_ORIGIN"
fi
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
