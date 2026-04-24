# ==================================================
# 启动服务与配置自检
# ==================================================

info "[5/6] 启动服务"

info "配置证书自动续签命令..."
mkdir -p /etc/ssl/private
acme.sh --install-cert -d "$REALITY_DOMAIN" --ecc \
  --key-file /etc/ssl/private/private.key \
  --fullchain-file /etc/ssl/private/fullchain.cer \
  --reloadcmd "${NGINX_RESTART_CMD}"

info "测试 Nginx 配置..."
nginx -t

info "测试 Xray 配置..."
xray -test -config /usr/local/etc/xray/config.json

info "启动服务..."
service_restart xray
service_restart nginx
sleep 1
service_is_active xray || error "Xray 启动失败"
service_is_active nginx || error "Nginx 启动失败"
info "Xray 运行中"
info "Nginx 运行中"

echo ""

