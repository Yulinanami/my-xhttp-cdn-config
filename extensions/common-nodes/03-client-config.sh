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
  local node_file ech_block

  node_file=$(mktemp)
  cat > "$node_file" <<EOF
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

  ech_block=$(extract_ech_opts_block "$source_file")
  [[ -n "$ech_block" ]] && printf '%s\n' "$ech_block" >> "$node_file"

  cat >> "$node_file" <<EOF
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

  printf '%s' "$node_file"
}

append_mihomo_node() {
  local source_file="$1"
  local node_file="$2"
  local node_name="$3"
  local tmp_mihomo

  tmp_mihomo=$(mktemp)
  awk -v node_name="$node_name" -v node_file="$node_file" '
    $0 == "  - name: " node_name      { skip=1; next }
    skip && /^  - name: /             { skip=0 }
    skip && /^proxy-groups:/          { skip=0 }
    skip                              { next }

    /^proxy-groups:/ {
      while ((getline line < node_file) > 0) print line
      print ""
      inserted=1
      print
      next
    }

    { print }

    END {
      if (!inserted) {
        print ""
        while ((getline line < node_file) > 0) print line
      }
    }
  ' "$source_file" > "$tmp_mihomo"
  mv "$tmp_mihomo" "$source_file"
}

# 拆成单节点文件，便于按名称去重后分别追加
split_node_file() {
  local combined_file="$1"
  local node_name="$2"
  local out_file

  out_file=$(mktemp)
  awk -v node_name="$node_name" '
    $0 == "  - name: " node_name { in_node = 1; print; next }
    in_node && /^  - name: /     { exit }
    in_node && /^$/              { exit }
    in_node                      { print }
  ' "$combined_file" > "$out_file"
  printf '%s' "$out_file"
}

for MIHOMO_TARGET_FILE in "${MIHOMO_TARGET_FILES[@]}"; do
  COMBINED_FILE=$(build_common_nodes_block "$MIHOMO_TARGET_FILE")
  NODE_WS_FILE=$(split_node_file "$COMBINED_FILE" "$NODE_WS_NAME")
  NODE_HY2_FILE=$(split_node_file "$COMBINED_FILE" "$NODE_HY2_NAME")
  [[ -s "$NODE_WS_FILE" && -s "$NODE_HY2_FILE" ]] || error "生成 Mihomo 节点失败"
  append_mihomo_node "$MIHOMO_TARGET_FILE" "$NODE_WS_FILE" "$NODE_WS_NAME"
  append_mihomo_node "$MIHOMO_TARGET_FILE" "$NODE_HY2_FILE" "$NODE_HY2_NAME"
  rm -f "$COMBINED_FILE" "$NODE_WS_FILE" "$NODE_HY2_FILE"
done
