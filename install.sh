#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本"

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  error "无法识别当前系统发行版"
fi

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
  *)
    error "不支持的发行版: $OS_ID，目前支持 Debian/Ubuntu/CentOS/RHEL/Fedora/openSUSE/SLES"
    ;;
esac

info "检测到系统: $PRETTY_NAME"

if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(eval echo "~$SUDO_USER")
else
  USER_HOME=$(getent passwd 1000 | cut -d: -f6)
fi
[[ -z "$USER_HOME" || ! -d "$USER_HOME" ]] && USER_HOME="/root"

echo -e "\n${CYAN}[+] XHTTP + CDN 一键部署脚本${NC}\n"
echo -e "${GREEN}[+] 推荐系统: Ubuntu 24.04 / Debian 12${NC}"
echo -e "${YELLOW}[+] 前置条件 (请确认已在 Cloudflare 完成):${NC}"
echo "  1. Reality 域名 DNS → 仅 DNS (灰色云朵)"
echo "  2. CDN 域名 DNS    → 代理开启 (橙色云朵)"
echo "  3. SSL/TLS 加密    → 完全(严格)"
echo "  4. 网络 → gRPC     → 已开启"
echo "  5. 缓存规则         → 部署完成后根据提示配置 (建议)"
echo ""

read -rp "请输入 Reality 域名 (如 reality.example.com): " REALITY_DOMAIN
[[ -z "$REALITY_DOMAIN" ]] && error "域名不能为空"

read -rp "请输入 CDN 域名 (如 cdn.example.com): " CDN_DOMAIN
[[ -z "$CDN_DOMAIN" ]] && error "域名不能为空"

echo ""
echo "  1) IPv4"
echo "  2) IPv6"
read -rp "请选择 IP 类型 [1/2] (默认 1): " IP_CHOICE
IP_CHOICE=${IP_CHOICE:-1}

echo ""
info "Reality: $REALITY_DOMAIN"
info "CDN:     $CDN_DOMAIN"
echo ""

info "[1/6] 安装基础环境"

pkg_update

command -v curl    >/dev/null 2>&1 || pkg_install curl
command -v sudo    >/dev/null 2>&1 || pkg_install sudo
command -v socat   >/dev/null 2>&1 || pkg_install socat
command -v wget    >/dev/null 2>&1 || pkg_install wget
command -v tar     >/dev/null 2>&1 || pkg_install tar
command -v openssl >/dev/null 2>&1 || pkg_install openssl
if ! command -v qrencode >/dev/null 2>&1; then
  info "安装二维码工具 qrencode..."
  if ! pkg_install qrencode; then
    warn "qrencode 安装失败，将跳过二维码输出"
  fi
fi

if ! command -v crontab >/dev/null 2>&1; then
  case "$OS_ID" in
    debian|ubuntu|opensuse*|sles)
      pkg_install cron
      ;;
    centos|rhel|almalinux|rocky|ol|amzn|fedora)
      pkg_install cronie
      systemctl enable --now crond 2>/dev/null || true
      ;;
  esac
fi

info "安装 Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
export PATH="/usr/local/bin:$PATH"

info "生成参数..."
UUID1=$(xray uuid)
UUID2=$(xray uuid)
KEY_OUTPUT=$(xray x25519 2>&1)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | awk -F': ' '{print $2}' | tr -d '[:space:]')
[[ -z "$PRIVATE_KEY" ]] && error "未能提取 Private Key，xray x25519 输出: $KEY_OUTPUT"
[[ -z "$PUBLIC_KEY" ]] && error "未能提取 Public Key，xray x25519 输出: $KEY_OUTPUT"
SHORT_ID=$(echo "$UUID1" | tr -d '-' | cut -c1-8)
XHTTP_PATH="/$(echo "$UUID2" | tr -d '-' | cut -c1-8)"

info "生成 VLESS Encryption 密钥..."
VLESSENC_OUTPUT=$(xray vlessenc 2>&1)
if [[ $? -ne 0 ]] || ! echo "$VLESSENC_OUTPUT" | grep -qi "encryption"; then
  error "VLESS Encryption 密钥生成失败，请确保 Xray 版本支持 vlessenc。输出: $VLESSENC_OUTPUT"
