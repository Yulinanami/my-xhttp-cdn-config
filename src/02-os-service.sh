# ==================================================
# 包管理与服务管理适配
# ==================================================

case "$OS_ID" in
  debian|ubuntu)
    pkg_update()  { apt update -y; }
    pkg_install() { apt install -y "$@"; }
    install_build_deps() {
      apt-get install -y gcc g++ libpcre3 libpcre3-dev zlib1g zlib1g-dev openssl libssl-dev wget make 2>/dev/null || \
        apt-get install -y gcc g++ libpcre2-dev zlib1g-dev libssl-dev wget make
    }
    ;;
  centos|rhel|almalinux|rocky|ol|amzn)
    pkg_update()  { yum makecache; }
    pkg_install() { yum install -y "$@"; }
    install_build_deps() {
      yum groupinstall -y "Development Tools"
      yum install -y pcre-devel zlib-devel openssl-devel wget make 2>/dev/null || \
        yum install -y pcre2-devel zlib-devel openssl-devel wget make
    }
    ;;
  fedora)
    pkg_update()  { dnf makecache; }
    pkg_install() { dnf install -y "$@"; }
    install_build_deps() {
      dnf groupinstall -y "Development Tools"
      dnf install -y pcre-devel zlib-devel openssl-devel wget make 2>/dev/null || \
        dnf install -y pcre2-devel zlib-devel openssl-devel wget make
    }
    ;;
  opensuse*|sles)
    pkg_update()  { zypper refresh; }
    pkg_install() { zypper install -y "$@"; }
    install_build_deps() {
      zypper install -y -t pattern devel_basis
      zypper install -y pcre2-devel zlib-devel libopenssl-devel wget make
    }
    ;;
  alpine)
    pkg_update()  { apk update; }
    pkg_install() { apk add --no-cache "$@"; }
    install_build_deps() {
      apk add --no-cache build-base linux-headers pcre2-dev zlib-dev openssl-dev wget make
    }
    ;;
  *)
    error "不支持的发行版: $OS_ID，目前支持 Debian/Ubuntu/CentOS/RHEL/Fedora/openSUSE/SLES/Alpine"
    ;;
esac

if [[ "$OS_ID" == "alpine" ]]; then
  SERVICE_TYPE="openrc"
  NGINX_STOP_CMD="rc-service nginx stop"
  NGINX_START_CMD="rc-service nginx start"
  NGINX_RESTART_CMD="rc-service nginx restart"
else
  SERVICE_TYPE="systemd"
  NGINX_STOP_CMD="systemctl stop nginx"
  NGINX_START_CMD="systemctl start nginx"
  NGINX_RESTART_CMD="systemctl restart nginx"
fi

service_enable() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-update add "$1" default >/dev/null 2>&1 || true
  else
    systemctl enable "$1" >/dev/null 2>&1 || true
  fi
}

service_restart() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$1" restart || rc-service "$1" start
  else
    systemctl restart "$1"
  fi
}

service_is_active() {
  if [[ "$SERVICE_TYPE" == "openrc" ]]; then
    rc-service "$1" status >/dev/null 2>&1
  else
    systemctl is-active --quiet "$1"
  fi
}

