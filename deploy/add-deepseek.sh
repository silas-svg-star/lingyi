#!/usr/bin/env bash
# 在服务器上添加 DeepSeek 渠道：sudo bash add-deepseek.sh
# 管理员密码和 Key 只在这台服务器的终端里输入，不会显示、不会保存到文件。
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
read -rp "管理员用户名（默认 root）: " NAME
read -rsp "管理员密码（输入时不显示）: " PASS; echo
read -rsp "DeepSeek API Key（输入时不显示）: " KEY; echo
export NAME="${NAME:-root}" PASS KEY SITE
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
    sys.exit("登录失败：" + str(login.get("message")))
token = login["data"]["access_token"]
res = call("POST", "/api/channel/", {"mode": "single", "channel": {
    "type": 43, "name": "DeepSeek", "key": os.environ["KEY"].strip(),
    "models": "deepseek-flash,deepseek-v4-pro", "group": "default"}})
if not res.get("success"):
    sys.exit("添加渠道失败：" + str(res.get("message")))
chans = call("GET", "/api/channel/?p=1&page_size=50")
items = chans["data"]["items"]
cid = max(c["id"] for c in items if c.get("name") == "DeepSeek")
test = call("GET", f"/api/channel/test/{cid}?model=deepseek-flash")
print("渠道已添加。" + ("测试成功，DeepSeek 可以用了。" if test.get("success") else "但测试没通过：" + str(test.get("message"))))
PY