fi
VLESSENC_ENCRYPTION=$(echo "$VLESSENC_OUTPUT" | awk '/ML-KEM/{found=1} found && /"encryption"/{print; exit}' | awk -F'"' '{print $4}')
VLESSENC_DECRYPTION=$(echo "$VLESSENC_OUTPUT" | awk '/ML-KEM/{found=1} found && /"decryption"/{print; exit}' | awk -F'"' '{print $4}')
[[ -z "$VLESSENC_ENCRYPTION" ]] && error "未能提取 ML-KEM-768 Encryption Key，xray vlessenc 输出: $VLESSENC_OUTPUT"
[[ -z "$VLESSENC_DECRYPTION" ]] && error "未能提取 ML-KEM-768 Decryption Key，xray vlessenc 输出: $VLESSENC_OUTPUT"
if [[ "$IP_CHOICE" == "2" ]]; then
  VPS_IP=$(curl -6 -s --max-time 5 ip.sb)
  [[ -z "$VPS_IP" ]] && error "无法获取 IPv6 地址"
  VPS_IP_URI="[${VPS_IP}]"
  VPS_IP_ENC=$(echo "$VPS_IP" | sed 's/:/%3A/g')
else
  VPS_IP=$(curl -4 -s --max-time 5 ip.sb)
  [[ -z "$VPS_IP" ]] && error "无法获取 IPv4 地址"
  VPS_IP_URI="${VPS_IP}"
  VPS_IP_ENC="${VPS_IP}"
fi

info "UUID1 (Vision): $UUID1"
info "UUID2 (XHTTP):  $UUID2"
info "Private Key:    $PRIVATE_KEY"
info "Public Key:     $PUBLIC_KEY"
info "Short ID:       $SHORT_ID"
info "Path:           $XHTTP_PATH"
info "VPS IP:         $VPS_IP"
info "VLESS Enc:      已启用 (防 CDN 中间人)"
echo ""

info "[2/6] 申请 / 复用 SSL 证书"

curl https://get.acme.sh | sh
ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

acme.sh --set-default-ca --server letsencrypt

ACME_CERT_HOME="/root/.acme.sh/${REALITY_DOMAIN}_ecc"
ACME_CERT_CONF="${ACME_CERT_HOME}/${REALITY_DOMAIN}.conf"

have_existing_dual_cert() {
  [[ -f "$ACME_CERT_CONF" ]] || return 1

  local alt_line
  alt_line=$(grep "^Le_Alt=" "$ACME_CERT_CONF" 2>/dev/null || true)

  grep -Fq "Le_Domain='${REALITY_DOMAIN}'" "$ACME_CERT_CONF" || return 1
  [[ -n "$alt_line" && "$alt_line" == *"$CDN_DOMAIN"* ]] || return 1
  [[ -f "$ACME_CERT_HOME/fullchain.cer" ]] || return 1
  [[ -f "$ACME_CERT_HOME/${REALITY_DOMAIN}.key" ]] || return 1
  return 0
}

issue_dual_cert() {
  if [[ "$IP_CHOICE" == "2" ]]; then
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --listen-v6 --keylength ec-256 \
      --pre-hook "systemctl stop nginx 2>/dev/null || true" \
      --post-hook "systemctl start nginx 2>/dev/null || true"
  else
    acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone --keylength ec-256 \
      --pre-hook "systemctl stop nginx 2>/dev/null || true" \
      --post-hook "systemctl start nginx 2>/dev/null || true"
  fi
}

if have_existing_dual_cert; then
  info "检测到已存在的双域名证书，跳过重新签发，直接复用"
else
  info "未检测到可复用的双域名证书，开始申请 (需要 80 端口空闲)..."
  set +e
  ISSUE_OUTPUT=$(issue_dual_cert 2>&1)
  ISSUE_CODE=$?
  set -e
  echo "$ISSUE_OUTPUT"
  if [[ $ISSUE_CODE -ne 0 ]]; then
    if echo "$ISSUE_OUTPUT" | grep -Eqi 'Domains not changed|Skipping\\. Next renewal time'; then
      warn "acme.sh 返回“Domains not changed”，视为已有证书可复用，继续执行"
    elif echo "$ISSUE_OUTPUT" | grep -Eqi 'rateLimit|too many certificates|Le_OrderFinalize'; then
      warn "Let's Encrypt 可能触发了签发频率限制；如果之前已签发过这组域名，请等待限流结束或直接复用现有证书"
      error "双域名证书申请失败"
    else
      error "双域名证书申请失败"
    fi
  fi
