# XHTTP + CDN 配置指南

这个仓库用于整理一套基于 Xray-core 的 XHTTP + CDN 搭建方案，覆盖环境准备、服务端配置和客户端模板三部分内容。

## 仓库文档

- [1.环境配置.md](./1.环境配置.md)：环境准备、Cloudflare 前置设置、Acme.sh 证书申请、Nginx 编译安装。
- [2.文件配置.md](./2.文件配置.md)：Nginx 反向代理配置、Xray 服务端配置。
- [客户端模板.txt](./客户端模板.txt)：客户端连接模板，包含 5 种常见连接模式。
- [install.sh](./install.sh)：一键部署脚本，自动完成全部安装配置并生成客户端节点。

## 一键部署

在 VPS (Debian/Ubuntu) 上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Yulinanami/my-xhttp-cdn-config/refs/heads/master/install.sh)
```

或者下载后运行：

```bash
wget -O install.sh https://raw.githubusercontent.com/Yulinanami/my-xhttp-cdn-config/refs/heads/master/install.sh && bash install.sh
```

脚本会提示输入两个域名，其余参数（UUID、密钥、shortId、路径）全部自动生成。完成后节点配置保存到 `~/client-config.txt`。

**前置条件**：运行脚本前需在 Cloudflare 完成以下设置：
1. Reality 域名 DNS → 仅 DNS（灰色云朵）
2. CDN 域名 DNS → 代理开启（橙色云朵）
3. SSL/TLS 加密 → 完全（严格）
4. 网络 → gRPC → 已开启

## 手动部署

按下面的顺序阅读和执行：

1. [环境配置.md](./1.环境配置.md)，完成 Cloudflare 设置、Xray 安装、证书申请和 Nginx 安装。
2. [文件配置.md](./2.文件配置.md)，完成 Nginx 与 Xray 配置，并执行测试与重启命令。
3. [客户端模板.txt](./客户端模板.txt)，复制到V2rayN，替换YOUR开头的占位符后可以正常使用。

## 模式

[客户端模板.txt](./客户端模板.txt) 当前包含以下 5 种模式：

1. Reality Vision 直连
2. XHTTP + Reality 上下行不分离
3. 上行 XHTTP + TLS + CDN，下行 XHTTP + Reality
4. XHTTP + TLS 双向 CDN
5. 上行 XHTTP + Reality，下行 XHTTP + TLS + CDN

## 去程流程图（上行 / 请求方向）

```mermaid
graph TD
	START2("外部请求到达 VPS:443")

	START2 -->|"代理软件请求"| PROXY["客户端代理请求"]
	START2 -->|"防火墙主动探测"| PROBEX["探测请求"]

	PROXY -->|"Vision 直连 / XHTTP+Reality<br/>直连 VPS:443"| GFWD["穿过防火墙"]
	GFWD --> XR443["Xray 443<br/>VLESS + Reality<br/>serverNames: REALITY_DOMAIN"]

	PROXY -->|"XHTTP+TLS+CDN<br/>连接 CDN 域名:443"| GFWC["穿过防火墙"]
	GFWC --> CF["Cloudflare CDN"]
	CF -->|"回源 VPS:443"| XR443C["Xray 443"]
	XR443C -->|"非 Reality<br/>target:8003 转发"| NG8003["Nginx 8003<br/>server_name: CDN_DOMAIN"]

	XR443 --> VISION{"UUID1 + Vision?"}
	VISION -->|"是<br/>flow: xtls-rprx-vision"| HANDLE443["Xray 443 处理 UUID1 代理请求<br/>Reality+Vision 直连到达"]
	HANDLE443 --> OUT2("Xray outbound direct<br/>到达目标网站")

	VISION -->|"否<br/>fallback dest:8001"| XR8001A["Xray 8001<br/>127.0.0.1:8001<br/>VLESS + XHTTP<br/>UUID2 path: XHTTP_PATH<br/>XHTTP+Reality 到达"]
	XR8001A --> OUT2

	NG8003 --> PATHCHK{"location 匹配<br/>XHTTP_PATH?"}
	PATHCHK -->|"是"| GRPC["grpc_pass 127.0.0.1:8001"]
	GRPC --> XR8001B["Xray 8001<br/>VLESS + XHTTP<br/>XHTTP+TLS+CDN 到达"]
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
```

## 注意事项

- 文档中的占位符需要全部替换后再使用。

## 参考资料

- Xray-core Discussion: https://github.com/XTLS/Xray-core/discussions/4118
- Xray小白搭建教程： https://xtls.github.io/document/level-0/ch06-certificates.html 和 https://xtls.github.io/document/level-0/ch07-xray-server.html
- 参考文章: https://jollyroger.top/sites/361.html
