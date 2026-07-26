# ==================================================
# 追加客户端节点
# ==================================================

NODE_XHTTP_H3_NAME="xhttp+TLS+H3"
NODE_H2_H3_NAME="上行 xhttp+TLS+H2 | 下行 xhttp+TLS+H3"
NODE_H3_H2_NAME="上行 xhttp+TLS+H3 | 下行 xhttp+TLS+H2"

BASE_SERVER_URI=$(format_uri_host "$BASE_SERVER")
XHTTP_PATH_ENC=$(rawurlencode "$XHTTP_PATH")

if [[ -n "$XHTTP_EXTRA" ]]; then
  BASE_EXTRA_JSON=$(urldecode "$XHTTP_EXTRA")
fi

build_download_extra() {
  local address="$1"
  local port="$2"
  local alpn="$3"
  local download

  download="\"downloadSettings\":{\"address\":\"$(json_escape "$address")\",\"port\":${port},\"network\":\"xhttp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"$(json_escape "$CDN_DOMAIN")\",\"allowInsecure\":false,\"alpn\":[\"${alpn}\"],\"fingerprint\":\"chrome\"${ECH_PARAM:+,\"echConfigList\":\"$(json_escape "$(urldecode "$ECH_PARAM")")\"}},\"xhttpSettings\":{\"host\":\"$(json_escape "$CDN_DOMAIN")\",\"path\":\"$(json_escape "$XHTTP_PATH")\",\"mode\":\"auto\"${BASE_EXTRA_JSON:+,\"extra\":${BASE_EXTRA_JSON}}}}"

  if [[ -n "$BASE_EXTRA_JSON" ]]; then
    rawurlencode "${BASE_EXTRA_JSON%\}},${download}}"
  else
    rawurlencode "{${download}}"
  fi
}

sed -i \
  -e "/#$(rawurlencode "$NODE_XHTTP_H3_NAME")\$/d" \
  -e "/#$(rawurlencode "$NODE_H2_H3_NAME")\$/d" \
  -e "/#$(rawurlencode "$NODE_H3_H2_NAME")\$/d" \
  "$V2RAYN_FILE"
printf '%s\n%s\n%s\n' \
  "vless://${UUID2}@${BASE_SERVER_URI}:${XHTTP_H3_PORT}?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h3&insecure=0&allowInsecure=0${ECH_PARAM:+&ech=${ECH_PARAM}}&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH_ENC}&mode=auto${XHTTP_EXTRA:+&extra=${XHTTP_EXTRA}}#$(rawurlencode "$NODE_XHTTP_H3_NAME")" \
  "vless://${UUID2}@${CDN_DOMAIN}:443?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h2&insecure=0&allowInsecure=0${ECH_PARAM:+&ech=${ECH_PARAM}}&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH_ENC}&mode=auto&extra=$(build_download_extra "$BASE_SERVER" "$XHTTP_H3_PORT" "h3")#$(rawurlencode "$NODE_H2_H3_NAME")" \
  "vless://${UUID2}@${BASE_SERVER_URI}:${XHTTP_H3_PORT}?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h3&insecure=0&allowInsecure=0${ECH_PARAM:+&ech=${ECH_PARAM}}&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH_ENC}&mode=auto&extra=$(build_download_extra "$CDN_DOMAIN" "443" "h2")#$(rawurlencode "$NODE_H3_H2_NAME")" >> "$V2RAYN_FILE"
chown "$(stat -c '%u:%g' "$USER_HOME")" "$V2RAYN_FILE"

write_xhttp_node() {
  local name="$1"
  local server="$2"
  local port="$3"
  local alpn="$4"
  local download_server="${5:-}"
  local download_port="${6:-}"
  local download_alpn="${7:-}"

  cat <<EOF
  - name: ${name}
    type: vless
    server: "${server}"
    port: ${port}
    uuid: ${UUID2}
    udp: true
    flow: ""
    tls: true
    encryption: "${VLESSENC_ENCRYPTION}"
    network: xhttp
    alpn:
      - ${alpn}
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
EOF
  fi

  cat <<'EOF'
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
        h-keep-alive-period: 0
EOF

  if [[ -n "$download_server" ]]; then
    cat <<EOF
      download-settings:
        host: ${CDN_DOMAIN}
        path: ${XHTTP_PATH}
        server: "${download_server}"
        port: ${download_port}
        tls: true
        alpn:
          - ${download_alpn}
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

    if [[ -n "$XHTTP_EXTRA" ]]; then
      cat <<EOF
        x-padding-obfs-mode: true
        x-padding-key: "${XHTTP_PADDING_KEY}"
        x-padding-header: "${XHTTP_PADDING_HEADER}"
        x-padding-placement: "${XHTTP_PADDING_PLACEMENT}"
        x-padding-method: "${XHTTP_PADDING_METHOD}"
EOF
    fi

    cat <<'EOF'
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"
          h-keep-alive-period: 0
EOF
  fi
}

build_quic_nodes_block() {
  write_xhttp_node "$NODE_XHTTP_H3_NAME" "$BASE_SERVER" "$XHTTP_H3_PORT" "h3"
  write_xhttp_node "$NODE_H2_H3_NAME" "$CDN_DOMAIN" "443" "h2" "$BASE_SERVER" "$XHTTP_H3_PORT" "h3"
  write_xhttp_node "$NODE_H3_H2_NAME" "$BASE_SERVER" "$XHTTP_H3_PORT" "h3" "$CDN_DOMAIN" "443" "h2"
}

update_mihomo_file() {
  local source_file="$1"
  local node_file
  local tmp_file

  node_file=$(mktemp)
  tmp_file=$(mktemp)
  build_quic_nodes_block > "$node_file"

  awk -v h3_name="$NODE_XHTTP_H3_NAME" \
      -v h2_h3_name="$NODE_H2_H3_NAME" \
      -v h3_h2_name="$NODE_H3_H2_NAME" \
      -v node_file="$node_file" '
    skip && !(/^  - name: / || /^proxy-groups:/) { next }
    skip { skip=0 }

    $0 == "  - name: " h3_name ||
    $0 == "  - name: " h2_h3_name ||
    $0 == "  - name: " h3_h2_name {
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
