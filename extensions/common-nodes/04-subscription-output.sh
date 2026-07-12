# ==================================================
# 订阅文件与二维码输出
# ==================================================

SUB_CONF_DIR="/etc/xhttp-cdn"
SUB_TOKEN_FILE="${SUB_CONF_DIR}/sub_token"
install -d -m 700 "$SUB_CONF_DIR"

if [[ -f "$SUB_TOKEN_FILE" ]]; then
  SUB_TOKEN=$(tr -d '\r\n' < "$SUB_TOKEN_FILE")
else
  warn "未找到订阅 token，已只更新本地客户端文件"
  SUB_TOKEN=""
fi

if [[ -n "$SUB_TOKEN" ]]; then
  SUB_DIR="/usr/local/nginx/html/sub/${SUB_TOKEN}"
  install -d -m 755 "$SUB_DIR"
  cp "$V2RAYN_FILE" "$SUB_DIR/v2rayn-raw.txt"
  base64 "$V2RAYN_FILE" | tr -d '\n' > "$SUB_DIR/v2rayn.txt"
  cp "$MIHOMO_FULL_FILE" "$SUB_DIR/mihomo-full.yaml"
  cp "$MIHOMO_NODES_FILE" "$SUB_DIR/mihomo-nodes.yaml"
  info "订阅文件已更新: $SUB_DIR"

  SUB_DIRECT_DOMAIN="${REALITY_DOMAIN}"
  V2RAYN_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/v2rayn.txt"
  MIHOMO_FULL_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/mihomo-full.yaml"
  MIHOMO_NODES_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/mihomo-nodes.yaml"
  V2RAYN_QR_FILE="${USER_HOME}/subscription-v2rayn.png"
  MIHOMO_FULL_QR_FILE="${USER_HOME}/subscription-mihomo-full.png"
  MIHOMO_NODES_QR_FILE="${USER_HOME}/subscription-mihomo-nodes.png"
  SUB_LINKS_FILE="${USER_HOME}/subscription-links.txt"

  print_subscription_qr() {
    local label="$1"
    local url="$2"

    command -v qrencode >/dev/null 2>&1 || return 1

    echo -e "${YELLOW}[+] ${label} 订阅二维码（手机可直接扫描导入）${NC}"
    qrencode -t ANSIUTF8 -m 1 "$url"
    echo ""
  }

  save_subscription_qr_png() {
    local url="$1"
    local output_file="$2"

    command -v qrencode >/dev/null 2>&1 || return 1

    qrencode -o "$output_file" -s 8 -m 2 "$url"
  }

  check_subscription_url() {
    local domain="$1"
    local path="$2"
    local expected_file="$3"
    local label="$4"
    local tmp_body tmp_head http_code

    tmp_body=$(mktemp)
    tmp_head=$(mktemp)

    http_code=$(curl -k -sS --resolve "${domain}:443:127.0.0.1" \
      -D "$tmp_head" -o "$tmp_body" -w "%{http_code}" "https://${domain}${path}" || true)

    if [[ "$http_code" != "200" ]]; then
      warn "${label} 订阅自检失败，HTTP 状态码: ${http_code}"
      cat "$tmp_head" || true
      rm -f "$tmp_body" "$tmp_head"
      error "${label} 订阅链接不可用，请检查 Nginx / Xray / 域名配置"
    fi

    if ! cmp -s "$expected_file" "$tmp_body"; then
      rm -f "$tmp_body" "$tmp_head"
      error "${label} 订阅自检失败，返回内容与落盘文件不一致"
    fi

    rm -f "$tmp_body" "$tmp_head"
  }

  info "验证订阅链接..."
  check_subscription_url "$SUB_DIRECT_DOMAIN" "/sub/${SUB_TOKEN}/v2rayn.txt" "$SUB_DIR/v2rayn.txt" "V2RayN(直连订阅)"
  check_subscription_url "$SUB_DIRECT_DOMAIN" "/sub/${SUB_TOKEN}/mihomo-full.yaml" "$SUB_DIR/mihomo-full.yaml" "Mihomo(完整分流订阅)"
  check_subscription_url "$SUB_DIRECT_DOMAIN" "/sub/${SUB_TOKEN}/mihomo-nodes.yaml" "$SUB_DIR/mihomo-nodes.yaml" "Mihomo(纯节点订阅)"
  info "订阅链接自检通过"

  cat > "$SUB_LINKS_FILE" << SUBLINKEOF
V2RayN / Shadowrocket 订阅:
$V2RAYN_SUB_URL

Mihomo 完整分流订阅:
$MIHOMO_FULL_SUB_URL

Mihomo 纯节点订阅:
$MIHOMO_NODES_SUB_URL

二维码 PNG 文件:
V2RayN / Shadowrocket: $V2RAYN_QR_FILE
Mihomo 完整分流: $MIHOMO_FULL_QR_FILE
Mihomo 纯节点: $MIHOMO_NODES_QR_FILE
SUBLINKEOF

  echo ""
  echo -e "${YELLOW}[+] 订阅链接（Ctrl Shift + C 复制）${NC}"
  echo "V2RayN / Shadowrocket 订阅: $V2RAYN_SUB_URL"
  echo "Mihomo 完整分流订阅: $MIHOMO_FULL_SUB_URL"
  echo "Mihomo 纯节点订阅: $MIHOMO_NODES_SUB_URL"
  info "订阅链接已保存到 $SUB_LINKS_FILE"

  if command -v qrencode >/dev/null 2>&1; then
    save_subscription_qr_png "$V2RAYN_SUB_URL" "$V2RAYN_QR_FILE" && \
      info "V2RayN / Shadowrocket 订阅二维码 PNG 已保存到 $V2RAYN_QR_FILE"
    save_subscription_qr_png "$MIHOMO_FULL_SUB_URL" "$MIHOMO_FULL_QR_FILE" && \
      info "Mihomo 完整分流订阅二维码 PNG 已保存到 $MIHOMO_FULL_QR_FILE"
    save_subscription_qr_png "$MIHOMO_NODES_SUB_URL" "$MIHOMO_NODES_QR_FILE" && \
      info "Mihomo 纯节点订阅二维码 PNG 已保存到 $MIHOMO_NODES_QR_FILE"
    echo ""
    print_subscription_qr "V2RayN / Shadowrocket" "$V2RAYN_SUB_URL"
    print_subscription_qr "Mihomo 完整分流" "$MIHOMO_FULL_SUB_URL"
    print_subscription_qr "Mihomo 纯节点" "$MIHOMO_NODES_SUB_URL"
  else
    warn "未检测到 qrencode，已跳过订阅二维码输出"
  fi
else
  echo ""
  echo -e "${CYAN}[+] 扩展模式添加完成${NC}"
  echo "新增节点: $NODE_WS_NAME"
  echo "新增节点: $NODE_HY2_NAME"
  echo "V2RayN 节点文件: $V2RAYN_FILE"
  echo "Mihomo 完整分流配置: $MIHOMO_FULL_FILE"
  echo "Mihomo 纯节点配置: $MIHOMO_NODES_FILE"
  echo ""
  warn "未找到订阅 token，无法输出订阅链接/二维码，请先运行主脚本"
fi

info "客户端更新订阅后即可看到新节点"