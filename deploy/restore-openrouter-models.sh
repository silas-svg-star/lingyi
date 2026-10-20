#!/usr/bin/env bash
# 把已经定好价、且 OpenRouter 真实提供的模型重新放回 OpenRouter 渠道。
#   cd ~/lingyi && git pull && sudo bash deploy/restore-openrouter-models.sh
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

if os.environ.get("OR_MODELS_FILE"):
    catalog = json.load(open(os.environ["OR_MODELS_FILE"]))["data"]
else:
    with urllib.request.urlopen("https://openrouter.ai/api/v1/models", timeout=60) as r:
        catalog = json.load(r)["data"]
text_ids = {m["id"] for m in catalog
            if m.get("architecture", {}).get("output_modalities", ["text"]) == ["text"]}

items = call("GET", "/api/channel/?p=1&page_size=100")["data"]["items"]
chans = [c for c in items if c.get("name") == "OpenRouter"]
if not chans:
    sys.exit("NO OPENROUTER CHANNEL")
chan = max(chans, key=lambda c: c["id"])
existing = [x.strip() for x in (chan.get("models") or "").split(",") if x.strip()]

opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
priced = set(json.loads(opts.get("ModelRatio") or "{}")) | set(json.loads(opts.get("ModelPrice") or "{}"))
back = sorted(x for x in priced if x in text_ids and x not in existing)

print(f"\nOpenRouter channel #{chan['id']} has {len(existing)} models now.")
print(f"Priced OpenRouter models to put back: {len(back)}")
for x in back:
    print("  " + x)
if not back:
    sys.exit("NOTHING TO RESTORE")
print(f"\nPut these {len(back)} models back? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")
res = call("PUT", "/api/channel/", {"id": chan["id"], "type": chan["type"], "models": ",".join(existing + back)})
if not res.get("success"):
    sys.exit("UPDATE CHANNEL FAILED: " + str(res.get("message")))
test = call("GET", f"/api/channel/test/{chan['id']}?model={back[0]}")
print(f"DONE. OpenRouter channel now has {len(existing) + len(back)} models. " +
      ("TEST OK" if test.get("success") else "TEST FAILED: " + str(test.get("message"))))
PY
