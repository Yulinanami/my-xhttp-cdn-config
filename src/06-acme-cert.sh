# ==================================================
# 证书申请与复用
# ==================================================

info "[2/6] 申请 / 复用 SSL 证书"

curl https://get.acme.sh | sh
ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

acme.sh --set-default-ca --server letsencrypt

ACME_CERT_HOME="/root/.acme.sh/${REALITY_DOMAIN}_ecc"
ACME_CERT_CONF="${ACME_CERT_HOME}/${REALITY_DOMAIN}.conf"

have_existing_dual_cert() {
  [[ -f "$ACME_CERT_CONF" ]] || return 1

  local alt_line
  alt_line=$(grep "^Le_Alt=" "$ACME_CERT_CONF" 2>/dev/null || true)

  grep -Fq "Le_Domain='${REALITY_DOMAIN}'" "$ACME_CERT_CONF" || return 1
  [[ -n "$alt_line" && "$alt_line" == *"$CDN_DOMAIN"* ]] || return 1
  [[ -f "$ACME_CERT_HOME/fullchain.cer" ]] || return 1
  [[ -f "$ACME_CERT_HOME/${REALITY_DOMAIN}.key" ]] || return 1
  return 0
}

issue_dual_cert() {
  if [[ "$IP_CHOICE" == "2" ]]; then
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --listen-v6 --keylength ec-256 \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true"
  else
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --keylength ec-256 \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true"
  fi
}

if have_existing_dual_cert; then
  info "检测到已存在的双域名证书，跳过重新签发，直接复用"
else
  info "未检测到可复用的双域名证书，开始申请 (需要 80 端口空闲)..."
  set +e
  ISSUE_OUTPUT=$(issue_dual_cert 2>&1)
  ISSUE_CODE=$?
  set -e
  echo "$ISSUE_OUTPUT"
  if [[ $ISSUE_CODE -ne 0 ]]; then
    if echo "$ISSUE_OUTPUT" | grep -Eqi 'Domains not changed|Skipping\\. Next renewal time'; then
      warn "acme.sh 返回“Domains not changed”，视为已有证书可复用，继续执行"
    elif echo "$ISSUE_OUTPUT" | grep -Eqi 'rateLimit|too many certificates|Le_OrderFinalize'; then
      warn "Let's Encrypt 可能触发了签发频率限制；如果之前已签发过这组域名，请等待限流结束或直接复用现有证书"
      error "双域名证书申请失败"
    else
      error "双域名证书申请失败"
    fi
  fi
fi

echo ""

