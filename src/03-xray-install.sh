# ==================================================
# Xray 安装与服务配置
# ==================================================

install_xray() {
  if [[ "$OS_ID" != "alpine" ]]; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    return
  fi

  local arch asset tmpdir
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) asset="Xray-linux-64.zip" ;;
    aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
    *) error "Alpine 暂不支持当前架构: $arch" ;;
  esac

  command -v unzip >/dev/null 2>&1 || pkg_install unzip
  XRAY_VERSION="v26.3.27"
  tmpdir=$(mktemp -d)
  curl -fL "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${asset}" -o "${tmpdir}/xray.zip"
  unzip -q "${tmpdir}/xray.zip" -d "$tmpdir"

  mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray /var/log/xray
  install -m 755 "${tmpdir}/xray" /usr/local/bin/xray
  install -m 644 "${tmpdir}/geoip.dat" /usr/local/share/xray/geoip.dat
  install -m 644 "${tmpdir}/geosite.dat" /usr/local/share/xray/geosite.dat
  rm -rf "$tmpdir"

  cat > /etc/init.d/xray << 'XRAYSERVICEEOF'
#!/sbin/openrc-run

name="xray"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"

export XRAY_LOCATION_ASSET="/usr/local/share/xray"

depend() {
    need net
}

start_pre() {
    checkpath --directory --mode 0755 /run
    checkpath --directory --mode 0755 /var/log/xray
}
XRAYSERVICEEOF
  chmod +x /etc/init.d/xray
  service_enable xray
}

