# ==================================================
# 证书、Nginx 与 Xray
# ==================================================

command -v acme.sh >/dev/null 2>&1 || error "未找到 acme.sh，请先运行主脚本"
command -v nginx >/dev/null 2>&1 || error "未找到 nginx，请先运行主脚本"
command -v xray >/dev/null 2>&1 || error "未找到 xray，请先运行主脚本"

ACME_CERT_HOME="/root/.acme.sh/${REALITY_DOMAIN}_ecc"
ACME_CERT_CONF="${ACME_CERT_HOME}/${REALITY_DOMAIN}.conf"
NGINX_CONF="/etc/nginx/nginx.conf"
XRAY_CONF="/usr/local/etc/xray/config.json"
[[ -f "$NGINX_CONF" ]] || error "未找到 $NGINX_CONF"
[[ -f "$XRAY_CONF" ]] || error "未找到 $XRAY_CONF"

DUAL_IP_STATE_DIR="/etc/xhttp-cdn"
DUAL_IP_STATE_FILE="${DUAL_IP_STATE_DIR}/dual-ip-domains"
DUAL_CDN_STATE_FILE="${DUAL_IP_STATE_DIR}/dual-cdn-domains"
install -d -m 700 "$DUAL_IP_STATE_DIR"

if [[ -f "$DUAL_IP_STATE_FILE" ]]; then
  while IFS= read -r old_domain; do
    add_old_reality_domain "$old_domain"
  done < "$DUAL_IP_STATE_FILE"
fi

CURRENT_DUAL_CDN_DOMAINS=()
add_current_dual_cdn_domain() {
  local domain="$1" existing
  [[ -n "$domain" ]] || return 0
  for existing in "${CURRENT_DUAL_CDN_DOMAINS[@]}"; do
    [[ "$existing" == "$domain" ]] && return 0
  done
  CURRENT_DUAL_CDN_DOMAINS+=("$domain")
}

if [[ -f "$DUAL_CDN_STATE_FILE" ]]; then
  while IFS= read -r domain; do
    add_current_dual_cdn_domain "$domain"
  done < "$DUAL_CDN_STATE_FILE"
fi

CERT_DOMAINS=()
add_cert_domain() {
  local domain="$1" existing
  [[ -n "$domain" ]] || return 0
  for existing in "${CERT_DOMAINS[@]}"; do
    [[ "$existing" == "$domain" ]] && return 0
  done
  CERT_DOMAINS+=("$domain")
}

add_cert_domain "$REALITY_DOMAIN"
add_cert_domain "$DEFAULT_CDN_DOMAIN"
for domain in "${CURRENT_DUAL_CDN_DOMAINS[@]}"; do
  add_cert_domain "$domain"
done
add_cert_domain "$REALITY_DOMAIN_V4"
add_cert_domain "$REALITY_DOMAIN_V6"

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

ACME_DOMAIN_ARGS=()
for domain in "${CERT_DOMAINS[@]}"; do
  ACME_DOMAIN_ARGS+=(-d "$domain")
done

if cert_has_all_domains; then
  info "检测到证书已包含 IPv4 / IPv6 Reality 域名，跳过重新签发"
else
  info "申请 / 更新包含 IPv4、IPv6 Reality 域名的证书..."
  set +e
  ISSUE_OUTPUT=$(acme.sh --issue "${ACME_DOMAIN_ARGS[@]}" \
    --standalone --listen-v6 --keylength ec-256 \
    --pre-hook "${NGINX_STOP_CMD} 2>/dev/null || true" \
    --post-hook "${NGINX_START_CMD} 2>/dev/null || true" 2>&1)
  ISSUE_CODE=$?
  set -e
  echo "$ISSUE_OUTPUT"
  if [[ $ISSUE_CODE -ne 0 ]] && ! echo "$ISSUE_OUTPUT" | grep -Eqi 'Domains not changed|Skipping\. Next renewal time'; then
    error "IPv4 / IPv6 Reality 域名证书申请失败"
  fi
fi

info "安装证书..."
acme.sh --install-cert -d "$REALITY_DOMAIN" --ecc \
  --key-file /etc/ssl/private/private.key \
  --fullchain-file /etc/ssl/private/fullchain.cer \
  --reloadcmd "${NGINX_RESTART_CMD}"

