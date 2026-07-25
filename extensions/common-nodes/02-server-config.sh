# ==================================================
# Xray WS 入站、Nginx 转发与 hysteria2
# ==================================================

command -v nginx >/dev/null 2>&1 || error "未找到 nginx，请先运行主脚本"
command -v xray >/dev/null 2>&1 || error "未找到 xray，请先运行主脚本"
command -v acme.sh >/dev/null 2>&1 || error "未找到 acme.sh，请先运行主脚本"

NGINX_CONF="/etc/nginx/nginx.conf"
XRAY_CONF="/usr/local/etc/xray/config.json"
[[ -f "$NGINX_CONF" ]] || error "未找到 $NGINX_CONF"
[[ -f "$XRAY_CONF" ]] || error "未找到 $XRAY_CONF"
[[ -f /etc/ssl/private/fullchain.cer && -f /etc/ssl/private/private.key ]] || error "未找到证书文件，请先运行主脚本"

WS_INBOUND_PORT=8002
WS_INBOUND_TAG="vless-ws-cdn"

ws_inbound_file=$(mktemp)
cat > "$ws_inbound_file" <<EOF
        ,
        {
            "tag": "${WS_INBOUND_TAG}",
            "listen": "127.0.0.1",
            "port": ${WS_INBOUND_PORT},
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID2}",
                        "level": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "${WS_PATH}"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
                "routeOnly": true
            }
        }
EOF

tmp_xray=$(mktemp)
awk -v tag="\"tag\": \"${WS_INBOUND_TAG}\"" -v node_file="$ws_inbound_file" '
  function braces(line,  i, c) {
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (c == "{") depth++
      if (c == "}") depth--
    }
  }

  pending == 1 {
    if ($0 ~ /^        \{/) {
      depth = 0
      hit = 0
      blk = $0 ORS
      braces($0)
      pending = 2
    } else {
      print held
      print
      pending = 0
    }
    next
  }

  pending == 2 {
    blk = blk $0 ORS
    if (index($0, tag)) hit = 1
    braces($0)
    if (depth == 0) {
      if (!hit) {
        print held
        printf "%s", blk
      }
      pending = 0
    }
    next
  }

  /"inbounds"[[:space:]]*:/ { in_inbounds = 1 }
  in_inbounds && $0 == "        ," { held = $0; pending = 1; next }

  in_inbounds && /^    \],[[:space:]]*$/ {
    while ((getline line < node_file) > 0) print line
    inserted = 1
    in_inbounds = 0
  }

  { print }

  END { if (!inserted) exit 1 }
' "$XRAY_CONF" > "$tmp_xray" || error "未找到 Xray inbounds 数组"
cat "$tmp_xray" > "$XRAY_CONF"
rm -f "$tmp_xray" "$ws_inbound_file"
info "已写入 Xray vless+ws 入站 (127.0.0.1:${WS_INBOUND_PORT})"

WS_MARK_BEGIN="        # BEGIN common-nodes ws"
WS_MARK_END="        # END common-nodes ws"

ws_location_file=$(mktemp)
cat > "$ws_location_file" <<EOF
${WS_MARK_BEGIN}
        location = ${WS_PATH} {
            if (\$http_upgrade != "websocket") {
                return 404;
            }
            proxy_pass http://127.0.0.1:${WS_INBOUND_PORT};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$real_client_ip;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }
${WS_MARK_END}
EOF

tmp_nginx=$(mktemp)
awk -v domain="$CDN_DOMAIN" -v node_file="$ws_location_file" \
    -v mark_begin="$WS_MARK_BEGIN" -v mark_end="$WS_MARK_END" '
  $0 == mark_begin { skip = 1; next }
  $0 == mark_end   { skip = 0; next }
  skip             { next }

  /^[[:space:]]*server[[:space:]]*\{/ { in_server = 1 }
  in_server && !inserted && /^[[:space:]]*server_name[[:space:]]/ && index($0, domain) {
    print
    while ((getline line < node_file) > 0) print line
    inserted = 1
    next
  }
  { print }
  END { exit inserted ? 0 : 1 }
' "$NGINX_CONF" > "$tmp_nginx" || error "未在 Nginx 配置中找到 CDN 域名 server block: $CDN_DOMAIN"
cat "$tmp_nginx" > "$NGINX_CONF"
rm -f "$tmp_nginx" "$ws_location_file"
info "已在 CDN 域名 server block 写入 WebSocket 转发"

HYSTERIA_BIN="/usr/local/bin/hysteria"
HYSTERIA_CONF_DIR="/etc/hysteria"
HYSTERIA_CONF="${HYSTERIA_CONF_DIR}/config.yaml"
HYSTERIA_SERVICE="hysteria-server"

if [[ ! -x "$HYSTERIA_BIN" ]]; then
  case "$(uname -m)" in
    x86_64|amd64) HY_ARCH="amd64" ;;
    aarch64|arm64) HY_ARCH="arm64" ;;
    armv7l|armv7) HY_ARCH="arm" ;;
    s390x) HY_ARCH="s390x" ;;
    *) error "不支持的 CPU 架构: $(uname -m)，无法安装 hysteria2" ;;
  esac
  info "下载 hysteria2 (linux-${HY_ARCH})..."
  curl -fsSL -o "$HYSTERIA_BIN" \
    "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_ARCH}" \
    || error "hysteria2 下载失败"
  chmod +x "$HYSTERIA_BIN"
