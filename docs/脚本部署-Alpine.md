# 脚本部署（Alpine Linux）

Alpine 用 OpenRC（`rc-service`），不用 `systemctl`。先装 `bash` 和 `curl`。

在 VPS 上执行：

## 1. 普通 XHTTP + TLS + CDN

> **注意**：需要 Mihomo 内核版本≥1.19.23。

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/install.sh -o ~/install.sh
bash ~/install.sh
```

---

## 2. 带 xpadding 的 XHTTP

> **提示**：xpadding 默认开启；ECH 可选，默认关闭
> **注意**：需要 Xray 内核版本≥`26.2.6`，Mihomo 内核版本≥`1.19.24`。

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/install-xpadding.sh -o ~/install-xpadding.sh
bash ~/install-xpadding.sh
```

---

## 扩展脚本

主脚本跑完再加。UUID / Path / VLESS Encryption 沿用，客户端配置和订阅一起改。

### 1. 上行 CDN-A | 下行 CDN-B

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-dual-cdn.sh -o ~/add-dual-cdn.sh
bash ~/add-dual-cdn.sh
```

- 同步：`xpadding`；ECH 可选复用，默认关闭
- 输入：`CDN-A / CDN-B`
- 回落：每个新增 CDN 域名单独配置

### 2. 上行 IPv4 | 下行 IPv6 (需要 vps 拥有 IPv4 和 IPv6)

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-dual-ip.sh -o ~/add-dual-ip.sh
bash ~/add-dual-ip.sh
```

- 同步：`xpadding`
- 输入：`IPv4 Reality 域名 / IPv6 Reality 域名`
- 回落：每个新增 Reality 域名单独配置

### 3. XHTTP H3 / H2-H3 上下行分离

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-quic.sh -o ~/add-quic.sh
bash ~/add-quic.sh
```

- 复用：已有 `xhttp+TLS+H2` 节点的域名、UUID、VLESS Encryption、XHTTP Path、xpadding；ECH 可选复用，默认关闭
- 端口：输入 `1-65535`，默认 443，不能与 Hysteria2 相同
- TLS：XHTTP H3 由 Nginx 处理
- 节点：XHTTP H3、上行 H2/下行 H3、上行 H3/下行 H2

### 4. Hysteria2

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-hysteria2.sh -o ~/add-hysteria2.sh
bash ~/add-hysteria2.sh
```

- 端口：输入 `1-65535`，默认 8443，不能与 XHTTP H3 相同
- 节点：Hysteria2 直连
