#!/usr/bin/env bash
# One-time site setup: cd ~/lingyi && git pull && sudo bash deploy/setup-site.sh
# Sets name, logo, CNY display, notice, invite rewards and creates redemption codes.
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

def option(key, value, label):
    r = call("PUT", "/api/option/", {"key": key, "value": value})
    print(("OK    " if r.get("success") else "FAIL  ") + label + ("" if r.get("success") else ": " + str(r.get("message"))))
    return r.get("success")

option("SystemName", "灵驿", "site name")
option("Logo", open("logo-url.txt").read().strip(), "logo")
option("USDExchangeRate", "10", "CNY rate 10")
option("general_setting.quota_display_type", "CNY", "show amounts in CNY")
option("Notice", "灵驿已上线。充值请看「购买额度」页面，兑换码在「钱包」里使用。邀请好友注册：你得 ¥5，好友得 ¥2。", "notice banner")

ok = option("QuotaForInviter", "250000", "invite reward 5 CNY")
ok = option("QuotaForInvitee", "100000", "new user via invite 2 CNY") and ok
if not ok:
    print("\nInvite rewards and redemption codes are locked until you confirm the payment")
    print("compliance terms yourself in the admin panel. Do that, then run this script again.")
    sys.exit(0)

codes_file = "/root/lingyi-codes.txt"
if os.path.exists(codes_file):
    print("SKIP  redemption codes already created, see " + codes_file)
    sys.exit(0)
lines = []
for yuan, quota in [(10, 500000), (50, 2600000), (100, 5500000), (300, 17500000), (500, 30000000)]:
    r = call("POST", "/api/redemption/", {"name": f"{yuan}元充值码", "count": 5, "quota": quota})
    if not r.get("success"):
        print(f"FAIL  {yuan} CNY codes: {r.get('message')}")
        continue
    lines.append(f"== {yuan} CNY ==")
    lines += r["data"]
    print(f"OK    5 codes of {yuan} CNY")
with open(codes_file, "w") as f:
    f.write("\n".join(lines) + "\n")
os.chmod(codes_file, 0o600)
print("\nCodes saved to " + codes_file + "  (view: sudo cat " + codes_file + ")")
PY
