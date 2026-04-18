# XHTTP + CDN 配置指南

这个仓库用于整理一套基于 Xray-core 的 XHTTP + CDN 搭建方案，覆盖环境准备、服务端配置和客户端模板三部分内容。
支持小火箭、Xray和Mihomo客户端。

## 仓库文档

- [1.环境配置.md](./1.环境配置.md)：环境准备、Cloudflare 前置设置、Acme.sh 证书申请、Nginx 编译安装。
- [2.文件配置.md](./2.文件配置.md)：Nginx 反向代理配置、Xray 服务端配置。
- [客户端模板.txt](./客户端模板.txt)：客户端连接模板，包含 5 种常见连接模式。
- [客户端模板-mihomo.yaml](./客户端模板-mihomo.yaml)：Mihomo 客户端完整 YAML 模板。
- [install.sh](./install.sh)：一键部署脚本，自动完成全部安装配置并生成 V2rayN / Mihomo 客户端配置。

## 一键部署

在 VPS (Debian/Ubuntu) 上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Yulinanami/my-xhttp-cdn-config/refs/heads/master/install.sh)
```

或者下载后运行：

```bash
wget -O install.sh https://raw.githubusercontent.com/Yulinanami/my-xhttp-cdn-config/refs/heads/master/install.sh && bash install.sh
```

脚本会提示输入两个域名，其余参数（UUID、密钥、shortId、路径）全部自动生成。完成后会同时生成：

- `~/client-config.txt`：V2rayN / Shadowrocket 可用的 Xray URI 节点
- `~/client-config-mihomo.yaml`：Mihomo 可直接导入的 YAML 配置

同时会输出订阅地址，默认使用 `REALITY_DOMAIN`：

- `v2rayn.txt`：适用于 **V2RayN / Shadowrocket**
- `mihomo.yaml`：适用于 **Mihomo**

**前置条件**：运行脚本前需在 Cloudflare 完成以下设置：
1. Reality 域名 DNS → 仅 DNS（灰色云朵）
2. CDN 域名 DNS → 代理开启（橙色云朵）
3. SSL/TLS 加密 → 完全（严格）
4. 网络 → gRPC → 已开启
5. 缓存规则（建议） → 将 XHTTP 路径设为绕过缓存，具体步骤请参考Github仓库的[环境配置.md](./1.环境配置.md)。

> **注意**：教程使用 VLESS Encryption，客户端（V2rayN、Mihomo客户端）也需要更新到支持 vlessenc / xhttp 的新版本。
>
> **Mihomo 版本要求**：建议直接使用 **Mihomo v1.19.23或更新版本**。

## 手动部署

按下面的顺序阅读和执行：

1. [环境配置.md](./1.环境配置.md)，完成 Cloudflare 设置、Xray 安装、证书申请和 Nginx 安装。
2. [文件配置.md](./2.文件配置.md)，完成 Nginx 与 Xray 配置，并执行测试与重启命令。
3. [客户端模板.txt](./客户端模板.txt)，复制到 V2rayN，替换 `YOUR_*` 占位符后使用。
4. [客户端模板-mihomo.yaml](./客户端模板-mihomo.yaml)，Mihomo内核客户端的配置文件，替换 `YOUR_*` 占位符后导入。
5. 如需核对 Mihomo 字段来源，可先阅读 [docs/mihomo-official/README.md](./docs/mihomo-official/README.md)。

## 模式

[客户端模板.txt](./客户端模板.txt) 与 [客户端模板-mihomo.yaml](./客户端模板-mihomo.yaml) 当前都包含以下 5 种模式：

1. Reality Vision 直连
2. XHTTP + Reality 上下行不分离
3. 上行 XHTTP + TLS + CDN，下行 XHTTP + Reality
4. XHTTP + TLS 双向 CDN
5. 上行 XHTTP + Reality，下行 XHTTP + TLS + CDN

## 安全特性

- **VLESS Encryption (vlessenc)**：脚本自动启用 VLESS Encryption，在 VLESS 协议层增加端到端加密（ML-KEM-768 + X25519 后量子安全算法 + PFS），防止 CDN 中间人解密流量内容
- **Reality**：直连模式使用 REALITY 协议，防止主动探测
- 仅对 XHTTP 入站启用 vlessenc（因为只有它过 CDN），Vision 直连不需要

## 流程图（去程 + 回程）

```mermaid
graph TD
	START2("外部请求到达 VPS:443")

	START2 -->|"代理软件请求"| PROXY["客户端代理请求"]
	START2 -->|"防火墙主动探测"| PROBEX["探测请求"]

	PROXY -->|"模式 1 Vision 直连<br/>模式 2 / 5 上行 XHTTP+Reality<br/>直连 VPS:443"| GFWD["穿过防火墙"]
	GFWD --> XR443["Xray 443<br/>VLESS + Reality<br/>serverNames: REALITY_DOMAIN"]

	PROXY -->|"模式 3 上行 / 模式 4<br/>XHTTP+TLS+CDN<br/>连接 CDN 域名:443"| GFWC["穿过防火墙"]
	GFWC --> CF["Cloudflare CDN"]
	CF -->|"回源 VPS:443"| XR443C["Xray 443"]
	XR443C -->|"非 Reality<br/>target:8003 转发"| NG8003["Nginx 8003<br/>server_name: CDN_DOMAIN"]

	XR443 --> VISION{"UUID1 + Vision?"}
	VISION -->|"是<br/>flow: xtls-rprx-vision"| HANDLE443["Xray 443 处理 UUID1 代理请求<br/>模式 1 Reality+Vision 直连到达"]
	HANDLE443 --> OUT2("Xray outbound direct<br/>到达目标网站")

	VISION -->|"否<br/>fallback dest:8001"| XR8001A["Xray 8001<br/>127.0.0.1:8001<br/>VLESS + XHTTP<br/>UUID2 path: XHTTP_PATH<br/>模式 2 / 5 上行 XHTTP+Reality 到达"]
	XR8001A --> OUT2

	NG8003 --> PATHCHK{"location 匹配<br/>XHTTP_PATH?"}
	PATHCHK -->|"是"| GRPC["grpc_pass 127.0.0.1:8001"]
	GRPC --> XR8001B["Xray 8001<br/>VLESS + XHTTP<br/>模式 3 上行 / 模式 4 XHTTP+TLS+CDN 到达"]
	XR8001B --> OUT2
	PATHCHK -->|"否<br/>location /"| HARVARD["proxy_pass harvard.edu"]
	HARVARD --> HVSITE["返回哈佛官网页面"]

	PROBEX -->|"探测 Reality 域名<br/>直连 VPS:443"| XR443P["Xray 443"]
	XR443P -->|"非 Reality<br/>target:8003 转发"| NG8003R["Nginx 8003<br/>server_name: REALITY_DOMAIN"]
	NG8003R -->|"location /"| STANFORD["proxy_pass stanford.edu"]
	STANFORD --> STSITE["返回斯坦福官网页面"]

	PROBEX -->|"探测 CDN 域名<br/>DNS 走橙色云朵"| CFC["Cloudflare CDN"]
	CFC -->|"回源 VPS:443"| XR443C2["Xray 443"]
	XR443C2 -->|"非 Reality<br/>target:8003 转发"| NG8003C["Nginx 8003<br/>server_name: CDN_DOMAIN"]
	NG8003C -->|"location /"| HARVARD2["proxy_pass harvard.edu"]
	HARVARD2 --> HVSITE2["返回哈佛官网页面"]

	OUT2 -->|"响应返回"| RESP("目标网站响应")

	RESP -->|"模式 1<br/>沿 Reality+Vision 原连接返回"| RXR443["Xray 443"] --> RFWD["穿过防火墙"] --> CLIENT("客户端收到响应")

	RESP -->|"模式 2<br/>沿 XHTTP+Reality 原连接返回"| RXR8001A["Xray 8001"] --> RXR443A["Xray 443"] --> RFWR["穿过防火墙"] --> CLIENT

	RESP -->|"模式 3 下行<br/>downloadSettings 另建下行连接"| DS3["客户端另建下行连接<br/>address: VPS_IP:443<br/>network: xhttp<br/>security: reality<br/>serverName: REALITY_DOMAIN<br/>path: XHTTP_PATH"]
	subgraph SUB3 ["模式 3 下行连接建立"]
	DS3 --> DS3FW["穿过防火墙"] --> DS3XR443["Xray 443<br/>VLESS + Reality<br/>serverNames: REALITY_DOMAIN"] --> DS3VISION{"UUID1 + Vision?"}
	DS3VISION -->|"否<br/>fallback dest:8001"| DS3XR8001["Xray 8001<br/>127.0.0.1:8001<br/>VLESS + XHTTP<br/>UUID2 匹配<br/>path: XHTTP_PATH 匹配<br/>下行连接建立"]
	end
	RESP -->|"模式 3 下行<br/>XHTTP+Reality"| R3XR8001["Xray 8001"] --> DS3R443["Xray 443"] --> DS3RFW["穿过防火墙"] --> CLIENT

	RESP -->|"模式 4<br/>沿 XHTTP+TLS+CDN 原连接返回"| RXR8001D["Xray 8001"] --> RNG4["Nginx 8003<br/>grpc 响应"] --> RXR443D["Xray 443"] --> RCDN4["Cloudflare CDN"] --> RFWC4["穿过防火墙"] --> CLIENT

	RESP -->|"模式 5 下行<br/>downloadSettings 另建下行连接"| DS5["客户端另建下行连接<br/>address: CDN_DOMAIN:443<br/>network: xhttp<br/>security: tls<br/>serverName: CDN_DOMAIN<br/>path: XHTTP_PATH"]
	subgraph SUB5 ["模式 5 下行连接建立"]
	DS5 --> DS5FW["穿过防火墙"] --> DS5CDN["Cloudflare CDN"] --> DS5XR443["Xray 443<br/>非 Reality<br/>target:8003 转发"] --> DS5NG["Nginx 8003<br/>server_name: CDN_DOMAIN"] --> DS5PATH{"location 匹配<br/>XHTTP_PATH?"}
	DS5PATH -->|"是"| DS5GRPC["grpc_pass 127.0.0.1:8001"] --> DS5XR8001["Xray 8001<br/>127.0.0.1:8001<br/>VLESS + XHTTP<br/>UUID2 匹配<br/>path: XHTTP_PATH 匹配<br/>下行连接建立"]
	end
	RESP -->|"模式 5 下行<br/>XHTTP+TLS+CDN"| R5XR8001["Xray 8001"] --> DS5RNG["Nginx 8003<br/>grpc 响应"] --> DS5R443["Xray 443"] --> DS5RCDN["Cloudflare CDN"] --> DS5RFW["穿过防火墙"] --> CLIENT
