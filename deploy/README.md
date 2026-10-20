# 灵驿上线部署包

在一台海外 Linux 服务器（Ubuntu 22.04/24.04，1 核 2G 即可）上运行灵驿，带 HTTPS。

## 准备
1. 买服务器（香港/日本/新加坡），记下 IP 和 root 密码。
2. 买域名，在域名后台加一条 A 记录：`api` → 服务器 IP。
3. 服务器安全组/防火墙放行 80 和 443 端口。

## 上传
把本文件夹整个传到服务器 `/opt/lingyi`（可用 WinSCP 或 `scp -r`）。
想保留电脑上的设置和数据：先在电脑上运行 stop.bat，再把
`C:\Users\30735\Documents\ChatGPT\dls\new-api\one-api.db` 一起放进这个文件夹。

## 安装
```bash
cd /opt/lingyi
bash install.sh api.你的域名.com
```

## 购买额度页面
`buy/` 文件夹是给朋友看的价目表和收款码页面，上线后地址是 `https://api.你的域名.com/buy/`。
- 把微信、支付宝收款码图片命名为 `wechat.png`、`alipay.png` 放进 `buy/` 文件夹。
- 后台 系统设置 → 计费 → 额度设置 →「充值链接」填 `https://api.你的域名.com/buy/`，钱包页就会出现购买入口。

## 常用命令
- 看日志：`docker compose logs -f lingyi`
- 重启：`docker compose restart`
- 备份：复制 `data/one-api.db`

## 上线后马上做
- 改 admin 强密码；关闭开放注册（或开邮箱验证）
- 系统设置里「服务器地址」改成 `https://api.你的域名.com`
- 客户端 Base URL 用 `https://api.你的域名.com/v1`

程序版本 cyber-798d865，基于 new-api（AGPL-3.0），许可证见 LICENSE / NOTICE。
sha256(new-api-linux) = 6e9523853bac452b2f520165b68d763d5946bdc7a18936f9fbf7131f1cce1c39
