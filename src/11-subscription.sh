# ==================================================
# 订阅文件与二维码输出
# ==================================================

SUB_TOKEN_FILE="/etc/xhttp-cdn/sub_token"
install -d -m 700 /etc/xhttp-cdn
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
cp "$USER_HOME/client-config-mihomo-full.yaml" "$SUB_DIR/mihomo-full.yaml"
cp "$USER_HOME/client-config-mihomo-nodes.yaml" "$SUB_DIR/mihomo-nodes.yaml"

V2RAYN_SUB_URL="https://${REALITY_DOMAIN}/sub/${SUB_TOKEN}/v2rayn.txt"
MIHOMO_FULL_SUB_URL="https://${REALITY_DOMAIN}/sub/${SUB_TOKEN}/mihomo-full.yaml"
MIHOMO_NODES_SUB_URL="https://${REALITY_DOMAIN}/sub/${SUB_TOKEN}/mihomo-nodes.yaml"

V2RAYN_QR_FILE="${USER_HOME}/subscription-v2rayn.png"
MIHOMO_FULL_QR_FILE="${USER_HOME}/subscription-mihomo-full.png"
MIHOMO_NODES_QR_FILE="${USER_HOME}/subscription-mihomo-nodes.png"
SUB_LINKS_FILE="${USER_HOME}/subscription-links.txt"

output_subscription_qr() {
  local label="$1" url="$2" file="$3"
  qrencode -o "$file" -s 8 -m 2 "$url"
  chown "$(stat -c '%u:%g' "$USER_HOME")" "$file"
  echo -e "${YELLOW}[+] ${label}${NC}"
  qrencode -t ANSIUTF8 -m 1 "$url"
}

check_subscription() {
  cmp -s "$2" <(curl -kfsS --resolve "${REALITY_DOMAIN}:443:127.0.0.1" \
    "https://${REALITY_DOMAIN}$1") ||
    error "订阅自检失败: $1"
}

info "验证订阅链接..."
check_subscription "/sub/${SUB_TOKEN}/v2rayn.txt" "$SUB_DIR/v2rayn.txt"
check_subscription "/sub/${SUB_TOKEN}/mihomo-full.yaml" "$SUB_DIR/mihomo-full.yaml"
check_subscription "/sub/${SUB_TOKEN}/mihomo-nodes.yaml" "$SUB_DIR/mihomo-nodes.yaml"
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
chown "$(stat -c '%u:%g' "$USER_HOME")" "$SUB_LINKS_FILE"
