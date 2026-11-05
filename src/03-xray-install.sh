# ==================================================
# Xray 安装与服务配置
# ==================================================

install_xray() {
  if [[ -f "/usr/local/bin/xray" && "${1:-}" != "update" ]]; then
    info "Xray already installed: $(/usr/local/bin/xray version 2>/dev/null | head -1 || echo 'unknown')"
    return
  fi

  info "Installing Xray-core..."

  if [[ "$OS_ID" != "alpine" ]]; then
    if [[ "${1:-}" == "update" ]]; then
      command -v curl >/dev/null 2>&1 || pkg_install curl
      local installer
      installer=$(curl -fL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
      bash -c "$installer" @ install --no-update-service
    else
      bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    fi
    return
  fi

  local arch asset tmpdir
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) asset="Xray-linux-64.zip" ;;
    aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
    *) error "Alpine 暂不支持当前架构: $arch" ;;
  esac

  if [[ "${1:-}" == "update" ]]; then
    command -v curl >/dev/null 2>&1 || pkg_install curl
  fi
  command -v unzip >/dev/null 2>&1 || pkg_install unzip
  tmpdir=$(mktemp -d)
  curl -fL "https://github.com/XTLS/Xray-core/releases/latest/download/${asset}" -o "${tmpdir}/xray.zip"
  unzip -q "${tmpdir}/xray.zip" -d "$tmpdir"

  mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray /var/log/xray
  install -m 755 "${tmpdir}/xray" /usr/local/bin/xray
  install -m 644 "${tmpdir}/geoip.dat" /usr/local/share/xray/geoip.dat
  install -m 644 "${tmpdir}/geosite.dat" /usr/local/share/xray/geosite.dat
  rm -rf "$tmpdir"

  if [[ "${1:-}" == "update" ]]; then
    service_restart xray
    return
  fi

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

if [ -f "/usr/local/bin/xray" ]; then
  info "当前 Xray: $(/usr/local/bin/xray version 2>/dev/null | head -1 || echo 'unknown')"
  info "选择 y：仅更新 Xray 并退出，保留现有配置"
  warn "选择 N：保留 Xray 版本并继续完整部署，将重新生成服务端和客户端配置"
  read -rp "是否仅更新 Xray 到最新正式版并退出 [y/N]: " REPLY || true
  case "${REPLY,,}" in
    y|yes)
      install_xray update
      info "Xray 更新流程结束，已保留现有配置"
      exit 0
      ;;
    *)
      info "保留当前 Xray 版本，继续完整部署"
      ;;
  esac
fi

