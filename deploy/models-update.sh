#!/usr/bin/env bash
# 一条命令整理全部模型：给新模型定价 → 把能卖的 OpenRouter 模型放回渠道 → 补厂商/图标/简介。
# 以后加了模型、或者模型管理里又出现"未设置价格""缺元数据"，就跑这一条：
#   cd ~/lingyi && git pull && sudo bash deploy/models-update.sh
# 只会新增，不改已有价格，不删渠道里的模型，不动密钥。
cd "$(dirname "$0")"
LINGYI_ADMIN=""; while [ -z "$LINGYI_ADMIN" ]; do read -rp "Admin username: " LINGYI_ADMIN; done
read -rsp "Admin password (hidden): " LINGYI_PASS; echo
export LINGYI_ADMIN LINGYI_PASS CONFIRM=y
echo; echo "== 1/3 Pricing models that have no price =="
bash price-openrouter-all.sh || true
echo; echo "== 2/3 Checking the OpenRouter channel (put back missing models, drop \"~\" aliases) =="
bash restore-openrouter-models.sh || true
echo; echo "== 3/3 Filling vendor, icon and description =="
bash fill-model-info.sh || true
unset LINGYI_PASS
echo; echo "ALL DONE."
