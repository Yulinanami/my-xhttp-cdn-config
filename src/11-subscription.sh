# ==================================================
# 订阅文件与二维码输出
# ==================================================

SUB_CONF_DIR="/etc/xhttp-cdn"
SUB_TOKEN_FILE="${SUB_CONF_DIR}/sub_token"
install -d -m 700 "$SUB_CONF_DIR"
if [[ -f "$SUB_TOKEN_FILE" ]]; then
  SUB_TOKEN=$(tr -d '\r\n' < "$SUB_TOKEN_FILE")
else
  SUB_TOKEN=$(openssl rand -hex 16)
  echo "$SUB_TOKEN" > "$SUB_TOKEN_FILE"
  chmod 600 "$SUB_TOKEN_FILE"
fi

SUB_DIR="/usr/local/nginx/html/sub/${SUB_TOKEN}"
install -d -m 755 "$SUB_DIR"
cp "$USER_HOME/client-config.txt" "$SUB_DIR/v2rayn-raw.txt"
base64 "$USER_HOME/client-config.txt" | tr -d '\n' > "$SUB_DIR/v2rayn.txt"
cp "$USER_HOME/client-config-mihomo.yaml" "$SUB_DIR/mihomo.yaml"

SUB_DIRECT_DOMAIN="${REALITY_DOMAIN}"
V2RAYN_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/v2rayn.txt"
MIHOMO_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/mihomo.yaml"
V2RAYN_QR_FILE="${USER_HOME}/subscription-v2rayn.png"
MIHOMO_QR_FILE="${USER_HOME}/subscription-mihomo.png"
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
check_subscription_url "$SUB_DIRECT_DOMAIN" "/sub/${SUB_TOKEN}/mihomo.yaml" "$SUB_DIR/mihomo.yaml" "Mihomo(直连订阅)"
info "订阅链接自检通过"

cat > "$SUB_LINKS_FILE" << SUBLINKEOF
V2RayN / Shadowrocket 订阅:
$V2RAYN_SUB_URL

Mihomo 订阅:
$MIHOMO_SUB_URL

二维码 PNG 文件:
V2RayN / Shadowrocket: $V2RAYN_QR_FILE
Mihomo: $MIHOMO_QR_FILE
SUBLINKEOF

