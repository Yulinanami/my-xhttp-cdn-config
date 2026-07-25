# ==================================================
# 订阅文件与二维码输出
# ==================================================

update_subscriptions() {
  local token_file="/etc/xhttp-cdn/sub_token"
  [[ -f "$token_file" ]] || {
    warn "未找到订阅 token，仅更新本地客户端文件"
    return
  }

  local token sub_dir v2rayn_url mihomo_full_url mihomo_nodes_url
  token=$(tr -d '\r\n' < "$token_file")
  sub_dir="/usr/local/nginx/html/sub/${token}"
  v2rayn_url="https://${REALITY_DOMAIN}/sub/${token}/v2rayn.txt"
  mihomo_full_url="https://${REALITY_DOMAIN}/sub/${token}/mihomo-full.yaml"
  mihomo_nodes_url="https://${REALITY_DOMAIN}/sub/${token}/mihomo-nodes.yaml"

  install -d -m 755 "$sub_dir"
  cp "$V2RAYN_FILE" "$sub_dir/v2rayn-raw.txt"
  base64 "$V2RAYN_FILE" | tr -d '\n' > "$sub_dir/v2rayn.txt"
  cp "$MIHOMO_FULL_FILE" "$sub_dir/mihomo-full.yaml"
  cp "$MIHOMO_NODES_FILE" "$sub_dir/mihomo-nodes.yaml"

  check_subscription() {
    cmp -s "$2" <(curl -kfsS --resolve "${REALITY_DOMAIN}:443:127.0.0.1" \
      "https://${REALITY_DOMAIN}$1") ||
      error "订阅自检失败: $1"
  }

  check_subscription "/sub/${token}/v2rayn.txt" "$sub_dir/v2rayn.txt"
  check_subscription "/sub/${token}/mihomo-full.yaml" "$sub_dir/mihomo-full.yaml"
  check_subscription "/sub/${token}/mihomo-nodes.yaml" "$sub_dir/mihomo-nodes.yaml"

  cat > "$USER_HOME/subscription-links.txt" << SUBLINKEOF
V2RayN / Shadowrocket 订阅:
$v2rayn_url

Mihomo 完整分流订阅:
$mihomo_full_url

Mihomo 纯节点订阅:
$mihomo_nodes_url

二维码 PNG 文件:
V2RayN / Shadowrocket: $USER_HOME/subscription-v2rayn.png
Mihomo 完整分流: $USER_HOME/subscription-mihomo-full.png
Mihomo 纯节点: $USER_HOME/subscription-mihomo-nodes.png
SUBLINKEOF
  chown "$(stat -c '%u:%g' "$USER_HOME")" "$USER_HOME/subscription-links.txt"

  echo -e "${YELLOW}[+] 订阅链接（Ctrl Shift + C 复制）${NC}"
  echo "V2RayN / Shadowrocket: $v2rayn_url"
  echo "Mihomo 完整分流: $mihomo_full_url"
  echo "Mihomo 纯节点: $mihomo_nodes_url"
  info "订阅文件已更新: $sub_dir"

  if command -v qrencode >/dev/null 2>&1; then
    output_qr() {
      local label="$1" url="$2" file="$3"
      qrencode -o "$file" -s 8 -m 2 "$url"
      chown "$(stat -c '%u:%g' "$USER_HOME")" "$file"
      echo -e "${YELLOW}[+] ${label}${NC}"
      qrencode -t ANSIUTF8 -m 1 "$url"
    }
    output_qr "V2RayN / Shadowrocket" "$v2rayn_url" "$USER_HOME/subscription-v2rayn.png"
    output_qr "Mihomo 完整分流" "$mihomo_full_url" "$USER_HOME/subscription-mihomo-full.png"
    output_qr "Mihomo 纯节点" "$mihomo_nodes_url" "$USER_HOME/subscription-mihomo-nodes.png"
  else
    warn "未检测到 qrencode，已跳过订阅二维码输出"
  fi
}

update_subscriptions

CACHE_BYPASS_RULE="(http.host eq \"${DEFAULT_CDN_DOMAIN}\")"
for domain in "$CDN_A" "$CDN_B"; do
  [[ "$CACHE_BYPASS_RULE" == *"\"${domain}\""* ]] ||
    CACHE_BYPASS_RULE+=" or (http.host eq \"${domain}\")"
done
CACHE_BYPASS_RULE+=" or (http.request.uri.path contains \"${XHTTP_PATH}\")"

echo ""
echo -e "${YELLOW}[+] 建议配置缓存绕过规则:${NC}"
echo "  ${CACHE_BYPASS_RULE}"
echo ""
info "客户端更新订阅后即可看到新节点"
