#!/usr/bin/env bash
# 清理 OpenRouter 渠道里 OpenRouter 实际不提供的模型名（比如误点"填入所有模型"带进来的
# MiniMax-M2.7、speech-02-hd、veo-2.0 这类不带前缀的名字）。价格设置不动。
#   cd ~/lingyi && git pull && sudo bash deploy/trim-openrouter-models.sh
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
NAME=""; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
read -rsp "Admin password (hidden): " PASS; echo
export NAME PASS SITE
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

if os.environ.get("OR_MODELS_FILE"):
    catalog = json.load(open(os.environ["OR_MODELS_FILE"]))["data"]
else:
    with urllib.request.urlopen("https://openrouter.ai/api/v1/models", timeout=60) as r:
        catalog = json.load(r)["data"]
offered = {m["id"] for m in catalog}
if len(offered) < 50:
    sys.exit("OPENROUTER CATALOG LOOKS WRONG, nothing changed")

items = call("GET", "/api/channel/?p=1&page_size=100")["data"]["items"]
chans = [c for c in items if c.get("name") == "OpenRouter"]
if not chans:
    sys.exit("NO OPENROUTER CHANNEL")
chan = max(chans, key=lambda c: c["id"])
chan = call("GET", f"/api/channel/{chan['id']}")["data"]
existing = [x.strip() for x in (chan.get("models") or "").split(",") if x.strip()]
try:
    mapped = set(json.loads(chan.get("model_mapping") or "{}"))
except ValueError:
    mapped = set()

keep = [x for x in existing if x in offered or x in mapped]
drop = [x for x in existing if x not in keep]
print(f"\nOpenRouter channel #{chan['id']}: {len(existing)} models")
print(f"  keep:   {len(keep)} (OpenRouter really serves these)")
print(f"  remove: {len(drop)} (OpenRouter has no model with this exact name)")
for x in drop:
    print("    " + x)
if not drop:
    sys.exit("NOTHING TO REMOVE")
if len(keep) < len(drop):
    sys.exit("WOULD REMOVE MOST OF THE CHANNEL, stopping, nothing changed")
print(f"\nRemove these {len(drop)} names from the OpenRouter channel? Prices are not touched. (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

res = call("PUT", "/api/channel/", {"id": chan["id"], "type": chan["type"], "models": ",".join(keep)})
if not res.get("success"):
    sys.exit("UPDATE CHANNEL FAILED: " + str(res.get("message")))
print(f"DONE. OpenRouter channel now has {len(keep)} models. The model list refreshes within a minute.")
PY
