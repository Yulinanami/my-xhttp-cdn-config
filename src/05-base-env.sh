# ==================================================
# 基础环境安装
# ==================================================

info "[1/6] 安装基础环境"

pkg_update

if [[ "$OS_ID" == "alpine" ]]; then
  pkg_install bash ca-certificates
  update-ca-certificates >/dev/null 2>&1 || true
fi

command -v curl    >/dev/null 2>&1 || pkg_install curl
command -v sudo    >/dev/null 2>&1 || pkg_install sudo
command -v socat   >/dev/null 2>&1 || pkg_install socat
command -v wget    >/dev/null 2>&1 || pkg_install wget
command -v tar     >/dev/null 2>&1 || pkg_install tar
command -v openssl >/dev/null 2>&1 || pkg_install openssl
if ! command -v qrencode >/dev/null 2>&1; then
  info "安装二维码工具 qrencode..."
  if [[ "$OS_ID" == "alpine" ]]; then
    QR_PACKAGE="libqrencode-tools"
  else
    QR_PACKAGE="qrencode"
  fi
  if ! pkg_install "$QR_PACKAGE"; then
    warn "qrencode 安装失败，将跳过二维码输出"
  fi
fi

if ! command -v crontab >/dev/null 2>&1; then
  case "$OS_ID" in
    debian|ubuntu|opensuse*|sles)
      pkg_install cron
      ;;
    centos|rhel|almalinux|rocky|ol|amzn|fedora|alpine)
      pkg_install cronie
      if [[ "$SERVICE_TYPE" == "openrc" ]]; then
        rc-update add crond default >/dev/null 2>&1 || true
        rc-service crond start >/dev/null 2>&1 || true
      else
        systemctl enable --now crond 2>/dev/null || true
      fi
      ;;
  esac
fi

info "安装 Xray..."
install_xray
export PATH="/usr/local/bin:$PATH"

info "生成参数..."
UUID1=$(xray uuid)
UUID2=$(xray uuid)
KEY_OUTPUT=$(xray x25519 2>&1)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | awk -F': ' '{print $2}' | tr -d '[:space:]')
[[ -z "$PRIVATE_KEY" ]] && error "未能提取 Private Key，xray x25519 输出: $KEY_OUTPUT"
[[ -z "$PUBLIC_KEY" ]] && error "未能提取 Public Key，xray x25519 输出: $KEY_OUTPUT"
SHORT_ID=$(echo "$UUID1" | tr -d '-' | cut -c1-8)
XHTTP_PATH="/$(echo "$UUID2" | tr -d '-' | cut -c1-8)"

XHTTP_PADDING_PLACEMENT="queryInHeader"
XHTTP_PADDING_METHOD="tokenish"
XRAY_XHTTP_PADDING_JSON=""
CDN_ECH_URI_PARAM=""
CDN_ECH_TLS_SETTINGS_EXTRA=""

if [[ "$FEATURE_XPADDING" == true ]]; then
  XRAY_XHTTP_PADDING_JSON=$(cat <<EOF
,
                    "xPaddingObfsMode": true,
                    "xPaddingKey": "${XHTTP_PADDING_KEY}",
                    "xPaddingHeader": "${XHTTP_PADDING_HEADER}",
                    "xPaddingPlacement": "${XHTTP_PADDING_PLACEMENT}",
                    "xPaddingMethod": "${XHTTP_PADDING_METHOD}"
EOF
)
fi

if [[ "$CDN_ECH_ENABLED" == true ]]; then
  CDN_ECH_QUERY_ENC=$(echo "$CDN_ECH_QUERY" | sed -e 's/%/%25/g' -e 's/+/%2B/g' -e 's/:/%3A/g' -e 's/\//%2F/g')
  CDN_ECH_URI_PARAM="&ech=${CDN_ECH_QUERY_ENC}"
  CDN_ECH_TLS_SETTINGS_EXTRA="%2C%22echConfigList%22%3A%22${CDN_ECH_QUERY_ENC}%22"
fi

info "生成 VLESS Encryption 密钥..."
VLESSENC_OUTPUT=$(xray vlessenc 2>&1)
if [[ $? -ne 0 ]] || ! echo "$VLESSENC_OUTPUT" | grep -qi "encryption"; then
  error "VLESS Encryption 密钥生成失败，请确保 Xray 版本支持 vlessenc。输出: $VLESSENC_OUTPUT"
fi
VLESSENC_ENCRYPTION=$(echo "$VLESSENC_OUTPUT" | awk '/ML-KEM/{found=1} found && /"encryption"/{print; exit}' | awk -F'"' '{print $4}')
VLESSENC_DECRYPTION=$(echo "$VLESSENC_OUTPUT" | awk '/ML-KEM/{found=1} found && /"decryption"/{print; exit}' | awk -F'"' '{print $4}')
[[ -z "$VLESSENC_ENCRYPTION" ]] && error "未能提取 ML-KEM-768 Encryption Key，xray vlessenc 输出: $VLESSENC_OUTPUT"
[[ -z "$VLESSENC_DECRYPTION" ]] && error "未能提取 ML-KEM-768 Decryption Key，xray vlessenc 输出: $VLESSENC_OUTPUT"
if [[ "$IP_CHOICE" == "2" ]]; then
  VPS_IP=$(curl -6 -s --max-time 5 ip.sb)
  [[ -z "$VPS_IP" ]] && error "无法获取 IPv6 地址"
  VPS_IP_URI="[${VPS_IP}]"
  VPS_IP_ENC=$(echo "$VPS_IP" | sed 's/:/%3A/g')
else
  VPS_IP=$(curl -4 -s --max-time 5 ip.sb)
  [[ -z "$VPS_IP" ]] && error "无法获取 IPv4 地址"
  VPS_IP_URI="${VPS_IP}"
  VPS_IP_ENC="${VPS_IP}"
fi

info "UUID1 (Vision): $UUID1"
info "UUID2 (XHTTP):  $UUID2"
info "Private Key:    $PRIVATE_KEY"
info "Public Key:     $PUBLIC_KEY"
info "Short ID:       $SHORT_ID"
info "Path:           $XHTTP_PATH"
info "VPS IP:         $VPS_IP"
info "VLESS Enc:      已启用 (防 CDN 中间人)"
echo ""
