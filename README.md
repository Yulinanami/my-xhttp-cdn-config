# XHTTP + CDN 上下行分离配置指南

> **推荐文章1**：XHTTP 原理、上下行分离、抗审查：https://habr.com/en/articles/990208/
> 
> **推荐文章2**：DNS 泄露：https://github.com/meooxx/blog/issues/31
>
> **注意**：教程用 VLESS Encryption，客户端（V2rayN、Mihomo）也要能用 vlessenc / xhttp。
>
> **注意**：V2rayN v7.19.5+ 的 TUN 模式可能不稳，可以打开旧版 TUN 保护。
> PR：https://github.com/2dust/v2rayN/pull/9005

这个仓库记录 443 端口上用 Xray-core 搭 XHTTP + CDN 的步骤，包括环境准备、服务端配置和客户端模板。
支持小火箭、Xray 和 Mihomo，支持 IPv4 和 IPv6。

## 模式

可以搭建这 5 种模式：

1. Reality Vision 直连
2. XHTTP + Reality 上下行不分离
3. 上行 XHTTP + TLS + CDN，下行 XHTTP + Reality
4. XHTTP + TLS + H2
5. 上行 XHTTP + Reality，下行 XHTTP + TLS + CDN

## 安全性

- VLESS Encryption：防止 CDN 中间人看到流量内容
- 只有过 CDN 的 XHTTP 入站开 vlessenc，Vision 直连不用
- 回落可以反向代理网站，也可以用上传的 `dist` 页面
- `xpadding`：绕过 CDN 检测
- `ECH`：加密 TLS 握手里的 SNI

## 流程图（去程 + 回程）

[流程图.md](./docs/5.流程图.md)

## 手动部署（以Ubuntu24.04为例）

按这个顺序做：

1. [环境配置.md](./docs/1.环境配置.md)：Cloudflare、Xray、证书、Nginx。
2. [文件配置.md](./docs/2.文件配置.md)：Nginx 和 Xray 配置，然后测试、重启。
3. [xpadding配置.md](./docs/3.xpadding配置.md)：给 Xray / v2rayN / Mihomo 加 xpadding。
4. [ECH配置.md](./docs/4.ECH配置.md)：给 CDN-TLS 节点加 ECH。
5. [拓展-上下行不同CDN.md](./docs/6.拓展-上下行不同CDN.md)：上行 CDN-A / 下行 CDN-B。
6. [拓展-上下行IPv4IPv6.md](./docs/7.拓展-上下行IPv4IPv6.md)：上行 IPv4 / 下行 IPv6。
7. [拓展-XHTTP-H3.md](./docs/8.拓展-XHTTP-H3.md)：XHTTP H3、H2/H3 上下行分离。
8. [拓展-Hysteria2.md](./docs/9.拓展-Hysteria2.md)：Hysteria2。
9. [卸载.md](./docs/卸载.md)：卸 Xray、Nginx、ACME、Hysteria2。
10. [客户端模板.txt](./客户端模板.txt)：复制到 V2rayN，替换 `YOUR_*`。
11. [客户端模板-mihomo.yaml](./客户端模板-mihomo.yaml)：替换 `YOUR_*` 后导入 Mihomo。

---

## 脚本部署

> **提示**：脚本可以再跑一遍，用来改域名、回落网站。
> 跑脚本前先在 Cloudflare 做好这些：
>
> 1. Reality 域名 DNS → 仅 DNS（灰色云朵）
> 2. CDN 域名 DNS → 代理开启（橙色云朵）
> 3. SSL/TLS 加密 → 完全（严格）
> 4. 网络 → gRPC → 已开启
> 5. 缓存规则（建议） → XHTTP 路径绕过缓存，步骤见 [环境配置.md](./docs/1.环境配置.md)。

虽然脚本会生成默认 `index.html`，但是最好换成更丰富完整的页面。
将 `dist` 文件夹上传到 `/var/www/`，每个入口域名使用独立的 `/var/www/dist/<域名>/index.html`；可用 [SingleFile](https://chromewebstore.google.com/detail/singlefile/mpiodijhokgodhhofbcjdecpffjipkle?hl=zh-CN&utm_source=ext_sidebar) 抓取网页。

命令按系统分：

1. [systemd 发行版（Debian / Ubuntu 等大部分发行版）](./docs/脚本部署-systemd.md)
2. [Alpine Linux](./docs/脚本部署-Alpine.md)

---

### 输出文件

脚本会生成：

- `~/client-config.txt`：V2RayN / Shadowrocket 节点
- `~/client-config-mihomo-full.yaml`：Mihomo 完整分流配置
- `~/client-config-mihomo-nodes.yaml`：Mihomo 纯节点配置
- `~/subscription-links.txt`：订阅链接汇总
- `~/subscription-*.png`：订阅二维码

已经有 Mihomo 配置的，用 `mihomo-nodes.yaml`。

---

## 个人开发与发布

改完模块或模板后，在仓库根目录跑这些命令拼安装脚本：

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

见 [参考资料](./docs/参考资料.md)。
