#!/usr/bin/env bash
# 在服务器上添加 DeepSeek 渠道：sudo bash add-deepseek.sh
# 管理员密码和 Key 只在这台服务器的终端里输入，不会显示、不会保存到文件。
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
NAME=""; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
read -rsp "Admin password (hidden): " PASS; echo
read -rsp "New DeepSeek API key (hidden): " KEY; echo
export NAME PASS KEY SITE
python3 - <<'PY'
import json, os, sys, urllib.request, http.cookiejar
site = os.environ["SITE"]
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
token = None
def call(method, path, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(site + path, method=method,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    with opener.open(req) as r:
        return json.load(r)
login = call("POST", "/api/user/login", {"username": os.environ["NAME"], "password": os.environ["PASS"]})
if not login.get("success"):
    sys.exit("LOGIN FAILED: " + str(login.get("message")))
token = login["data"]["access_token"]
import atexit
def _logout():
    # Each script login is a session (the site allows 50); close leftovers from earlier runs and this one.
    try:
        for sess in call("GET", "/api/user/sessions").get("data") or []:
            if not sess.get("current") and (sess.get("user_agent") or "").startswith("Python-urllib"):
                call("DELETE", f"/api/user/sessions/{sess['sid']}")
    except Exception:
        pass
    try:
        call("POST", "/api/user/auth/logout")
    except Exception:
        pass
atexit.register(_logout)
res = call("POST", "/api/channel/", {"mode": "single", "channel": {
    "type": 43, "name": "DeepSeek", "key": os.environ["KEY"].strip(),
    "models": "deepseek-flash,deepseek-v4-pro", "group": "default"}})
if not res.get("success"):
    sys.exit("ADD CHANNEL FAILED: " + str(res.get("message")))
chans = call("GET", "/api/channel/?p=1&page_size=50")
items = chans["data"]["items"]
cid = max(c["id"] for c in items if c.get("name") == "DeepSeek")
test = call("GET", f"/api/channel/test/{cid}?model=deepseek-flash")
print("CHANNEL ADDED. " + ("TEST OK" if test.get("success") else "TEST FAILED: " + str(test.get("message"))))
PY