```

### 订阅链接获取流程

脚本会在 `/usr/local/nginx/html/sub/` 目录下生成随机 Token 文件夹，存放客户端配置文件。默认订阅地址为：

- `https://REALITY_DOMAIN/sub/TOKEN/v2rayn.txt`
- `https://REALITY_DOMAIN/sub/TOKEN/mihomo.yaml`

```mermaid
graph TD
	SUB_START("客户端请求订阅链接")
	
	SUB_START -->|"直接请求<br/>https://REALITY_DOMAIN/sub/TOKEN/..."| SUB_XR443["Xray 443<br/>(VPS 监听)"]
	
	SUB_XR443 -->|"普通 TLS 握手<br/>转发至 target:8003"| SUB_NG8003["Nginx 8003<br/>(处理 HTTPS)"]
	
	SUB_NG8003 -->|"解析 HTTP URI"| SUB_NG_MATCH{"匹配 Nginx location"}
	
	SUB_NG_MATCH -->|"1. 匹配 location ^~ /sub/<br/>(订阅链接路径)"| SUB_NG_STATIC["静态文件处理<br/>root /usr/local/nginx/html"]
	SUB_NG_MATCH -->|"2. 匹配 location /XHTTP_PATH<br/>(代理流量)"| SUB_NG_GRPC["grpc_pass 至 127.0.0.1:8001<br/>交由 Xray 处理"]
	SUB_NG_MATCH -->|"3. 匹配 location /<br/>(主动探测防范)"| SUB_NG_PROXY["proxy_pass 伪装站<br/>(哈佛/斯坦福)"]
	
	SUB_NG_STATIC -->|"读取对应配置"| SUB_FILE[("/usr/local/nginx/html/sub/TOKEN/<br/>v2rayn.txt 或 mihomo.yaml")]
	
	SUB_FILE -->|"返回文件内容"| SUB_END("客户端成功获取订阅配置")
```

## 注意事项

- 文档中的占位符需要全部替换后再使用。

## 参考资料

- Xray小白搭建教程： https://xtls.github.io/document/level-0/ch06-certificates.html 和 https://xtls.github.io/document/level-0/ch07-xray-server.html
- Xray-core Xhttp-CDN 上下行分离讨论: https://github.com/XTLS/Xray-core/discussions/4118
- Xhttp-CDN 上下行分离手搓: https://jollyroger.top/sites/361.html
- Mihomo xhttp 讨论: https://github.com/MetaCubeX/mihomo/discussions/2669
- Mihomo 文档（VLESS / 传输层 / TLS）: https://wiki.metacubex.one/config/proxies/vless/ 、https://wiki.metacubex.one/config/proxies/transport/ 、https://wiki.metacubex.one/config/proxies/tls/
- Mihomo 分流规则配置: https://github.com/xiaolin-007/clash-verge-script
