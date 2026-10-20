#!/usr/bin/env bash
# Turn on disclosed conversation logging: cd ~/lingyi && git pull && sudo bash deploy/enable-conversation-log.sh
# Order matters: the user agreement and privacy policy that disclose the 7-day log go live first,
# then the notice banner, then the switch. The login/register pages show a notice while it is on.
set -e
cd "$(dirname "$0")"
SITE="${SITE:-http://127.0.0.1:3000}"
NAME=""; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
read -rsp "Admin password (hidden): " PASS; echo
export NAME PASS SITE
python3 - <<'PY'
import json, os, sys, urllib.request, urllib.error
site = os.environ["SITE"]
token = None
def call(method, path, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(site + path, method=method,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return json.load(e)
login = call("POST", "/api/user/login", {"username": os.environ["NAME"], "password": os.environ["PASS"]})
if not login.get("success"):
    sys.exit("LOGIN FAILED: " + str(login.get("message")))
token = login["data"]["access_token"]

def option(key, value, label):
    r = call("PUT", "/api/option/", {"key": key, "value": value})
    print(("OK    " if r.get("success") else "FAIL  ") + label + ("" if r.get("success") else ": " + str(r.get("message"))))
    if not r.get("success"):
        sys.exit("Stopped before turning logging on.")

option("legal.user_agreement", open("legal/user-agreement.md").read(), "user agreement (mentions 7-day log)")
option("legal.privacy_policy", open("legal/privacy-policy.md").read(), "privacy policy (mentions 7-day log)")
option("Notice", "灵驿已上线。充值请看「购买额度」页面，兑换码在「钱包」里使用。邀请好友注册：你得 ¥5，好友得 ¥2。\n\n【隐私提示】为排查问题和防止滥用，本站从现在起会保存对话内容 7 天后自动删除，仅管理员可见，详见《隐私政策》。", "notice banner (privacy notice)")
option("ConversationLogEnabled", "true", "conversation logging ON (7 days)")
status = call("GET", "/api/status")["data"]
print("Login page notice shown:", status.get("conversation_log_enabled"), "| days:", status.get("conversation_log_days"))
PY
