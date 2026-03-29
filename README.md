# XHTTP + CDN 配置指南

这个仓库用于整理一套基于 Xray-core 的 XHTTP + CDN 搭建方案，覆盖环境准备、服务端配置和客户端模板三部分内容。

适合的使用场景：
- 需要使用 Reality 直连。
- 需要通过 CDN 承载部分或全部 XHTTP 流量。
- 希望按文档顺序快速完成一套可复用的部署。

## 仓库结构

- [1.环境配置.md](./1.环境配置.md)：环境准备、Cloudflare 前置设置、Acme.sh 证书申请、Nginx 编译安装。
- [2.文件配置.md](./2.文件配置.md)：Nginx 反向代理配置、Xray 服务端配置。
- [客户端模板.txt](./客户端模板.txt)：客户端连接模板，包含 5 种常见连接模式。

## 快速开始

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

## 参数说明

- `UUID_1`：用于 443 端口的 Reality 直连入站。
- `UUID_2`：用于 XHTTP 入站和大部分客户端模板。
- `YOUR_REALITY_DOMAIN`：Reality 直连使用的域名。
- `YOUR_CDN_DOMAIN`：走 CDN 的域名。
- `YOUR_PATH`：伪装路径，需要与 Cloudflare 规则、Nginx `location`、Xray `xhttpSettings.path` 保持一致。
- `YOUR_PUBILC_KEY`：客户端使用的 Reality 公钥。
- `YOUR_SHORT_ID`：Reality 短 ID。

## 注意事项

- 文档中的占位符需要全部替换后再使用。

## 参考资料

- Xray-core Discussion: https://github.com/XTLS/Xray-core/discussions/4118
- 参考文章: https://jollyroger.top/sites/361.html
