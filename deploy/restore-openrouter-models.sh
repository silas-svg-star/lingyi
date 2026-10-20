#!/usr/bin/env bash
# 把已经定好价、且 OpenRouter 真实提供的模型重新放回 OpenRouter 渠道。
#   cd ~/lingyi && git pull && sudo bash deploy/restore-openrouter-models.sh
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
NAME="${LINGYI_ADMIN:-}"; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
PASS="${LINGYI_PASS:-}"; if [ -z "$PASS" ]; then read -rsp "Admin password (hidden): " PASS; echo; fi
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
text_ids = {m["id"] for m in catalog
            if m.get("architecture", {}).get("output_modalities", ["text"]) == ["text"]}

items = call("GET", "/api/channel/?p=1&page_size=100")["data"]["items"]
chans = [c for c in items if c.get("name") == "OpenRouter"]
if not chans:
    sys.exit("NO OPENROUTER CHANNEL")
chan = max(chans, key=lambda c: c["id"])
chan = call("GET", f"/api/channel/{chan['id']}")["data"]
existing = [x.strip() for x in (chan.get("models") or "").split(",") if x.strip()]
try:
    mapping = json.loads(chan.get("model_mapping") or "{}") or {}
except ValueError:
    mapping = {}
mapped_to = set(mapping.values())

opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
priced = set(json.loads(opts.get("ModelRatio") or "{}")) | set(json.loads(opts.get("ModelPrice") or "{}"))
# Leave out duplicates of a real model: "~vendor/model-latest" aliases and
# variants such as "model:batch", ":free", ":thinking", ":extended".
def duplicate(x):
    return x.startswith("~") or ":" in x
aliases = [x for x in existing if duplicate(x)]
existing = [x for x in existing if not duplicate(x)]
back = sorted(x for x in priced if x in text_ids and x not in existing and x not in mapped_to
              and not duplicate(x))

print(f"\nOpenRouter channel #{chan['id']} has {len(existing) + len(aliases)} models now.")
if aliases:
    print(f"Duplicate models to take off (\"~\" aliases, :batch and similar): {len(aliases)}")
    for x in aliases:
        print("  " + x)
print(f"Priced OpenRouter models to put back: {len(back)}")
for x in back:
    print("  " + x)
if not back and not aliases:
    sys.exit("NOTHING TO RESTORE")
print(f"\nApply these changes? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")
for x in aliases:
    mapping.pop(x, None)
res = call("PUT", "/api/channel/", {"id": chan["id"], "type": chan["type"], "models": ",".join(existing + back),
                                    "model_mapping": json.dumps(mapping)})
if not res.get("success"):
    sys.exit("UPDATE CHANNEL FAILED: " + str(res.get("message")))
# Drop the info cards of those duplicates too, so they leave the model list.
ids, page = [], 1
while True:
    items = call("GET", f"/api/models/?p={page}&page_size=100")["data"].get("items") or []
    ids += [m["id"] for m in items if m.get("id") and m["model_name"] in aliases]
    if len(items) < 100:
        break
    page += 1
if ids:
    call("POST", "/api/models/delete", {"model_ids": ids, "remove_from_channels": False, "remove_pricing": False})
test = call("GET", f"/api/channel/test/{chan['id']}?model={(back or existing)[0]}")
print(f"DONE. OpenRouter channel now has {len(existing) + len(back)} models. " +
      ("TEST OK" if test.get("success") else "TEST FAILED: " + str(test.get("message"))))
PY
