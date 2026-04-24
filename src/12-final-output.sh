# ==================================================
# 最终结果输出
# ==================================================

echo -e "\n${CYAN}[+] 部署完成${NC}\n"
echo -e "${YELLOW}[+] 服务端参数${NC}"
echo "Reality 域名:   $REALITY_DOMAIN"
echo "CDN 域名:       $CDN_DOMAIN"
echo "Reality 回落网站: $REALITY_FALLBACK_ORIGIN"
echo "CDN 回落网站:    $CDN_FALLBACK_ORIGIN"
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
echo -e "${YELLOW}[+] Mihomo 配置文件，已保存到 $USER_HOME/client-config-mihomo.yaml${NC}"
cat "$USER_HOME/client-config-mihomo.yaml"
echo ""
info "V2rayN 请导入 $USER_HOME/client-config.txt"
info "Mihomo 请导入 $USER_HOME/client-config-mihomo.yaml"
echo ""
echo -e "${YELLOW}[+] 订阅链接（Ctrl Shift + C 复制）${NC}"
echo "V2RayN / Shadowrocket 订阅: $V2RAYN_SUB_URL"
echo "Mihomo 订阅: $MIHOMO_SUB_URL"
info "订阅链接已保存到 $SUB_LINKS_FILE"
info "订阅链接默认使用直连域名，适合客户端首次导入"
echo ""

if command -v qrencode >/dev/null 2>&1; then
  save_subscription_qr_png "$V2RAYN_SUB_URL" "$V2RAYN_QR_FILE" && \
    info "V2RayN / Shadowrocket 订阅二维码 PNG 已保存到 $V2RAYN_QR_FILE"
  save_subscription_qr_png "$MIHOMO_SUB_URL" "$MIHOMO_QR_FILE" && \
    info "Mihomo 订阅二维码 PNG 已保存到 $MIHOMO_QR_FILE"
  echo ""
  print_subscription_qr "V2RayN / Shadowrocket" "$V2RAYN_SUB_URL"
  print_subscription_qr "Mihomo" "$MIHOMO_SUB_URL"
else
  warn "未检测到 qrencode，已跳过订阅二维码输出"
fi

echo -e "${YELLOW}[+] 建议: 在 Cloudflare 配置缓存规则绕过 XHTTP 路径${NC}"
echo "  Cloudflare → 缓存 → Cache Rules → 创建缓存规则"
echo "  选择「自定义筛选表达式」→ 点击「编辑表达式」→ 输入:"
echo ""
echo "  (http.host eq \"${CDN_DOMAIN}\") or (http.request.uri.path contains \"${XHTTP_PATH}\")"
echo ""
echo "  缓存资格设置为「绕过缓存」→ 部署"
echo "  详细步骤请参考仓库的 docs/1.环境配置.md 文档"
