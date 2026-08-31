# XHTTP + CDN 上下行分离配置指南

> **推荐文章1**：关于XHTTP的原理，上下行分离，以及带来的抗审查优势：https://habr.com/en/articles/990208/
> 
> **推荐文章2**：关于DNS泄露：https://github.com/meooxx/blog/issues/31
>
> **注意**：教程使用 VLESS Encryption，客户端（V2rayN、Mihomo客户端）也需要更新到支持 vlessenc / xhttp 的版本。
>
> **注意**：V2rayN v7.19.5+版本 TUN 模式下链路不稳定，可能需要启用旧版TUN保护选项。
> PR：https://github.com/2dust/v2rayN/pull/9005

这个仓库用于整理一套443端口上基于 Xray-core 的 XHTTP + CDN 搭建方案，覆盖环境准备、服务端配置和客户端模板三部分内容。
支持小火箭、Xray和Mihomo客户端，支持IPv4和IPv6。

## 模式

仓库文档用于搭建包含以下 5 种模式：

1. Reality Vision 直连
2. XHTTP + Reality 上下行不分离
3. 上行 XHTTP + TLS + CDN，下行 XHTTP + Reality
4. XHTTP + TLS + H2
5. 上行 XHTTP + Reality，下行 XHTTP + TLS + CDN

## 安全性

- VLESS Encryption：启用 VLESS Encryption，防止 CDN 中间人解密流量内容
- 对 XHTTP 入站启用 vlessenc（因为只有它过 CDN），Vision 直连不需要
- 主脚本可选择由 Nginx 反向代理回落网站，或直接返回用户上传的 `dist` 静态页面
- 配置 `xpadding` 以绕过 CDN 的潜在检测
- 配置 `ECH` 以加密 TLS 握手时的 SNI

## 流程图（去程 + 回程）

客户端与服务器连接流程图请看：[流程图.md](./docs/5.流程图.md)

## 手动部署（以Ubuntu24.04为例）

按下面的顺序阅读和执行：

1. [环境配置.md](./docs/1.环境配置.md)，完成 Cloudflare 设置、Xray 安装、证书申请和 Nginx 安装。
2. [文件配置.md](./docs/2.文件配置.md)，完成 Nginx 与 Xray 配置，并执行测试与重启命令。
3. [xpadding配置.md](./docs/3.xpadding配置.md)，带 `xpadding` 的版本，按此文档补充 Xray / v2rayN / Mihomo 配置。
4. [ECH配置.md](./docs/4.ECH配置.md)，给 CDN-TLS 节点启用 ECH，按此文档补充客户端配置。
5. [拓展-上下行不同CDN.md](./docs/6.拓展-上下行不同CDN.md)，可选扩展：上行 CDN-A / 下行 CDN-B。
6. [拓展-上下行IPv4IPv6.md](./docs/7.拓展-上下行IPv4IPv6.md)，可选扩展：上行 IPv4 / 下行 IPv6。
7. [拓展-XHTTP-H3.md](./docs/8.拓展-XHTTP-H3.md)，可选扩展：XHTTP H3、H2/H3 上下行分离。
8. [拓展-Hysteria2.md](./docs/9.拓展-Hysteria2.md)，可选扩展：Hysteria2。
9. [卸载.md](./docs/9.卸载.md)，卸载指令，用于卸载前面搭建 Xray、Nginx、ACME 和 Hysteria2。
10. [客户端模板.txt](./客户端模板.txt)，复制到 V2rayN，替换 `YOUR_*` 占位符后使用。
11. [客户端模板-mihomo.yaml](./客户端模板-mihomo.yaml)，Mihomo内核客户端的配置文件，替换 `YOUR_*` 占位符后导入。

---

## 脚本部署

> **提示**：脚本可以重新执行即可更新域名、回落网站等参数。
> 运行脚本前需在 Cloudflare 完成以下设置：
>
> 1. Reality 域名 DNS → 仅 DNS（灰色云朵）
> 2. CDN 域名 DNS → 代理开启（橙色云朵）
> 3. SSL/TLS 加密 → 完全（严格）
> 4. 网络 → gRPC → 已开启
> 5. 缓存规则（建议） → 将 XHTTP 路径设为绕过缓存，具体步骤请参考Github仓库的 [环境配置.md](./docs/1.环境配置.md)。

