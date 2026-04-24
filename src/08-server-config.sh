# ==================================================
# 服务端配置生成
# ==================================================

info "[4/6] 生成配置文件"

info "写入 /etc/nginx/nginx.conf ..."
cat > /etc/nginx/nginx.conf << NGINXEOF
@@include templates/nginx.conf.tmpl
NGINXEOF

info "写入 /usr/local/etc/xray/config.json ..."
cat > /usr/local/etc/xray/config.json << XRAYEOF
@@include templates/xray-config.json.tmpl
XRAYEOF

echo ""
