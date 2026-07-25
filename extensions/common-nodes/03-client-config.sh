# ==================================================
# 追加客户端节点
# ==================================================

NODE_XHTTP_H3_NAME="vless+xhttp+tls+h3 直连"
NODE_HY2_NAME="hysteria2 直连"

NODE_XHTTP_H3_TAG=$(rawurlencode "$NODE_XHTTP_H3_NAME")
NODE_HY2_TAG=$(rawurlencode "$NODE_HY2_NAME")

BASE_SERVER_URI=$(format_uri_host "$BASE_SERVER")

LINE_XHTTP_H3="vless://${UUID2}@${BASE_SERVER_URI}:${XHTTP_H3_PORT}?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h3&insecure=0&allowInsecure=0${ECH_PARAM:+&ech=${ECH_PARAM}}&type=xhttp&host=${CDN_DOMAIN}&path=$(rawurlencode "$XHTTP_PATH")&mode=auto${XHTTP_EXTRA:+&extra=${XHTTP_EXTRA}}#${NODE_XHTTP_H3_TAG}"
LINE_HY2="hysteria2://$(rawurlencode "$HY2_PASSWORD")@${BASE_SERVER_URI}:${HY2_PORT}/?sni=${REALITY_DOMAIN}&insecure=0#${NODE_HY2_TAG}"

sed -i "/#${NODE_XHTTP_H3_TAG}\$/d" "$V2RAYN_FILE"
sed -i "/#${NODE_HY2_TAG}\$/d" "$V2RAYN_FILE"
printf '%s\n%s\n' "$LINE_XHTTP_H3" "$LINE_HY2" >> "$V2RAYN_FILE"
chown "$(stat -c '%u:%g' "$USER_HOME")" "$V2RAYN_FILE"

build_common_nodes_block() {
  cat <<EOF
  - name: ${NODE_XHTTP_H3_NAME}
    type: vless
    server: "${BASE_SERVER}"
    port: ${XHTTP_H3_PORT}
    uuid: ${UUID2}
    udp: true
    flow: ""
    tls: true
    encryption: "${VLESSENC_ENCRYPTION}"
    network: xhttp
    alpn:
      - h3
    servername: ${CDN_DOMAIN}
    client-fingerprint: chrome
EOF

  if [[ -n "$ECH_PARAM" ]]; then
    cat <<'EOF'
    ech-opts:
      enable: true
      query-server-name: cloudflare-ech.com
EOF
  fi

  cat <<EOF
    xhttp-opts:
      host: ${CDN_DOMAIN}
      path: ${XHTTP_PATH}
      mode: auto
EOF

  if [[ -n "$XHTTP_EXTRA" ]]; then
    cat <<EOF
      x-padding-obfs-mode: true
      x-padding-key: "${XHTTP_PADDING_KEY}"
      x-padding-header: "${XHTTP_PADDING_HEADER}"
      x-padding-placement: "${XHTTP_PADDING_PLACEMENT}"
      x-padding-method: "${XHTTP_PADDING_METHOD}"
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
        h-keep-alive-period: 0
EOF
  fi

  cat <<EOF
  - name: ${NODE_HY2_NAME}
    type: hysteria2
    server: "${BASE_SERVER}"
    port: ${HY2_PORT}
    password: "${HY2_PASSWORD}"
    sni: ${REALITY_DOMAIN}
    alpn:
      - h3
EOF
}

update_mihomo_file() {
  local source_file="$1"
  local node_file tmp_file

  node_file=$(mktemp)
  tmp_file=$(mktemp)
  build_common_nodes_block > "$node_file"

  awk -v h3_name="$NODE_XHTTP_H3_NAME" \
      -v hy2_name="$NODE_HY2_NAME" \
      -v node_file="$node_file" '
    skip && !(/^  - name: / || /^proxy-groups:/) { next }
    skip { skip=0 }

    $0 == "  - name: " h3_name ||
    $0 == "  - name: " hy2_name {
      skip=1
      next
    }

    /^proxy-groups:/ {
      while ((getline line < node_file) > 0) print line
      print ""
      inserted=1
    }

    { print }

    END {
      if (!inserted) {
        print ""
        while ((getline line < node_file) > 0) print line
      }
    }
  ' "$source_file" > "$tmp_file"

  cat "$tmp_file" > "$source_file"
  rm -f "$node_file" "$tmp_file"
}

for target_file in "$MIHOMO_FULL_FILE" "$MIHOMO_NODES_FILE"; do
  update_mihomo_file "$target_file"
done
chown "$(stat -c '%u:%g' "$USER_HOME")" "$MIHOMO_FULL_FILE" "$MIHOMO_NODES_FILE"
