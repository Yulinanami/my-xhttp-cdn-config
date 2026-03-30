#!/bin/bash
# ============================================================
# XHTTP + CDN 一键部署脚本
# 支持: Debian / Ubuntu
# 用法: bash install.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ==================== 检查环境 ====================
[[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   XHTTP + CDN 一键部署脚本${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${YELLOW}前置条件 (请确认已在 Cloudflare 完成):${NC}"
echo "  1. Reality 域名 DNS → 仅 DNS (灰色云朵)"
echo "  2. CDN 域名 DNS    → 代理开启 (橙色云朵)"
echo "  3. SSL/TLS 加密    → 完全(严格)"
echo "  4. 网络 → gRPC     → 已开启"
echo ""

read -rp "请输入 Reality 域名 (如 reality.example.com): " REALITY_DOMAIN
[[ -z "$REALITY_DOMAIN" ]] && error "域名不能为空"

read -rp "请输入 CDN 域名 (如 cdn.example.com): " CDN_DOMAIN
[[ -z "$CDN_DOMAIN" ]] && error "域名不能为空"

echo ""
info "Reality: $REALITY_DOMAIN"
info "CDN:     $CDN_DOMAIN"
echo ""

# ==================== [1/6] 基础环境 ====================
info "===== [1/6] 安装基础环境 ====="

apt update -y && apt upgrade -y
apt install -y curl sudo socat cron

info "安装 Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

info "生成参数..."
UUID1=$(xray uuid)
UUID2=$(xray uuid)
KEY_OUTPUT=$(xray x25519)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(echo "$UUID1" | tr -d '-' | cut -c1-8)
XHTTP_PATH="/$(echo "$UUID2" | tr -d '-' | cut -c1-8)"
VPS_IP=$(curl -4 -s ip.sb)

info "UUID1 (Vision): $UUID1"
info "UUID2 (XHTTP):  $UUID2"
info "Public Key:     $PUBLIC_KEY"
info "Short ID:       $SHORT_ID"
info "Path:           $XHTTP_PATH"
info "VPS IP:         $VPS_IP"
echo ""

# ==================== [2/6] SSL 证书 ====================
info "===== [2/6] 申请 SSL 证书 ====="

curl https://get.acme.sh | sh
ln -sf /root/.acme.sh/acme.sh /usr/local/bin/acme.sh

acme.sh --set-default-ca --server letsencrypt

info "申请双域名证书 (需要 80 端口空闲)..."
acme.sh --issue -d "$REALITY_DOMAIN" -d "$CDN_DOMAIN" --standalone

mkdir -p /etc/ssl/private
acme.sh --install-cert -d "$REALITY_DOMAIN" --ecc \
  --key-file /etc/ssl/private/private.key \
  --fullchain-file /etc/ssl/private/fullchain.cer

echo ""

# ==================== [3/6] 编译 Nginx ====================
info "===== [3/6] 编译安装 Nginx ====="

info "安装编译依赖..."
apt-get install -y gcc g++ libpcre3 libpcre3-dev zlib1g zlib1g-dev openssl libssl-dev wget make 2>/dev/null || \
  apt-get install -y gcc g++ libpcre2-dev zlib1g-dev libssl-dev wget make

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
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable nginx.service
echo ""

# ==================== [4/6] 配置文件 ====================
info "===== [4/6] 生成配置文件 ====="

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
                "decryption": "none"
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

# ==================== [5/6] 启动服务 ====================
info "===== [5/6] 启动服务 ====="

info "测试 Nginx 配置..."
nginx -t

info "测试 Xray 配置..."
xray -test -config /usr/local/etc/xray/config.json

info "启动服务..."
systemctl restart xray
systemctl restart nginx

systemctl is-active --quiet xray && info "Xray 运行中" || warn "Xray 启动失败"
systemctl is-active --quiet nginx && info "Nginx 运行中" || warn "Nginx 启动失败"

echo ""

# ==================== [6/6] 客户端配置 ====================
info "===== [6/6] 生成客户端配置 ====="

# URL 编码路径中的 /
XHTTP_PATH_ENC=$(printf '%s' "$XHTTP_PATH" | sed 's|/|%2F|g')

# 模式3 extra: 上行 CDN, 下行 Reality
EXTRA_3="%7B%22downloadSettings%22%3A%7B%22address%22%3A%22${VPS_IP}%22%2C%22port%22%3A443%2C%22network%22%3A%22xhttp%22%2C%22security%22%3A%22reality%22%2C%22realitySettings%22%3A%7B%22show%22%3Afalse%2C%22serverName%22%3A%22${REALITY_DOMAIN}%22%2C%22fingerprint%22%3A%22chrome%22%2C%22shortId%22%3A%22${SHORT_ID}%22%2C%22publicKey%22%3A%22${PUBLIC_KEY}%22%7D%2C%22xhttpSettings%22%3A%7B%22host%22%3A%22%22%2C%22path%22%3A%22${XHTTP_PATH_ENC}%22%2C%22mode%22%3A%22auto%22%7D%7D%7D"

# 模式5 extra: 上行 Reality, 下行 CDN
EXTRA_5="%7B%22downloadSettings%22%3A%7B%22address%22%3A%22${CDN_DOMAIN}%22%2C%22port%22%3A443%2C%22network%22%3A%22xhttp%22%2C%22security%22%3A%22tls%22%2C%22tlsSettings%22%3A%7B%22serverName%22%3A%22${CDN_DOMAIN}%22%2C%22allowInsecure%22%3Afalse%2C%22alpn%22%3A%5B%22h2%22%5D%2C%22fingerprint%22%3A%22chrome%22%7D%2C%22xhttpSettings%22%3A%7B%22host%22%3A%22${CDN_DOMAIN}%22%2C%22path%22%3A%22${XHTTP_PATH_ENC}%22%2C%22mode%22%3A%22auto%22%7D%7D%7D"

cat > ~/client-config.txt << CLIENTEOF
vless://${UUID1}@${VPS_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#reality%2Bvision%20%E7%9B%B4%E8%BF%9E
vless://${UUID2}@${VPS_IP}:443?encryption=none&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&mode=auto#xhttp%2BReality%20%E4%B8%8A%E4%B8%8B%E8%A1%8C%E4%B8%8D%E5%88%86%E7%A6%BB%20%EF%BC%88%E4%B8%8A%E8%A1%8C%E4%B8%BA%20stream-one%20%E6%A8%A1%E5%BC%8F%EF%BC%89
vless://${UUID2}@${CDN_DOMAIN}:443?encryption=none&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h2&insecure=0&allowInsecure=0&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_3}#%E4%B8%8A%E8%A1%8C%20xhttp%2BTLS%2BCDN%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BReality
vless://${UUID2}@${CDN_DOMAIN}:443?encryption=none&security=tls&sni=${CDN_DOMAIN}&fp=chrome&alpn=h2&insecure=0&allowInsecure=0&type=xhttp&host=${CDN_DOMAIN}&path=${XHTTP_PATH}&mode=auto#xhttp%2Btls%20%E5%8F%8C%E5%90%91CDN
vless://${UUID2}@${VPS_IP}:443?encryption=none&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${XHTTP_PATH}&mode=auto&extra=${EXTRA_5}#%E4%B8%8A%E8%A1%8C%20xhttp%2BReality%20%7C%20%E4%B8%8B%E8%A1%8C%20xhttp%2BTLS%2BCDN
CLIENTEOF

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}            部署完成${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${YELLOW}===== 服务端参数 =====${NC}"
echo "Reality 域名:   $REALITY_DOMAIN"
echo "CDN 域名:       $CDN_DOMAIN"
echo "VPS IP:         $VPS_IP"
echo "UUID1 (Vision): $UUID1"
echo "UUID2 (XHTTP):  $UUID2"
echo "Public Key:     $PUBLIC_KEY"
echo "Private Key:    $PRIVATE_KEY"
echo "Short ID:       $SHORT_ID"
echo "Path:           $XHTTP_PATH"
echo ""
echo -e "${YELLOW}===== 客户端节点 (已保存到 ~/client-config.txt) =====${NC}"
cat ~/client-config.txt
echo ""
info "将以上节点复制到 V2rayN 即可使用"
