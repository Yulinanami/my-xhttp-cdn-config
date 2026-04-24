# ==================================================
# Nginx 编译安装与服务配置
# ==================================================

info "[3/6] 编译安装 Nginx"
info "安装编译依赖..."
install_build_deps

NGINX_VER="1.27.3"
cd /tmp
wget -q "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz"
tar -xf "nginx-${NGINX_VER}.tar.gz"
cd "nginx-${NGINX_VER}"

info "编译 Nginx ${NGINX_VER} ..."
./configure \
  --prefix=/usr/local/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --with-cc-opt="-Wno-error" \
  --with-http_stub_status_module \
  --with-http_ssl_module \
  --with-http_realip_module \
  --with-http_sub_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-http_v2_module

make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
make install

cd /tmp && rm -rf "nginx-${NGINX_VER}" "nginx-${NGINX_VER}.tar.gz"
mkdir -p /var/log/nginx

info "创建 ${SERVICE_TYPE} 服务..."
if [[ "$SERVICE_TYPE" == "openrc" ]]; then
  cat > /etc/init.d/nginx << 'SERVICEEOF'
#!/sbin/openrc-run

name="nginx"
description="Nginx web server"
command="/usr/sbin/nginx"
command_args="-g 'daemon off; master_process on;'"
command_background="yes"
pidfile="/run/nginx.pid"
required_files="/etc/nginx/nginx.conf"
extra_started_commands="reload"

depend() {
    need net
}

start_pre() {
    checkpath --directory --mode 0755 /run
    /usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
}

reload() {
    start_pre || return 1
    ebegin "Reloading nginx"
    /usr/sbin/nginx -s reload
    eend $?
}
SERVICEEOF
  chmod +x /etc/init.d/nginx
  service_enable nginx
else
  cat > /etc/systemd/system/nginx.service << 'SERVICEEOF'
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/bin/kill -s QUIT $MAINPID
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
SERVICEEOF

  systemctl daemon-reload
  service_enable nginx.service
fi
echo ""

