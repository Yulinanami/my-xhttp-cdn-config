# ==================================================
# 追加客户端节点
# ==================================================

NODE_V4_UP_NAME="上行 xhttp+Reality IPv4 | 下行 xhttp+Reality IPv6"
NODE_V6_UP_NAME="上行 xhttp+Reality IPv6 | 下行 xhttp+Reality IPv4"
NODE_V4_UP_TAG="%E4%B8%8A%E8%A1%8C%20xhttp%2BReality%20IPv4%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BReality%20IPv6"
NODE_V6_UP_TAG="%E4%B8%8A%E8%A1%8C%20xhttp%2BReality%20IPv6%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BReality%20IPv4"

BASE_EXTRA_JSON=""
NESTED_EXTRA_FIELD=""
if [[ -n "$BASE_EXTRA_ENC" ]]; then
  BASE_EXTRA_JSON=$(urldecode "$BASE_EXTRA_ENC")
  NESTED_EXTRA_FIELD=",\"extra\":${BASE_EXTRA_JSON}"
fi

build_reality_download_extra() {
  local download_ip="$1"
  local download_domain="$2"
  local download_json extra_json

  download_json="\"downloadSettings\":{\"address\":\"$(json_escape "$download_ip")\",\"port\":443,\"network\":\"xhttp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"serverName\":\"$(json_escape "$download_domain")\",\"fingerprint\":\"chrome\",\"shortId\":\"$(json_escape "$SHORT_ID")\",\"publicKey\":\"$(json_escape "$PUBLIC_KEY")\"},\"xhttpSettings\":{\"host\":\"\",\"path\":\"$(json_escape "$XHTTP_PATH")\",\"mode\":\"auto\"${NESTED_EXTRA_FIELD}}}"

  if [[ -n "$BASE_EXTRA_JSON" ]]; then
    extra_json="${BASE_EXTRA_JSON%\}},${download_json}}"
  else
    extra_json="{${download_json}}"
  fi

  rawurlencode "$extra_json"
}

EXTRA_V4_DOWN=$(build_reality_download_extra "$IPV4_ADDRESS" "$REALITY_DOMAIN_V4")
EXTRA_V6_DOWN=$(build_reality_download_extra "$IPV6_ADDRESS" "$REALITY_DOMAIN_V6")

LINE_V4_UP="vless://${UUID2}@${IPV4_URI}:443?encryption=${VLESSENC_ENCRYPTION}&security=reality&sni=${REALITY_DOMAIN_V4}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_V6_DOWN}#${NODE_V4_UP_TAG}"
LINE_V6_UP="vless://${UUID2}@${IPV6_URI}:443?encryption=${VLESSENC_ENCRYPTION}&security=reality&sni=${REALITY_DOMAIN_V6}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_V4_DOWN}#${NODE_V6_UP_TAG}"

sed -i "/#${NODE_V4_UP_TAG}\$/d" "$V2RAYN_FILE"
sed -i "/#${NODE_V6_UP_TAG}\$/d" "$V2RAYN_FILE"
printf '%s\n%s\n' "$LINE_V4_UP" "$LINE_V6_UP" >> "$V2RAYN_FILE"

build_download_settings_block() {
  local download_ip="$1"
  local download_domain="$2"
  local base_node_file="$3"

  cat <<EOF
      download-settings:
        path: ${XHTTP_PATH}
        server: ${download_ip}
        port: 443
        tls: true
        alpn:
          - h2
        servername: ${download_domain}
        client-fingerprint: chrome
EOF

  awk '/^      x-padding-/ { sub(/^      /, "        "); print }' "$base_node_file"

  cat <<EOF
        reality-opts:
          public-key: ${PUBLIC_KEY}
          short-id: ${SHORT_ID}
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"
EOF

  grep -q 'h-keep-alive-period:' "$base_node_file" && \
    echo "          h-keep-alive-period: 0"
}

build_mihomo_node_block() {
  local node_name="$1"
  local upload_ip="$2"
  local download_ip="$3"
  local upload_domain="$4"
  local download_domain="$5"
  local source_file="$6"
  local base_node_file new_node_file

  base_node_file=$(mktemp)
  awk '
    /^  - name: xhttp\+Reality 上下行不分离/ { in_node=1; print; next }
    in_node && (/^  - name: / || /^proxy-groups:/) { exit }
    in_node { print }
  ' "$source_file" > "$base_node_file"
  [[ -s "$base_node_file" ]] || error "未找到 Mihomo 的 xhttp+Reality 上下行不分离节点: $source_file"

  new_node_file=$(mktemp)
  awk -v node_name="$node_name" -v upload_ip="$upload_ip" -v upload_domain="$upload_domain" '
    /^  - name: xhttp\+Reality 上下行不分离/ { print "  - name: " node_name; next }
    /^    server:/ { print "    server: " upload_ip; next }
    /^    servername:/ { print "    servername: " upload_domain; next }
    { print }
  ' "$base_node_file" > "$new_node_file"

  build_download_settings_block "$download_ip" "$download_domain" "$base_node_file" >> "$new_node_file"
  rm -f "$base_node_file"

  printf '%s' "$new_node_file"
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
  chown "$(stat -c '%u:%g' "$USER_HOME")" "$tmp_mihomo"
  chmod 644 "$tmp_mihomo"
  mv "$tmp_mihomo" "$source_file"
}

for MIHOMO_TARGET_FILE in "${MIHOMO_TARGET_FILES[@]}"; do
  NODE_V4_UP_FILE=$(build_mihomo_node_block "$NODE_V4_UP_NAME" "$IPV4_ADDRESS" "$IPV6_ADDRESS" "$REALITY_DOMAIN_V4" "$REALITY_DOMAIN_V6" "$MIHOMO_TARGET_FILE")
  NODE_V6_UP_FILE=$(build_mihomo_node_block "$NODE_V6_UP_NAME" "$IPV6_ADDRESS" "$IPV4_ADDRESS" "$REALITY_DOMAIN_V6" "$REALITY_DOMAIN_V4" "$MIHOMO_TARGET_FILE")
  append_mihomo_node "$MIHOMO_TARGET_FILE" "$NODE_V4_UP_FILE" "$NODE_V4_UP_NAME"
  append_mihomo_node "$MIHOMO_TARGET_FILE" "$NODE_V6_UP_FILE" "$NODE_V6_UP_NAME"
  rm -f "$NODE_V4_UP_FILE" "$NODE_V6_UP_FILE"
done
