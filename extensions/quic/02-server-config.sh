# ==================================================
# Nginx XHTTP H3
# ==================================================

command -v nginx >/dev/null 2>&1 || error "未找到 nginx，请先运行主脚本"
command -v xray >/dev/null 2>&1 || error "未找到 xray，请先运行主脚本"
nginx -V 2>&1 | grep -q -- '--with-http_v3_module' || error "Nginx 未启用 HTTP/3 模块，请重新运行主脚本"

NGINX_CONF="/etc/nginx/nginx.conf"
XRAY_CONF="/usr/local/etc/xray/config.json"
[[ -f "$NGINX_CONF" ]] || error "未找到 $NGINX_CONF"
[[ -f "$XRAY_CONF" ]] || error "未找到 $XRAY_CONF"
[[ -f /etc/ssl/private/fullchain.cer && -f /etc/ssl/private/private.key ]] || error "未找到证书文件，请先运行主脚本"

sed -i \
  -e '/^[[:space:]]*# BEGIN quic xhttp$/,/^[[:space:]]*# END quic xhttp$/d' \
  "$NGINX_CONF"

grep -Eq "^[[:space:]]*server_name[[:space:]][[:space:]]*${CDN_DOMAIN};[[:space:]]*$" "$NGINX_CONF" ||
  error "未找到 CDN 域名 Nginx 配置"

sed -i "/^[[:space:]]*server_name[[:space:]][[:space:]]*${CDN_DOMAIN};[[:space:]]*$/a\\
        # BEGIN quic xhttp\\
        listen ${XHTTP_H3_PORT} quic reuseport;\\
        add_header Alt-Svc 'h3=\":${XHTTP_H3_PORT}\"; ma=86400' always;\\
        # END quic xhttp" "$NGINX_CONF"

nginx -t
xray -test -config "$XRAY_CONF"
service_restart nginx
info "XHTTP H3 已监听 Nginx UDP ${XHTTP_H3_PORT}"