fi

echo ""
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

make -j"$(nproc)"
make install

cd /tmp && rm -rf "nginx-${NGINX_VER}" "nginx-${NGINX_VER}.tar.gz"
mkdir -p /var/log/nginx

info "创建 systemd 服务..."
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
systemctl enable nginx.service
echo ""

info "[4/6] 生成配置文件"

info "写入 /etc/nginx/nginx.conf ..."
cat > /etc/nginx/nginx.conf << NGINXEOF
user root;
worker_processes auto;

error_log /usr/local/nginx/logs/error.log notice;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    set_real_ip_from      127.0.0.1;
    map \$http_cf_connecting_ip \$real_client_ip {
        default \$http_cf_connecting_ip;
        ""      \$remote_addr;
    }
    real_ip_header        X-Real-IP;

    sendfile              on;
    server_tokens         off;
    tcp_nodelay           on;
    tcp_nopush            on;
    client_max_body_size  0;
    gzip                  on;

    add_header X-Content-Type-Options nosniff;

    ssl_session_cache          shared:SSL:16m;
    ssl_session_timeout        1h;
    ssl_session_tickets        off;
    ssl_protocols              TLSv1.3 TLSv1.2;
    ssl_ciphers                TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers  on;
    ssl_stapling               on;
    ssl_stapling_verify        on;
    resolver                   1.1.1.1 8.8.8.8 valid=60s;
    resolver_timeout           2s;

    map \$real_client_ip \$proxy_forwarded_elem {
        ~^[0-9.]+\$        "for=\$real_client_ip";
        ~^[0-9A-Fa-f:.]+\$ "for=\"[\$real_client_ip]\"";
        default           "for=unknown";
    }
    map \$http_forwarded \$proxy_add_forwarded {
        default "\$proxy_forwarded_elem";
    }
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ""      close;
    }

    server {
        listen       8003 ssl;
        http2        on;
        server_name  ${REALITY_DOMAIN};

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
            proxy_pass https://www.stanford.edu;
            proxy_set_header Host www.stanford.edu;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
        }
    }

    server {
        listen       8003 ssl;
        http2        on;
        server_name  ${CDN_DOMAIN};

        ssl_certificate /etc/ssl/private/fullchain.cer;
        ssl_certificate_key /etc/ssl/private/private.key;

        location / {
            proxy_pass https://www.harvard.edu;
            proxy_set_header Host www.harvard.edu;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
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

    server {
        listen  80 default_server;
        server_name _;
        return 301 https://\$host\$request_uri;
    }
}
NGINXEOF

info "写入 /usr/local/etc/xray/config.json ..."
cat > /usr/local/etc/xray/config.json << XRAYEOF
{
    "log": {
        "loglevel": "info"
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:cn",
                    "geoip:private"
                ],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID1}",
                        "level": 0,
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "8001",
                        "xver": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "target": "8003",
                    "xver": 0,
                    "serverNames": [
                        "${REALITY_DOMAIN}"
                    ],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": [
                        "${SHORT_ID}"
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
                "routeOnly": true
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 8001,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID2}",
                        "level": 0
                    }
                ],
                "decryption": "${VLESSENC_DECRYPTION}"
            },
            "streamSettings": {
                "network": "xhttp",
                "xhttpSettings": {
                    "host": "",
                    "path": "${XHTTP_PATH}",
                    "mode": "auto"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false,
                "routeOnly": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
XRAYEOF

echo ""

info "[5/6] 启动服务"

info "配置证书自动续签命令..."
mkdir -p /etc/ssl/private
acme.sh --install-cert -d "$REALITY_DOMAIN" --ecc \
  --key-file /etc/ssl/private/private.key \
  --fullchain-file /etc/ssl/private/fullchain.cer \
  --reloadcmd "systemctl restart nginx"

info "测试 Nginx 配置..."
nginx -t

info "测试 Xray 配置..."
xray -test -config /usr/local/etc/xray/config.json

info "启动服务..."
systemctl restart xray
systemctl restart nginx
sleep 1
systemctl is-active --quiet xray || error "Xray 启动失败"
systemctl is-active --quiet nginx || error "Nginx 启动失败"
info "Xray 运行中"
info "Nginx 运行中"

echo ""

info "[6/6] 生成客户端配置"
XHTTP_PATH_ENC=$(printf '%s' "$XHTTP_PATH" | sed 's|/|%2F|g')

EXTRA_3="%7B%22downloadSettings%22%3A%7B%22address%22%3A%22${VPS_IP_ENC}%22%2C%22port%22%3A443%2C%22network%22%3A%22xhttp%22%2C%22security%22%3A%22reality%22%2C%22realitySettings%22%3A%7B%22show%22%3Afalse%2C%22serverName%22%3A%22${REALITY_DOMAIN}%22%2C%22fingerprint%22%3A%22chrome%22%2C%22shortId%22%3A%22${SHORT_ID}%22%2C%22publicKey%22%3A%22${PUBLIC_KEY}%22%7D%2C%22xhttpSettings%22%3A%7B%22host%22%3A%22%22%2C%22path%22%3A%22${XHTTP_PATH_ENC}%22%2C%22mode%22%3A%22auto%22%7D%7D%7D"

EXTRA_5="%7B%22downloadSettings%22%3A%7B%22address%22%3A%22${CDN_DOMAIN}%22%2C%22port%22%3A443%2C%22network%22%3A%22xhttp%22%2C%22security%22%3A%22tls%22%2C%22tlsSettings%22%3A%7B%22serverName%22%3A%22${CDN_DOMAIN}%22%2C%22allowInsecure%22%3Afalse%2C%22alpn%22%3A%5B%22h2%22%5D%2C%22fingerprint%22%3A%22chrome%22%7D%2C%22xhttpSettings%22%3A%7B%22host%22%3A%22${CDN_DOMAIN}%22%2C%22path%22%3A%22${XHTTP_PATH_ENC}%22%2C%22mode%22%3A%22auto%22%7D%7D%7D"

cat > "$USER_HOME/client-config.txt" << CLIENTEOF
vless://${UUID1}@${VPS_IP_URI}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#reality%2Bvision%20%E7%9B%B4%E8%BF%9E
vless://${UUID2}@${VPS_IP_URI}:443?encryption=${VLESSENC_ENCRYPTION}&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&mode=auto#xhttp%2BReality%20%E4%B8%8A%E4%B8%8B%E8%A1%8C%E4%B8%8D%E5%88%86%E7%A6%BB%20%EF%BC%88%E4%B8%8A%E8%A1%8C%E4%B8%BA%20stream-one%20%E6%A8%A1%E5%BC%8F%EF%BC%89
vless://${UUID2}@${CDN_DOMAIN}:443?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h2&insecure=0&allowInsecure=0&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_3}#%E4%B8%8A%E8%A1%8C%20xhttp%2BTLS%2BCDN%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BReality
vless://${UUID2}@${CDN_DOMAIN}:443?encryption=${VLESSENC_ENCRYPTION}&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h2&insecure=0&allowInsecure=0&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH}&mode=auto#xhttp%2Btls%20%E5%8F%8C%E5%90%91CDN
vless://${UUID2}@${VPS_IP_URI}:443?encryption=${VLESSENC_ENCRYPTION}&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_5}#%E4%B8%8A%E8%A1%8C%20xhttp%2BReality%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BTLS%2BCDN
CLIENTEOF

cat > "$USER_HOME/client-config-mihomo.yaml" << MIHOMOEOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: true
unified-delay: true

dns:
  enable: true
  listen: "0.0.0.0:1053"
  ipv6: true
  prefer-h3: false
  respect-rules: true
  use-system-hosts: false
  cache-algorithm: "arc"
  enhanced-mode: fake-ip
  fake-ip-range: "198.18.0.1/16"
  fake-ip-filter:
    - "+.lan"
    - "+.local"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "localhost.ptlogin2.qq.com"
    - "localhost.sec.qq.com"
    - "+.in-addr.arpa"
    - "+.ip6.arpa"
    - "time.*.com"
    - "time.*.gov"
    - "pool.ntp.org"
    - "localhost.work.weixin.qq.com"
  default-nameserver:
    - "223.5.5.5"
    - "1.2.4.8"
  nameserver:
    - "https://208.67.222.222/dns-query"
    - "https://77.88.8.8/dns-query"
    - "https://1.1.1.1/dns-query"
    - "https://8.8.4.4/dns-query"
  proxy-server-nameserver:
    - "https://223.5.5.5/dns-query"
    - "https://doh.pub/dns-query"
  direct-nameserver:
    - "https://223.5.5.5/dns-query"
    - "https://doh.pub/dns-query"
  nameserver-policy:
    "geosite:private,cn":
      - "https://223.5.5.5/dns-query"
      - "https://doh.pub/dns-query"

proxies:
  - name: "reality+vision 直连"
    type: vless
    server: "${VPS_IP}"
    port: 443
    uuid: "${UUID1}"
    udp: true
    tls: true
    flow: xtls-rprx-vision
    encryption: "none"
    network: tcp
    alpn:
      - h2
    servername: "${REALITY_DOMAIN}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"

  - name: "xhttp+Reality 上下行不分离"
    type: vless
    server: "${VPS_IP}"
    port: 443
    uuid: "${UUID2}"
    udp: true
    flow: ""
    tls: true
    encryption: "${VLESSENC_ENCRYPTION}"
    network: xhttp
    alpn:
      - h2
    servername: "${REALITY_DOMAIN}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"
    xhttp-opts:
      path: "${XHTTP_PATH}"
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"

  - name: "上行 xhttp+TLS+CDN | 下行 xhttp+Reality"
    type: vless
    server: "${CDN_DOMAIN}"
    port: 443
    uuid: "${UUID2}"
    udp: true
    flow: ""
    tls: true
    encryption: "${VLESSENC_ENCRYPTION}"
    network: xhttp
    alpn:
      - h2
    servername: "${CDN_DOMAIN}"
    client-fingerprint: chrome
    xhttp-opts:
      host: "${CDN_DOMAIN}"
      path: "${XHTTP_PATH}"
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
      download-settings:
        path: "${XHTTP_PATH}"
        server: "${VPS_IP}"
        port: 443
        tls: true
        alpn:
          - h2
        servername: "${REALITY_DOMAIN}"
        client-fingerprint: chrome
        reality-opts:
          public-key: "${PUBLIC_KEY}"
          short-id: "${SHORT_ID}"
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"

  - name: "xhttp+TLS 双向 CDN"
    type: vless
    server: "${CDN_DOMAIN}"
    port: 443
    uuid: "${UUID2}"
    udp: true
    flow: ""
    tls: true
    network: xhttp
    alpn:
      - h2
    servername: "${CDN_DOMAIN}"
    client-fingerprint: chrome
    encryption: "${VLESSENC_ENCRYPTION}"
    xhttp-opts:
      host: "${CDN_DOMAIN}"
      path: "${XHTTP_PATH}"
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"

  - name: "上行 xhttp+Reality | 下行 xhttp+TLS+CDN"
    type: vless
    server: "${VPS_IP}"
    port: 443
    uuid: "${UUID2}"
    udp: true
    flow: ""
    tls: true
    network: xhttp
    alpn:
      - h2
    servername: "${REALITY_DOMAIN}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"
    encryption: "${VLESSENC_ENCRYPTION}"
    xhttp-opts:
      host: "${CDN_DOMAIN}"
      path: "${XHTTP_PATH}"
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
      download-settings:
        host: "${CDN_DOMAIN}"
        path: "${XHTTP_PATH}"
        server: "${CDN_DOMAIN}"
        port: 443
        tls: true
        alpn:
          - h2
        servername: "${CDN_DOMAIN}"
        client-fingerprint: chrome
        reality-opts: { public-key: "" }
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"

proxy-groups:
  - name: "节点选择"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    include-all: true
    filter: "^(?!.*(官网|套餐|流量|异常|剩余)).*$"
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/adjust.svg"

  - name: "谷歌服务"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/google.svg"

  - name: "YouTube"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/youtube.svg"

  - name: "Netflix"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/netflix.svg"

  - name: "电报消息"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/telegram.svg"

  - name: "AI"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/chatgpt.svg"

  - name: "TikTok"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/tiktok.svg"

  - name: "微软服务"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "全局直连"
      - "节点选择"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/microsoft.svg"

  - name: "苹果服务"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/apple.svg"

  - name: "动画疯"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
    include-all: true
    filter: "(?i)台|tw|TW"
    icon: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/Bahamut.svg"

  - name: "哔哩哔哩港澳台"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "全局直连"
      - "节点选择"
    include-all: true
    filter: "^(?!.*(官网|套餐|流量|异常|剩余)).*$"
    icon: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/bilibili.svg"

  - name: "Spotify"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/icon/spotify.svg"

  - name: "广告过滤"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "REJECT"
      - "DIRECT"
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/bug.svg"

  - name: "全局直连"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "DIRECT"
      - "节点选择"
    include-all: true
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/link.svg"

  - name: "全局拦截"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "REJECT"
      - "DIRECT"
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/block.svg"

  - name: "漏网之鱼"
    type: select
    interval: 300
    timeout: 3000
    url: "https://www.google.com/generate_204"
    lazy: true
    max-failed-times: 3
    hidden: false
    proxies:
      - "节点选择"
      - "全局直连"
    include-all: true
    filter: "^(?!.*(官网|套餐|流量|异常|剩余)).*$"
    icon: "https://fastly.jsdelivr.net/gh/clash-verge-rev/clash-verge-rev.github.io@main/docs/assets/icons/fish.svg"

rule-providers:
  reject:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt"
    path: "./ruleset/loyalsoldier/reject.yaml"
  icloud:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt"
    path: "./ruleset/loyalsoldier/icloud.yaml"
  apple:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt"
    path: "./ruleset/loyalsoldier/apple.yaml"
  google:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/google.txt"
    path: "./ruleset/loyalsoldier/google.yaml"
  proxy:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt"
    path: "./ruleset/loyalsoldier/proxy.yaml"
  direct:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: "./ruleset/loyalsoldier/direct.yaml"
  private:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: "./ruleset/loyalsoldier/private.yaml"
  gfw:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: "./ruleset/loyalsoldier/gfw.yaml"
  tld-not-cn:
    type: http
    behavior: domain
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt"
    path: "./ruleset/loyalsoldier/tld-not-cn.yaml"
  telegramcidr:
    type: http
    behavior: ipcidr
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: "./ruleset/loyalsoldier/telegramcidr.yaml"
  cncidr:
    type: http
    behavior: ipcidr
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: "./ruleset/loyalsoldier/cncidr.yaml"
  lancidr:
    type: http
    behavior: ipcidr
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: "./ruleset/loyalsoldier/lancidr.yaml"
  applications:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt"
    path: "./ruleset/loyalsoldier/applications.yaml"
  bahamut:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/Bahamut.txt"
    path: "./ruleset/xiaolin-007/bahamut.yaml"
  YouTube:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/YouTube.txt"
    path: "./ruleset/xiaolin-007/YouTube.yaml"
  Netflix:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/Netflix.txt"
    path: "./ruleset/xiaolin-007/Netflix.yaml"
  Spotify:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/Spotify.txt"
    path: "./ruleset/xiaolin-007/Spotify.yaml"
  BilibiliHMT:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/BilibiliHMT.txt"
    path: "./ruleset/xiaolin-007/BilibiliHMT.yaml"
  AI:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/AI.txt"
    path: "./ruleset/xiaolin-007/AI.yaml"
  TikTok:
    type: http
    behavior: classical
    format: yaml
    interval: 86400
    url: "https://fastly.jsdelivr.net/gh/xiaolin-007/clash@main/rule/TikTok.txt"
    path: "./ruleset/xiaolin-007/TikTok.yaml"

rules:
  - DOMAIN-SUFFIX,googleapis.cn,节点选择
  - DOMAIN-SUFFIX,gstatic.com,节点选择
  - DOMAIN-SUFFIX,xn--ngstr-lra8j.com,节点选择
  - DOMAIN-SUFFIX,github.io,节点选择
  - DOMAIN,v2rayse.com,节点选择
  - RULE-SET,applications,全局直连
  - RULE-SET,private,全局直连
  - RULE-SET,reject,广告过滤
  - RULE-SET,icloud,微软服务
  - RULE-SET,apple,苹果服务
  - RULE-SET,YouTube,YouTube
  - RULE-SET,Netflix,Netflix
  - RULE-SET,bahamut,动画疯
  - RULE-SET,Spotify,Spotify
  - RULE-SET,BilibiliHMT,哔哩哔哩港澳台
  - RULE-SET,AI,AI
  - RULE-SET,TikTok,TikTok
  - RULE-SET,google,谷歌服务
  - RULE-SET,proxy,节点选择
  - RULE-SET,gfw,节点选择
  - RULE-SET,tld-not-cn,节点选择
  - RULE-SET,direct,全局直连
  - RULE-SET,lancidr,全局直连,no-resolve
  - RULE-SET,cncidr,全局直连,no-resolve
  - RULE-SET,telegramcidr,电报消息,no-resolve
  - GEOSITE,CN,全局直连
  - GEOIP,LAN,全局直连,no-resolve
  - GEOIP,CN,全局直连,no-resolve
  - MATCH,漏网之鱼
MIHOMOEOF

SUB_CONF_DIR="/etc/xhttp-cdn"
SUB_TOKEN_FILE="${SUB_CONF_DIR}/sub_token"
install -d -m 700 "$SUB_CONF_DIR"
if [[ -f "$SUB_TOKEN_FILE" ]]; then
  SUB_TOKEN=$(tr -d '\r\n' < "$SUB_TOKEN_FILE")
else
  SUB_TOKEN=$(openssl rand -hex 16)
  echo "$SUB_TOKEN" > "$SUB_TOKEN_FILE"
  chmod 600 "$SUB_TOKEN_FILE"
fi

SUB_DIR="/usr/local/nginx/html/sub/${SUB_TOKEN}"
install -d -m 755 "$SUB_DIR"
cp "$USER_HOME/client-config.txt" "$SUB_DIR/v2rayn-raw.txt"
base64 "$USER_HOME/client-config.txt" | tr -d '\n' > "$SUB_DIR/v2rayn.txt"
cp "$USER_HOME/client-config-mihomo.yaml" "$SUB_DIR/mihomo.yaml"

SUB_DIRECT_DOMAIN="${REALITY_DOMAIN}"
V2RAYN_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/v2rayn.txt"
MIHOMO_SUB_URL="https://${SUB_DIRECT_DOMAIN}/sub/${SUB_TOKEN}/mihomo.yaml"
V2RAYN_QR_FILE="${USER_HOME}/subscription-v2rayn.png"
MIHOMO_QR_FILE="${USER_HOME}/subscription-mihomo.png"

print_subscription_qr() {
  local label="$1"
  local url="$2"

  command -v qrencode >/dev/null 2>&1 || return 1

  echo -e "${YELLOW}[+] ${label} 订阅二维码（手机可直接扫描导入）${NC}"
  qrencode -t ANSIUTF8 -m 1 "$url"
  echo ""
}

save_subscription_qr_png() {
  local url="$1"
  local output_file="$2"

  command -v qrencode >/dev/null 2>&1 || return 1

  qrencode -o "$output_file" -s 8 -m 2 "$url"
}

check_subscription_url() {
  local domain="$1"
  local path="$2"
  local expected_file="$3"
  local label="$4"
  local tmp_body tmp_head http_code

  tmp_body=$(mktemp)
  tmp_head=$(mktemp)

  http_code=$(curl -k -sS --resolve "${domain}:443:127.0.0.1" \
    -D "$tmp_head" -o "$tmp_body" -w "%{http_code}" "https://${domain}${path}" || true)

  if [[ "$http_code" != "200" ]]; then
    warn "${label} 订阅自检失败，HTTP 状态码: ${http_code}"
    cat "$tmp_head" || true
    rm -f "$tmp_body" "$tmp_head"
    error "${label} 订阅链接不可用，请检查 Nginx / Xray / 域名配置"
  fi

  if ! cmp -s "$expected_file" "$tmp_body"; then
    rm -f "$tmp_body" "$tmp_head"
    error "${label} 订阅自检失败，返回内容与落盘文件不一致"
  fi

  rm -f "$tmp_body" "$tmp_head"
}

info "验证订阅链接..."
check_subscription_url "$SUB_DIRECT_DOMAIN" "/sub/${SUB_TOKEN}/v2rayn.txt" "$SUB_DIR/v2rayn.txt" "V2RayN(直连订阅)"
check_subscription_url "$SUB_DIRECT_DOMAIN" "/sub/${SUB_TOKEN}/mihomo.yaml" "$SUB_DIR/mihomo.yaml" "Mihomo(直连订阅)"
info "订阅链接自检通过"

echo -e "\n${CYAN}[+] 部署完成${NC}\n"
echo -e "${YELLOW}[+] 服务端参数${NC}"
echo "Reality 域名:   $REALITY_DOMAIN"
echo "CDN 域名:       $CDN_DOMAIN"
echo "VPS IP:         $VPS_IP"
echo "UUID1 (Vision): $UUID1"
echo "UUID2 (XHTTP):  $UUID2"
echo "Public Key:     $PUBLIC_KEY"
echo "Private Key:    $PRIVATE_KEY"
echo "Short ID:       $SHORT_ID"
echo "Path:           $XHTTP_PATH"
echo "VLESS Enc(客户端): $VLESSENC_ENCRYPTION"
echo "VLESS Dec(服务端): $VLESSENC_DECRYPTION"
echo ""
echo -e "\n${YELLOW}[+] 客户端节点，已保存到 $USER_HOME/client-config.txt${NC}"
cat "$USER_HOME/client-config.txt"
echo ""
echo -e "${YELLOW}[+] Mihomo 配置文件，已保存到 $USER_HOME/client-config-mihomo.yaml${NC}"
cat "$USER_HOME/client-config-mihomo.yaml"
echo ""
info "V2rayN 请导入 $USER_HOME/client-config.txt"
info "Mihomo 请导入 $USER_HOME/client-config-mihomo.yaml"
echo ""
echo -e "${YELLOW}[+] 订阅链接（Ctrl Shift + C 复制）${NC}"
echo "V2RayN / Shadowrocket 订阅: $V2RAYN_SUB_URL"
echo "Mihomo 订阅: $MIHOMO_SUB_URL"
info "订阅链接默认使用直连域名，适合客户端首次导入"
echo ""

if command -v qrencode >/dev/null 2>&1; then
  save_subscription_qr_png "$V2RAYN_SUB_URL" "$V2RAYN_QR_FILE" && \
    info "V2RayN / Shadowrocket 订阅二维码 PNG 已保存到 $V2RAYN_QR_FILE"
  save_subscription_qr_png "$MIHOMO_SUB_URL" "$MIHOMO_QR_FILE" && \
    info "Mihomo 订阅二维码 PNG 已保存到 $MIHOMO_QR_FILE"
  echo ""
  print_subscription_qr "V2RayN / Shadowrocket" "$V2RAYN_SUB_URL"
  print_subscription_qr "Mihomo" "$MIHOMO_SUB_URL"
else
  warn "未检测到 qrencode，已跳过订阅二维码输出"
fi

echo -e "${YELLOW}[+] 建议: 在 Cloudflare 配置缓存规则绕过 XHTTP 路径${NC}"
echo "  Cloudflare → 缓存 → Cache Rules → 创建缓存规则"
echo "  选择「自定义筛选表达式」→ 点击「编辑表达式」→ 输入:"
echo ""
echo "  (http.host eq \"${CDN_DOMAIN}\") or (http.request.uri.path contains \"${XHTTP_PATH}\")"
echo ""
echo "  缓存资格设置为「绕过缓存」→ 部署"
echo "  详细步骤请参考仓库的 1.环境配置.md 文档"