else
  info "检测到已安装 hysteria2，跳过下载"
fi

install -d -m 755 "$HYSTERIA_CONF_DIR"
cat > "$HYSTERIA_CONF" <<EOF
listen: :${HY2_PORT}

tls:
  cert: /etc/ssl/private/fullchain.cer
  key: /etc/ssl/private/private.key

auth:
  type: password
  password: ${HY2_PASSWORD}
EOF

if [[ "$FALLBACK_MODE" == "static" ]]; then
  cat >> "$HYSTERIA_CONF" <<EOF
masquerade:
  type: file
  file:
    dir: ${STATIC_SITE_DIR}/${REALITY_DOMAIN}
EOF
else
  cat >> "$HYSTERIA_CONF" <<EOF
masquerade:
  type: proxy
  proxy:
    url: ${REALITY_FALLBACK_ORIGIN}
    rewriteHost: true
EOF
fi
chmod 600 "$HYSTERIA_CONF"
info "已写入 hysteria2 配置: $HYSTERIA_CONF"

if [[ "$SERVICE_TYPE" == "openrc" ]]; then
  cat > "/etc/init.d/${HYSTERIA_SERVICE}" <<'EOF'
#!/sbin/openrc-run

name="hysteria-server"
description="Hysteria2 Server"
command="/usr/local/bin/hysteria"
command_args="server --config /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/hysteria-server.pid"
output_log="/var/log/hysteria-server.log"
error_log="/var/log/hysteria-server.log"

depend() {
    need net
}
EOF
  chmod +x "/etc/init.d/${HYSTERIA_SERVICE}"
  rc-update add "$HYSTERIA_SERVICE" default >/dev/null 2>&1 || true
  HYSTERIA_RESTART_CMD="rc-service ${HYSTERIA_SERVICE} restart"
else
  cat > "/etc/systemd/system/${HYSTERIA_SERVICE}.service" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=${HYSTERIA_BIN} server --config ${HYSTERIA_CONF}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$HYSTERIA_SERVICE" >/dev/null 2>&1 || true
  HYSTERIA_RESTART_CMD="systemctl restart ${HYSTERIA_SERVICE}"
fi

acme.sh --install-cert -d "$REALITY_DOMAIN" --ecc \
  --key-file /etc/ssl/private/private.key \
  --fullchain-file /etc/ssl/private/fullchain.cer \
  --reloadcmd "${NGINX_RESTART_CMD}; ${HYSTERIA_RESTART_CMD}"

install -d -m 700 "$COMMON_STATE_DIR"
cat > "$COMMON_STATE_FILE" <<EOF
WS_PATH=${WS_PATH}
HY2_PASSWORD=${HY2_PASSWORD}
EOF
chmod 600 "$COMMON_STATE_FILE"

nginx -t
xray -test -config "$XRAY_CONF"
service_restart nginx
service_restart xray
service_restart "$HYSTERIA_SERVICE"

if [[ "$SERVICE_TYPE" == "systemd" ]]; then
  sleep 1
  systemctl is-active --quiet "$HYSTERIA_SERVICE" || error "hysteria2 启动失败，请检查 journalctl -u ${HYSTERIA_SERVICE}"
fi
info "Nginx / Xray / hysteria2 已重启"
info "hysteria2 监听 UDP ${HY2_PORT}"