append_reality_block() {
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

        location ^~ /sub/ {
            root /usr/local/nginx/html;
            try_files \$uri =404;
            autoindex off;
            types {
                text/plain txt;
                application/yaml yaml yml;
            }
            default_type text/plain;
            add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;
        }

        location / {
            proxy_pass ${fallback_origin};
            proxy_ssl_server_name on;
            proxy_ssl_name ${fallback_host};
            proxy_redirect ${fallback_origin}/ https://\$host/;
            proxy_redirect http://${fallback_host}/ https://\$host/;
            proxy_redirect https://${fallback_host}/ https://\$host/;
            proxy_set_header Host ${fallback_host};
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
        }
    }
EOF
}

remove_nginx_server_block() {
  local domain="$1"
  local input="$2"
  local output="$3"

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
  ' "$input" > "$output"
}

cert_domain_targeted() {
  local domain="$1" target
  for target in "${CERT_DOMAINS[@]}"; do
    [[ "$domain" == "$target" ]] && return 0
  done
  return 1
}

tmp_nginx=$(mktemp)
tmp_nginx_next=$(mktemp)

cp "$NGINX_CONF" "$tmp_nginx"
while IFS= read -r prev_domain; do
  [[ "$prev_domain" == "_" ]] && continue
  if ! cert_domain_targeted "$prev_domain"; then
    remove_nginx_server_block "$prev_domain" "$tmp_nginx" "$tmp_nginx_next"
    mv "$tmp_nginx_next" "$tmp_nginx"
    info "移除历史 server block: $prev_domain"
  fi
done < <(awk '/^[[:space:]]*server_name[[:space:]]/ { gsub(/;/, ""); for (i = 2; i <= NF; i++) print $i }' "$NGINX_CONF")

for old_domain in "${OLD_REALITY_DOMAINS[@]}" "$REALITY_DOMAIN_V4" "$REALITY_DOMAIN_V6"; do
  remove_nginx_server_block "$old_domain" "$tmp_nginx" "$tmp_nginx_next"
  mv "$tmp_nginx_next" "$tmp_nginx"
done

sed -i '$d' "$tmp_nginx"
append_reality_block "$REALITY_DOMAIN_V4" "$FALLBACK_ORIGIN_V4" "$FALLBACK_HOST_V4" >> "$tmp_nginx"
append_reality_block "$REALITY_DOMAIN_V6" "$FALLBACK_ORIGIN_V6" "$FALLBACK_HOST_V6" >> "$tmp_nginx"
echo "}" >> "$tmp_nginx"
cat "$tmp_nginx" > "$NGINX_CONF"
rm -f "$tmp_nginx" "$tmp_nginx_next"
info "已写入 IPv4 / IPv6 Reality 独立回落站"

printf '%s\n%s\n' "$REALITY_DOMAIN_V4" "$REALITY_DOMAIN_V6" > "$DUAL_IP_STATE_FILE"
chmod 600 "$DUAL_IP_STATE_FILE"

tmp_xray=$(mktemp)
awk -v base="$REALITY_DOMAIN" -v v4="$REALITY_DOMAIN_V4" -v v6="$REALITY_DOMAIN_V6" '
  function add_name(name) {
    if (name == "") return
    for (i = 1; i <= count; i++) if (names[i] == name) return
    names[++count] = name
  }

  !listen_done && /"listen"[[:space:]]*:[[:space:]]*"0\.0\.0\.0"/ {
    sub(/"0\.0\.0\.0"/, "\"::\"")
    listen_done = 1
  }

  /"serverNames"[[:space:]]*:/ {
    print
    count = 0
    add_name(base)
    add_name(v4)
    add_name(v6)
    for (i = 1; i <= count; i++) {
      printf "                        \"%s\"%s\n", names[i], (i < count ? "," : "")
    }
    skip = 1
    next
  }

  skip && /^[[:space:]]*],[[:space:]]*$/ {
    print "                    ],"
    skip = 0
    next
  }

  skip { next }
  { print }
' "$XRAY_CONF" > "$tmp_xray"
cat "$tmp_xray" > "$XRAY_CONF"
rm -f "$tmp_xray"
info "已写入 Xray Reality serverNames"

nginx -t
xray -test -config "$XRAY_CONF"
service_restart nginx
service_restart xray
