#!/usr/bin/env bash
# 灵驿一键部署：bash install.sh [你的域名]
# 不带域名时先用 http://服务器IP 访问；买了域名后再运行一次 bash install.sh api.你的域名.com 即可开启 https
set -e
DOMAIN="$1"
cd "$(dirname "$0")"

# 小内存服务器（1GB）加 2GB swap，避免内存不够
if [ "$(swapon --show | wc -l)" -eq 0 ] && [ ! -f /swapfile ]; then
  echo ">> 添加 2GB swap"
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

if ! command -v docker >/dev/null 2>&1; then
  echo ">> 安装 Docker"
  curl -fsSL https://get.docker.com | sh
fi

if [ ! -f new-api ]; then
  echo ">> 解压程序"
  gunzip -k new-api-linux.gz && mv new-api-linux new-api
fi

if [ ! -f .env ]; then
  echo "SESSION_SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '/+=')" > .env
fi

SITE="${DOMAIN:-:80}"
cat > Caddyfile <<CADDY
$SITE {
    handle_path /buy* {
        root * /srv/buy
        file_server
    }
    reverse_proxy 127.0.0.1:3000 {
        flush_interval -1
    }
}
CADDY

mkdir -p data logs
[ -f one-api.db ] && [ ! -f data/one-api.db ] && mv one-api.db data/ && echo ">> 已导入电脑上的数据库"

docker compose up -d --build
if [ -n "$DOMAIN" ]; then
  echo ">> 完成。几十秒后打开 https://$DOMAIN"
else
  echo ">> 完成。几十秒后打开 http://$(curl -s https://checkip.amazonaws.com)"
fi
