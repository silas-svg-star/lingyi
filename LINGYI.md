# 灵驿 LingYi

基于 [new-api](https://github.com/QuantumNous/new-api)（AGPL-3.0）修改的 AI API 中转站：暗色 Cyber 主题、精简侧边栏、可选且公开告知的对话记录（默认关闭）。

- `deploy/`：服务器一键部署（Docker + Caddy）。在服务器上运行：
  ```
  git clone --depth 1 https://github.com/silas-svg-star/lingyi && cd lingyi/deploy && sudo bash install.sh
  ```
  有域名后：`sudo bash install.sh api.你的域名.com` 开启 HTTPS。
- `release/lingyi-windows.zip`：Windows 版程序（解压得到 new-api-cyber.exe）。
- 源代码即本仓库，许可证见 `LICENSE`、`NOTICE`。
