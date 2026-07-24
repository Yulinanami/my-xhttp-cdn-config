# ==================================================
# 追加客户端节点
# ==================================================

NODE_NAME="上行 xhttp+TLS+CDN-A | 下行 xhttp+TLS+CDN-B"
NODE_TAG="%E4%B8%8A%E8%A1%8C%20xhttp%2BTLS%2BCDN-A%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BTLS%2BCDN-B"

BASE_EXTRA_JSON=""
NESTED_EXTRA_FIELD=""
if [[ -n "$BASE_EXTRA_ENC" ]]; then
  BASE_EXTRA_JSON=$(urldecode "$BASE_EXTRA_ENC")
  NESTED_EXTRA_FIELD=",\"extra\":${BASE_EXTRA_JSON}"
fi

ECH_TLS_JSON=""
ECH_URI_PARAM=""
if [[ -n "$ECH_PARAM" ]]; then
  ECH_TLS_JSON=",\"echConfigList\":\"$(json_escape "$(urldecode "$ECH_PARAM")")\""
  ECH_URI_PARAM="&ech=${ECH_PARAM}"
fi

DOWNLOAD_SETTINGS_JSON="\"downloadSettings\":{\"address\":\"$(json_escape "$CDN_B")\",\"port\":443,\"network\":\"xhttp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"$(json_escape "$CDN_B")\",\"allowInsecure\":false,\"alpn\":[\"h2\"],\"fingerprint\":\"chrome\"${ECH_TLS_JSON}},\"xhttpSettings\":{\"host\":\"$(json_escape "$CDN_B")\",\"path\":\"$(json_escape "$XHTTP_PATH")\",\"mode\":\"auto\"${NESTED_EXTRA_FIELD}}}"

if [[ -n "$BASE_EXTRA_JSON" ]]; then
  EXTRA_JSON="${BASE_EXTRA_JSON%\}},${DOWNLOAD_SETTINGS_JSON}}"
else
  EXTRA_JSON="{${DOWNLOAD_SETTINGS_JSON}}"
fi
EXTRA_ENC=$(rawurlencode "$EXTRA_JSON")

NEW_V2RAYN_LINE="vless://${UUID2}@${CDN_A}:443?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_A}&fp=chrome&alpn=h2&insecure=0&allowInsecure=0${ECH_URI_PARAM}&type=xhttp&host=${CDN_A}&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_ENC}#${NODE_TAG}"

sed -i "/#${NODE_TAG}\$/d" "$V2RAYN_FILE"
printf '%s\n' "$NEW_V2RAYN_LINE" >> "$V2RAYN_FILE"

build_mihomo_node_block() {
  local source_file="$1"
  local base_node_file new_node_file tmp_mihomo

  base_node_file=$(mktemp)
  awk '
    /^  - name: xhttp\+TLS 双向 CDN$/ { in_node=1; print; next }
    in_node && (/^  - name: / || /^proxy-groups:/) { exit }
    in_node { print }
  ' "$source_file" > "$base_node_file"
  [[ -s "$base_node_file" ]] || error "未找到 Mihomo 的 xhttp+TLS 双向 CDN 节点: $source_file"

  new_node_file=$(mktemp)
  awk -v node_name="$NODE_NAME" -v cdn_a="$CDN_A" '
    /^  - name: xhttp\+TLS 双向 CDN$/ { print "  - name: " node_name; next }
    /^    server:/      { print "    server: " cdn_a; next }
    /^    servername:/  { print "    servername: " cdn_a; next }
    /^      host:/      { print "      host: " cdn_a; next }
    { print }
  ' "$base_node_file" > "$new_node_file"

  cat >> "$new_node_file" <<EOF
      download-settings:
        host: ${CDN_B}
        path: ${XHTTP_PATH}
        server: ${CDN_B}
        port: 443
        tls: true
        alpn:
          - h2
        servername: ${CDN_B}
        client-fingerprint: chrome
EOF

  if grep -q '^    ech-opts:' "$base_node_file"; then
    cat >> "$new_node_file" <<'EOF'
        ech-opts:
          enable: true
          query-server-name: cloudflare-ech.com
EOF
  fi

  awk '/^      x-padding-/ { sub(/^      /, "        "); print }' "$base_node_file" >> "$new_node_file"

  cat >> "$new_node_file" <<EOF
        reality-opts: { public-key: "" }
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"
EOF

  grep -q 'h-keep-alive-period:' "$base_node_file" && \
    echo "          h-keep-alive-period: 0" >> "$new_node_file"

  tmp_mihomo=$(mktemp)
  awk -v node_name="$NODE_NAME" -v node_file="$new_node_file" '
    $0 == "  - name: " node_name      { skip=1; next }
    skip && /^  - name: /             { skip=0 }
    skip && /^proxy-groups:/          { skip=0 }
    skip                              { next }

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
  ' "$source_file" > "$tmp_mihomo"
  chown "$(stat -c '%u:%g' "$USER_HOME")" "$tmp_mihomo"
  chmod 644 "$tmp_mihomo"
  mv "$tmp_mihomo" "$source_file"

  rm -f "$base_node_file" "$new_node_file"
}

for MIHOMO_TARGET_FILE in "${MIHOMO_TARGET_FILES[@]}"; do
  build_mihomo_node_block "$MIHOMO_TARGET_FILE"
done
