# ==================================================
# 证书与 Nginx
# ==================================================

command -v acme.sh >/dev/null 2>&1 || error "未找到 acme.sh，请先运行主脚本"
command -v nginx >/dev/null 2>&1 || error "未找到 nginx，请先运行主脚本"

ACME_CERT_HOME="/root/.acme.sh/${REALITY_DOMAIN}_ecc"
ACME_CERT_CONF="${ACME_CERT_HOME}/${REALITY_DOMAIN}.conf"
ACME_LISTEN_ARGS=()
[[ "$VPS_SERVER" == \[*\] ]] && ACME_LISTEN_ARGS=(--listen-v6)
NGINX_CONF="/etc/nginx/nginx.conf"
[[ -f "$NGINX_CONF" ]] || error "未找到 $NGINX_CONF"

DUAL_CDN_STATE_FILE="/etc/xhttp-cdn/dual-cdn-domains"
DUAL_IP_STATE_FILE="/etc/xhttp-cdn/dual-ip-domains"
install -d -m 700 /etc/xhttp-cdn

PREV_DUAL_CDN_DOMAINS=()
if [[ -f "$DUAL_CDN_STATE_FILE" ]]; then
  mapfile -t PREV_DUAL_CDN_DOMAINS < "$DUAL_CDN_STATE_FILE"
fi

CERT_DOMAINS=()
add_cert_domain() {
  if [[ -n "$1" && " ${CERT_DOMAINS[*]} " != *" $1 "* ]]; then
    CERT_DOMAINS+=("$1")
  fi
}

add_cert_domain "$REALITY_DOMAIN"
add_cert_domain "$DEFAULT_CDN_DOMAIN"
add_cert_domain "$CDN_A"
add_cert_domain "$CDN_B"
if [[ -f "$DUAL_IP_STATE_FILE" ]]; then
  while IFS= read -r domain; do
    add_cert_domain "$domain"
  done < "$DUAL_IP_STATE_FILE"
fi

ACME_DOMAIN_ARGS=()
for domain in "${CERT_DOMAINS[@]}"; do
  ACME_DOMAIN_ARGS+=(-d "$domain")
done

cert_has_all_domains() {
  [[ -f "$ACME_CERT_CONF" ]] || return 1
  [[ -f "$ACME_CERT_HOME/fullchain.cer" ]] || return 1
  [[ -f "$ACME_CERT_HOME/${REALITY_DOMAIN}.key" ]] || return 1

  local cert_domains domain
  cert_domains=$(openssl x509 -in "$ACME_CERT_HOME/fullchain.cer" -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^,[:space:]]*' | sed 's/^DNS://' || true)

  for domain in "${CERT_DOMAINS[@]}"; do
    grep -Fxq "$domain" <<< "$cert_domains" || return 1
  done
  return 0
}

if cert_has_all_domains; then
  info "检测到证书已包含所需域名，跳过重新签发"
else
  info "申请 / 更新包含 CDN-A、CDN-B 的证书..."
  if ! ISSUE_OUTPUT=$(acme.sh --issue "${ACME_DOMAIN_ARGS[@]}" \
      --standalone "${ACME_LISTEN_ARGS[@]}" --keylength ec-256 \
      --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
      --post-hook "${NGINX_START_CMD} 2>/dev/null || true" 2>&1); then
    grep -Eqi 'Domains not changed|Skipping\. Next renewal time' <<< "$ISSUE_OUTPUT" || {
      echo "$ISSUE_OUTPUT"
      error "包含 CDN-A / CDN-B 的证书申请失败"
    }
  fi
  echo "$ISSUE_OUTPUT"
fi

info "安装证书..."
acme.sh --install-cert -d "$REALITY_DOMAIN" --ecc \
  --key-file /etc/ssl/private/private.key \
  --fullchain-file /etc/ssl/private/fullchain.cer \
  --reloadcmd "${NGINX_RESTART_CMD}"

