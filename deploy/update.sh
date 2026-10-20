#!/usr/bin/env bash
# 更新到 GitHub 上的最新版本：cd ~/lingyi && git pull && sudo bash deploy/update.sh
set -e
cd "$(dirname "$0")"
rm -f new-api
gunzip -k new-api-linux.gz && mv new-api-linux new-api
docker compose up -d --build
echo ">> 已更新，几十秒后刷新网页"
