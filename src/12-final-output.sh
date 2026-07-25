# ==================================================
# 最终结果输出
# ==================================================

echo -e "\n${CYAN}[+] 部署完成${NC}\n"
echo -e "${YELLOW}[+] 服务端参数${NC}"
echo "Reality 域名:   $REALITY_DOMAIN"
echo "CDN 域名:       $CDN_DOMAIN"
if [[ "$FALLBACK_MODE" == "static" ]]; then
  echo "回落方式:       本地静态页面"
  echo "Reality 页面:   ${STATIC_SITE_DIR}/${REALITY_DOMAIN}"
  echo "CDN 页面:       ${STATIC_SITE_DIR}/${CDN_DOMAIN}"
else
  echo "回落方式:       Nginx 反向代理"
  echo "Reality 回落网站: $REALITY_FALLBACK_ORIGIN"
  echo "CDN 回落网站:    $CDN_FALLBACK_ORIGIN"
fi
echo "VPS IP:         $VPS_IP"
echo "UUID1 (Vision): $UUID1"
echo "UUID2 (XHTTP):  $UUID2"
echo "Public Key:     $PUBLIC_KEY"
echo "Private Key:    $PRIVATE_KEY"
echo "Short ID:       $SHORT_ID"
echo "Path:           $XHTTP_PATH"
echo "VLESS Enc(客户端): $VLESSENC_ENCRYPTION"
echo "VLESS Dec(服务端): $VLESSENC_DECRYPTION"
if [[ "$FEATURE_CDN_ECH" == true ]]; then
  if [[ "$CDN_ECH_ENABLED" == true ]]; then
    echo "CDN ECH:        已开启 (${CDN_ECH_QUERY})"
  else
    echo "CDN ECH:        未开启"
  fi
fi
echo ""
echo -e "\n${YELLOW}[+] 客户端节点，已保存到 $USER_HOME/client-config.txt${NC}"
cat "$USER_HOME/client-config.txt"
echo ""
echo -e "${YELLOW}[+] Mihomo 完整分流配置，已保存到 $USER_HOME/client-config-mihomo-full.yaml${NC}"
echo -e "${YELLOW}[+] Mihomo 纯节点配置，已保存到 $USER_HOME/client-config-mihomo-nodes.yaml${NC}"
echo ""
echo -e "${YELLOW}[+] 订阅链接（Ctrl Shift + C 复制）${NC}"
echo "V2RayN / Shadowrocket 订阅: $V2RAYN_SUB_URL"
echo "Mihomo 完整分流订阅: $MIHOMO_FULL_SUB_URL"
echo "Mihomo 纯节点订阅: $MIHOMO_NODES_SUB_URL"
info "订阅链接已保存到 $SUB_LINKS_FILE"
echo ""

if command -v qrencode >/dev/null 2>&1; then
  output_subscription_qr "V2RayN / Shadowrocket" "$V2RAYN_SUB_URL" "$V2RAYN_QR_FILE"
  output_subscription_qr "Mihomo 完整分流" "$MIHOMO_FULL_SUB_URL" "$MIHOMO_FULL_QR_FILE"
  output_subscription_qr "Mihomo 纯节点" "$MIHOMO_NODES_SUB_URL" "$MIHOMO_NODES_QR_FILE"
else
  warn "未检测到 qrencode，已跳过订阅二维码输出"
fi

echo -e "${YELLOW}[+] Cloudflare 缓存绕过表达式${NC}"
echo "  (http.host eq \"${CDN_DOMAIN}\") or (http.request.uri.path contains \"${XHTTP_PATH}\")"