append_cdn_block() {
  local domain="$1"
  local fallback_origin="$2"
  local fallback_host="$3"

  cat <<EOF
    server {
        listen       8003 ssl;
        http2        on;
        server_name  ${domain};

        ssl_certificate /etc/ssl/private/fullchain.cer;
        ssl_certificate_key /etc/ssl/private/private.key;

        location / {
EOF

  if [[ "$FALLBACK_MODE" == "static" ]]; then
    cat <<EOF
            root ${STATIC_SITE_DIR}/${domain};
            index index.html;
            try_files \$uri \$uri/ /index.html;
EOF
  else
    cat <<EOF
            proxy_pass ${fallback_origin};
            proxy_ssl_server_name on;
            proxy_ssl_name ${fallback_host};
            proxy_redirect http://${fallback_host}/ https://\$host/;
            proxy_redirect https://${fallback_host}/ https://\$host/;
            proxy_set_header Host ${fallback_host};
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
EOF
  fi

  cat <<EOF
        }

        location ${XHTTP_PATH} {
            grpc_pass 127.0.0.1:8001;
            grpc_set_header Host                  \$host;
            grpc_set_header X-Real-IP             \$real_client_ip;
            grpc_set_header Forwarded             \$proxy_add_forwarded;
            grpc_set_header X-Forwarded-For       \$proxy_add_x_forwarded_for;
            grpc_set_header X-Forwarded-Proto     \$scheme;
        }
    }
EOF
}

remove_nginx_server_block() {
  local domain="$1"
  local config="$2"
  local output
  output=$(mktemp)

  awk -v domain="$domain" '
    function count_braces(line, i, c) {
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "{") depth++
        if (c == "}") depth--
      }
    }

    !in_server && /^[[:space:]]*server[[:space:]]*\{/ {
      in_server = 1
      depth = 0
      hit = 0
      block = $0 ORS
      count_braces($0)
      next
    }

    in_server {
      block = block $0 ORS
      if ($0 ~ /^[[:space:]]*server_name[[:space:]]/ && index($0, domain)) hit = 1
      count_braces($0)
      if (depth == 0) {
        if (!hit) printf "%s", block
        in_server = 0
        block = ""
      }
      next
    }

    { print }
  ' "$config" > "$output"
  cat "$output" > "$config"
  rm -f "$output"
}

tmp_nginx=$(mktemp)
cp "$NGINX_CONF" "$tmp_nginx"

for domain in "${PREV_DUAL_CDN_DOMAINS[@]}" "$CDN_A" "$CDN_B"; do
  [[ -n "$domain" && "$domain" != "$DEFAULT_CDN_DOMAIN" ]] || continue
  remove_nginx_server_block "$domain" "$tmp_nginx"
done

if [[ "$CDN_A" == "$CDN_B" && "$CDN_A" != "$DEFAULT_CDN_DOMAIN" ]]; then
  warn "CDN-A 与 CDN-B 域名相同，无法生成两个独立 server block，将只写入一个回落站"
fi

if [[ "$CDN_A" == "$DEFAULT_CDN_DOMAIN" ]]; then
  warn "CDN-A 与原 CDN 域名相同，将复用主脚本写入的 server block"
fi
if [[ "$CDN_B" == "$DEFAULT_CDN_DOMAIN" ]]; then
  warn "CDN-B 与原 CDN 域名相同，将复用主脚本写入的 server block"
fi

sed -i '$d' "$tmp_nginx"

if [[ "$CDN_A" != "$DEFAULT_CDN_DOMAIN" ]]; then
  append_cdn_block "$CDN_A" "$CDN_A_FALLBACK_ORIGIN" "$CDN_A_FALLBACK_HOST" >> "$tmp_nginx"
fi

if [[ "$CDN_B" != "$DEFAULT_CDN_DOMAIN" && "$CDN_B" != "$CDN_A" ]]; then
  append_cdn_block "$CDN_B" "$CDN_B_FALLBACK_ORIGIN" "$CDN_B_FALLBACK_HOST" >> "$tmp_nginx"
fi

echo "}" >> "$tmp_nginx"
cat "$tmp_nginx" > "$NGINX_CONF"
rm -f "$tmp_nginx"
info "已为 CDN-A / CDN-B 写入独立回落站"

: > "$DUAL_CDN_STATE_FILE"
if [[ "$CDN_A" != "$DEFAULT_CDN_DOMAIN" ]]; then
  echo "$CDN_A" >> "$DUAL_CDN_STATE_FILE"
fi
if [[ "$CDN_B" != "$DEFAULT_CDN_DOMAIN" && "$CDN_B" != "$CDN_A" ]]; then
  echo "$CDN_B" >> "$DUAL_CDN_STATE_FILE"
fi
chmod 600 "$DUAL_CDN_STATE_FILE"

nginx -t
service_restart nginx