将 `dist` 文件夹上传到 `/var/www/`，每个入口域名使用独立的 `/var/www/dist/<域名>/index.html`；可用 [SingleFile](https://chromewebstore.google.com/detail/singlefile/mpiodijhokgodhhofbcjdecpffjipkle?hl=zh-CN&utm_source=ext_sidebar) 抓取网页。

在 VPS (Debian/Ubuntu) 上执行：

### 普通 XHTTP + TLS + CDN

> **注意**：需要 Mihomo 内核版本≥1.19.23。

```bash
sudo -i
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/install.sh -o ~/install.sh
bash ~/install.sh
```

Alpine Linux：

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/install.sh -o ~/install.sh
bash ~/install.sh
```

---

### 带 xpadding 的 XHTTP

> **提示**：xpadding 默认开启；ECH 可选，默认关闭
> **注意**：需要 Xray 内核版本≥`26.2.6`，Mihomo 内核版本≥`1.19.24`。

```bash
sudo -i
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/install-xpadding.sh -o ~/install-xpadding.sh
bash ~/install-xpadding.sh
```

Alpine Linux：

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/install-xpadding.sh -o ~/install-xpadding.sh
bash ~/install-xpadding.sh
```

---

### 扩展脚本

主脚本部署完成后，可按需追加新模式；扩展脚本会复用已有 `UUID / Path / VLESS Encryption`，并更新客户端配置和订阅。

#### 上行 CDN-A | 下行 CDN-B

```bash
sudo -i
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-dual-cdn.sh -o ~/add-dual-cdn.sh
bash ~/add-dual-cdn.sh
```

Alpine Linux：

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-dual-cdn.sh -o ~/add-dual-cdn.sh
bash ~/add-dual-cdn.sh
```

- 同步：`xpadding`；ECH 可选复用，默认关闭
- 输入：`CDN-A / CDN-B`
- 回落：每个新增 CDN 域名单独配置

#### 上行 IPv4 | 下行 IPv6 (需要 vps 拥有 IPv4 和 IPv6)

```bash
sudo -i
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-dual-ip.sh -o ~/add-dual-ip.sh
bash ~/add-dual-ip.sh
```

Alpine Linux：

```sh

doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-dual-ip.sh -o ~/add-dual-ip.sh
bash ~/add-dual-ip.sh
```

- 同步：`xpadding`
- 输入：`IPv4 Reality 域名 / IPv6 Reality 域名`
- 回落：每个新增 Reality 域名单独配置

#### XHTTP H3 / H2-H3 上下行分离

Debian / Ubuntu：

```bash
sudo -i
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-quic.sh -o ~/add-quic.sh
bash ~/add-quic.sh
```

Alpine Linux：

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

#### Hysteria2

Debian / Ubuntu：

```bash
sudo -i
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-hysteria2.sh -o ~/add-hysteria2.sh
bash ~/add-hysteria2.sh
```

Alpine Linux：

```sh
doas -s
apk add --no-cache bash curl
curl -fsSL https://github.com/Yulinanami/my-xhttp-cdn-config/releases/latest/download/add-hysteria2.sh -o ~/add-hysteria2.sh
bash ~/add-hysteria2.sh
```

- 端口：输入 `1-65535`，默认 8443，不能与 XHTTP H3 相同
- 节点：Hysteria2 直连

---

### 输出文件

脚本会生成：

- `~/client-config.txt`：V2RayN / Shadowrocket 节点
- `~/client-config-mihomo-full.yaml`：Mihomo 完整分流配置
- `~/client-config-mihomo-nodes.yaml`：Mihomo 纯节点配置
- `~/subscription-links.txt`：订阅链接汇总
- `~/subscription-*.png`：订阅二维码

已有 Mihomo 配置的用户，建议使用 `mihomo-nodes.yaml`。

---

## 个人开发与发布

修改模块或模板后，在仓库根目录运行代码以构建搭建脚本：

```bash
bash .github/scripts/build-install.sh
bash .github/scripts/build-dual-cdn.sh
bash .github/scripts/build-dual-ip.sh
bash .github/scripts/build-quic.sh
bash .github/scripts/build-hysteria2.sh
```

会在 `dist/` 目录生成：

- `install.sh`
- `install-xpadding.sh`
- `add-dual-cdn.sh`
- `add-dual-ip.sh`
- `add-quic.sh`
- `add-hysteria2.sh`

---

## 参考资料

### Xray-xhttp

- Xray 小白搭建教程：[https://xtls.github.io/document/level-0/ch06-certificates.html](https://xtls.github.io/document/level-0/ch06-certificates.html) 、[https://xtls.github.io/document/level-0/ch07-xray-server.html](https://xtls.github.io/document/level-0/ch07-xray-server.html)
- Xray-core XHTTP 官方讨论 XHTTP: Beyond REALITY：[https://github.com/XTLS/Xray-core/discussions/4113](https://github.com/XTLS/Xray-core/discussions/4113)
- Xray-core XHTTP + CDN 上下行分离讨论：[https://github.com/XTLS/Xray-core/discussions/4118](https://github.com/XTLS/Xray-core/discussions/4118)
- XHTTP + CDN 上下行分离手搓参考：[https://jollyroger.top/sites/361.html](https://jollyroger.top/sites/361.html)

### Mihomo-xhttp

- Mihomo v1.19.24 Release：[https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.24](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.24)
- Mihomo XHTTP 讨论：[https://github.com/MetaCubeX/mihomo/discussions/2669](https://github.com/MetaCubeX/mihomo/discussions/2669)
- Mihomo 文档（VLESS）：[https://wiki.metacubex.one/config/proxies/vless/](https://wiki.metacubex.one/config/proxies/vless/)
- Mihomo 文档（Transport）：[https://wiki.metacubex.one/config/proxies/transport/](https://wiki.metacubex.one/config/proxies/transport/)
- Mihomo 文档（TLS）：[https://wiki.metacubex.one/config/proxies/tls/](https://wiki.metacubex.one/config/proxies/tls/)
- Mihomo 官方配置示例 `docs/config.yaml`：[https://github.com/MetaCubeX/mihomo/blob/Meta/docs/config.yaml](https://github.com/MetaCubeX/mihomo/blob/Meta/docs/config.yaml)
- Mihomo 分流规则配置参考：[https://github.com/xiaolin-007/clash-verge-script](https://github.com/xiaolin-007/clash-verge-script)

### xpadding

- Xray-core v26.2.6 Release：[https://github.com/XTLS/Xray-core/releases/tag/v26.2.6](https://github.com/XTLS/Xray-core/releases/tag/v26.2.6)
- Xray-core Solution to the xpadding leak：[https://github.com/XTLS/Xray-core/issues/4346](https://github.com/XTLS/Xray-core/issues/4346)
- XTLS/BBS 重拳出击XHTTP！科福瑞的忠实用户应该如何应对？：[https://github.com/XTLS/BBS/issues/25](https://github.com/XTLS/BBS/issues/25)
- Mihomo v1.19.24 Release：[https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.24](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.24)
- Mihomo 文档（Transport）：[https://wiki.metacubex.one/config/proxies/transport/](https://wiki.metacubex.one/config/proxies/transport/)
- Mihomo 官方配置示例 `docs/config.yaml`：[https://github.com/MetaCubeX/mihomo/blob/Meta/docs/config.yaml](https://github.com/MetaCubeX/mihomo/blob/Meta/docs/config.yaml)

### ECH

- Cloudflare ECH 文档：[https://developers.cloudflare.com/ssl/edge-certificates/ech/](https://developers.cloudflare.com/ssl/edge-certificates/ech/)
- Xray-core v25.7.26 Release（TLS client/server 支持 ECH）：[https://github.com/XTLS/Xray-core/releases/tag/v25.7.26](https://github.com/XTLS/Xray-core/releases/tag/v25.7.26)
- Xray-core v26.3.27 Release（ECH 查询行为调整）：[https://github.com/XTLS/Xray-core/releases/tag/v26.3.27](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)
- Xray TLSObject 文档（`echConfigList` / `echForceQuery`）：[https://xtls.github.io/config/transport.html](https://xtls.github.io/config/transport.html)
- Xray VLESS 分享链接标准（`ech` 对应 `echConfigList`）：[https://github.com/XTLS/Xray-core/discussions/716](https://github.com/XTLS/Xray-core/discussions/716)
- Mihomo ECH：[https://github.com/MetaCubeX/mihomo/blob/Meta/adapter/outbound/ech.go](https://github.com/MetaCubeX/mihomo/blob/Meta/adapter/outbound/ech.go)
