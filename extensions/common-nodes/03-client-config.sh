# ==================================================
# 追加客户端节点
# ==================================================

NODE_WS_NAME="vless+ws+tls+CDN"
NODE_HY2_NAME="hysteria2 直连"
NODE_WS_TAG=$(rawurlencode "$NODE_WS_NAME")
NODE_HY2_TAG=$(rawurlencode "$NODE_HY2_NAME")

WS_PATH_ENC=$(rawurlencode "$WS_PATH")
HY2_PASSWORD_ENC=$(rawurlencode "$HY2_PASSWORD")
HY2_SERVER_URI=$(format_uri_host "$BASE_SERVER")

WS_ECH_URI_PARAM=""
[[ -n "$CDN_ECH_PARAM" ]] && WS_ECH_URI_PARAM="&ech=${CDN_ECH_PARAM}"

LINE_WS="vless://${UUID2}@${CDN_DOMAIN}:443?encryption=none&security=tls&sni=${CDN_DOMAIN}&fp=chrome&insecure=0&allowInsecure=0${WS_ECH_URI_PARAM}&type=ws&host=${CDN_DOMAIN}&path=${WS_PATH_ENC}#${NODE_WS_TAG}"
LINE_HY2="hysteria2://${HY2_PASSWORD_ENC}@${HY2_SERVER_URI}:${HY2_PORT}/?sni=${REALITY_DOMAIN}&insecure=0#${NODE_HY2_TAG}"

sed -i "/#${NODE_WS_TAG}\$/d" "$V2RAYN_FILE"
sed -i "/#${NODE_HY2_TAG}\$/d" "$V2RAYN_FILE"
printf '%s\n%s\n' "$LINE_WS" "$LINE_HY2" >> "$V2RAYN_FILE"
chown "$(stat -c '%u:%g' "$USER_HOME")" "$V2RAYN_FILE"

# 从已有 双向CDN 节点同步 ech-opts（若启用了 ECH）
extract_ech_opts_block() {
  local source_file="$1"

  awk '
    /^  - name: xhttp\+TLS 双向 CDN/ { in_node = 1; next }
    in_node && /^  - name: /         { exit }
    in_node && /^    ech-opts:/      { in_ech = 1; print; next }
    in_ech && /^      /              { print; next }
    in_ech                           { exit }
  ' "$source_file"
}

build_common_nodes_block() {
  local source_file="$1"

  cat <<EOF
  - name: ${NODE_WS_NAME}
    type: vless
    server: ${CDN_DOMAIN}
    port: 443
    uuid: ${UUID2}
    udp: true
    flow: ""
    tls: true
    network: ws
    servername: ${CDN_DOMAIN}
    client-fingerprint: chrome
EOF

  extract_ech_opts_block "$source_file"

  cat <<EOF
    ws-opts:
      path: ${WS_PATH}
      headers:
        Host: ${CDN_DOMAIN}

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
  build_common_nodes_block "$source_file" > "$node_file"

  awk -v ws_name="$NODE_WS_NAME" -v hy2_name="$NODE_HY2_NAME" -v node_file="$node_file" '
    skip && !(/^  - name: / || /^proxy-groups:/) { next }
    skip { skip=0 }

    $0 == "  - name: " ws_name || $0 == "  - name: " hy2_name {
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
