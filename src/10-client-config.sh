# ==================================================
# 客户端配置生成
# ==================================================

info "[6/6] 生成客户端配置"
XHTTP_PATH_ENC=$(echo "$XHTTP_PATH" | sed 's|/|%2F|g')

EXTRA_2_PARAM=""
EXTRA_4_PARAM=""
EXTRA_TOP_PREFIX_ENC=""
EXTRA_TOP_SC_PREFIX_ENC=""
XHTTP_EXTRA_FIELD_ENC=""
MIHOMO_XPADDING_XHTTP_BLOCK=""
MIHOMO_XPADDING_DOWNLOAD_BLOCK=""
MIHOMO_SC_MIN_POSTS_BLOCK=""
MIHOMO_REUSE_KEEPALIVE_XHTTP=""
MIHOMO_REUSE_KEEPALIVE_DOWNLOAD=""
MIHOMO_ECH_PROXY_BLOCK=""
MIHOMO_ECH_DOWNLOAD_BLOCK=""

if [[ "$FEATURE_XPADDING" == true ]]; then
  XPAD_FIELDS_ENC="%22xPaddingObfsMode%22%3Atrue%2C%22xPaddingMethod%22%3A%22${XHTTP_PADDING_METHOD}%22%2C%22xPaddingPlacement%22%3A%22${XHTTP_PADDING_PLACEMENT}%22%2C%22xPaddingHeader%22%3A%22${XHTTP_PADDING_HEADER}%22%2C%22xPaddingKey%22%3A%22${XHTTP_PADDING_KEY}%22"
  XMUX_ENC="%22xmux%22%3A%7B%22maxConcurrency%22%3A%2216-32%22%2C%22cMaxReuseTimes%22%3A0%2C%22hMaxReusableSecs%22%3A%221800-3000%22%2C%22hKeepAlivePeriod%22%3A0%7D"
  XPAD_EXTRA_ENC="%7B${XPAD_FIELDS_ENC}%2C${XMUX_ENC}%7D"
  SC_MIN_POSTS_ENC="%22scMinPostsIntervalMs%22%3A30"

  EXTRA_2_PARAM="&extra=${XPAD_EXTRA_ENC}"
  EXTRA_4_PARAM="&extra=%7B${XPAD_FIELDS_ENC}%2C${SC_MIN_POSTS_ENC}%2C${XMUX_ENC}%7D"
  EXTRA_TOP_PREFIX_ENC="${XPAD_FIELDS_ENC}%2C${XMUX_ENC}%2C"
  EXTRA_TOP_SC_PREFIX_ENC="${XPAD_FIELDS_ENC}%2C${SC_MIN_POSTS_ENC}%2C${XMUX_ENC}%2C"
  XHTTP_EXTRA_FIELD_ENC="%2C%22extra%22%3A${XPAD_EXTRA_ENC}"

  MIHOMO_XPADDING_XHTTP_BLOCK=$(cat <<EOF

      x-padding-obfs-mode: true
      x-padding-key: "${XHTTP_PADDING_KEY}"
      x-padding-header: "${XHTTP_PADDING_HEADER}"
      x-padding-placement: "${XHTTP_PADDING_PLACEMENT}"
      x-padding-method: "${XHTTP_PADDING_METHOD}"
EOF
)
  MIHOMO_XPADDING_DOWNLOAD_BLOCK=$(cat <<EOF

        x-padding-obfs-mode: true
        x-padding-key: "${XHTTP_PADDING_KEY}"
        x-padding-header: "${XHTTP_PADDING_HEADER}"
        x-padding-placement: "${XHTTP_PADDING_PLACEMENT}"
        x-padding-method: "${XHTTP_PADDING_METHOD}"
EOF
)
  MIHOMO_SC_MIN_POSTS_BLOCK=$(cat <<EOF

      sc-min-posts-interval-ms: 30
EOF
)
  MIHOMO_REUSE_KEEPALIVE_XHTTP=$(cat <<EOF

        h-keep-alive-period: 0
EOF
)
  MIHOMO_REUSE_KEEPALIVE_DOWNLOAD=$(cat <<EOF

          h-keep-alive-period: 0
EOF
)
fi

if [[ "$CDN_ECH_ENABLED" == true ]]; then
  MIHOMO_ECH_PROXY_BLOCK=$(cat <<EOF

    ech-opts:
      enable: true
      query-server-name: cloudflare-ech.com
EOF
)
  MIHOMO_ECH_DOWNLOAD_BLOCK=$(cat <<EOF

        ech-opts:
          enable: true
          query-server-name: cloudflare-ech.com
EOF
)
fi

EXTRA_3="%7B${EXTRA_TOP_SC_PREFIX_ENC}%22downloadSettings%22%3A%7B%22address%22%3A%22${VPS_IP_ENC}%22%2C%22port%22%3A443%2C%22network%22%3A%22xhttp%22%2C%22security%22%3A%22reality%22%2C%22realitySettings%22%3A%7B%22show%22%3Afalse%2C%22serverName%22%3A%22${REALITY_DOMAIN}%22%2C%22fingerprint%22%3A%22chrome%22%2C%22shortId%22%3A%22${SHORT_ID}%22%2C%22publicKey%22%3A%22${PUBLIC_KEY}%22%7D%2C%22xhttpSettings%22%3A%7B%22host%22%3A%22%22%2C%22path%22%3A%22${XHTTP_PATH_ENC}%22%2C%22mode%22%3A%22auto%22${XHTTP_EXTRA_FIELD_ENC}%7D%7D%7D"

EXTRA_5="%7B${EXTRA_TOP_PREFIX_ENC}%22downloadSettings%22%3A%7B%22address%22%3A%22${CDN_DOMAIN}%22%2C%22port%22%3A443%2C%22network%22%3A%22xhttp%22%2C%22security%22%3A%22tls%22%2C%22tlsSettings%22%3A%7B%22serverName%22%3A%22${CDN_DOMAIN}%22%2C%22allowInsecure%22%3Afalse%2C%22alpn%22%3A%5B%22h2%22%5D%2C%22fingerprint%22%3A%22chrome%22${CDN_ECH_TLS_SETTINGS_EXTRA}%7D%2C%22xhttpSettings%22%3A%7B%22host%22%3A%22${CDN_DOMAIN}%22%2C%22path%22%3A%22${XHTTP_PATH_ENC}%22%2C%22mode%22%3A%22auto%22${XHTTP_EXTRA_FIELD_ENC}%7D%7D%7D"

cat > "$USER_HOME/client-config.txt" << CLIENTEOF
@@include templates/client-config.txt.tmpl
CLIENTEOF

cat > "$USER_HOME/client-config-mihomo.yaml" << MIHOMOEOF
@@include templates/mihomo.yaml.tmpl
MIHOMOEOF
