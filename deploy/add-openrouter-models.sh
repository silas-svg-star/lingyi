#!/usr/bin/env bash
# 往已有的 OpenRouter 渠道里补加模型（按名字搜索），并按官方价格设置倍率：
#   cd ~/lingyi && git pull && sudo bash deploy/add-openrouter-models.sh severance
# 可以一次写多个关键词：... add-openrouter-models.sh severance grok-5
set -e
if [ $# -eq 0 ]; then echo "Usage: sudo bash deploy/add-openrouter-models.sh <keyword> [keyword...]"; exit 1; fi
SITE="${SITE:-http://127.0.0.1:3000}"
NAME=""; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
read -rsp "Admin password (hidden): " PASS; echo
TERMS="$*"
export NAME PASS SITE TERMS
python3 - <<'PY'
import json, os, sys, urllib.request, http.cookiejar
site = os.environ["SITE"]
terms = [t.lower() for t in os.environ["TERMS"].split()]
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

def price(m, field):
    try:
        return float(m.get("pricing", {}).get(field) or 0) * 1e6  # USD per 1M tokens
    except ValueError:
        return 0.0

matches = [m for m in catalog
           if any(t in m["id"].lower() or t in m.get("name", "").lower() for t in terms)]
picked = [m for m in matches
          if m.get("architecture", {}).get("output_modalities", ["text"]) == ["text"]
          and price(m, "prompt") > 0 and price(m, "completion") > 0]
for m in matches:
    if m not in picked:
        print(f"  skipped {m['id']} (free, router, or not a text model)")
if not picked:
    sys.exit("NO PAID TEXT MODELS MATCH: " + " ".join(terms))

items = call("GET", "/api/channel/?p=1&page_size=100")["data"]["items"]
chans = [c for c in items if c.get("name") == "OpenRouter"]
if not chans:
    sys.exit("NO OPENROUTER CHANNEL, run deploy/add-openrouter.sh first")
chan = max(chans, key=lambda c: c["id"])
existing = [x for x in (chan.get("models") or "").split(",") if x]

opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
model_ratio = json.loads(opts.get("ModelRatio") or "{}")
completion_ratio = json.loads(opts.get("CompletionRatio") or "{}")
cache_ratio = json.loads(opts.get("CacheRatio") or "{}")

print("\nModels to add (USD per 1M tokens, input / output):")
for m in picked:
    mid = m["id"]
    pin, pout, pcache = price(m, "prompt"), price(m, "completion"), price(m, "input_cache_read")
    note = ""
    if mid in model_ratio:
        note = "  (price already set, kept)"
    else:
        model_ratio[mid] = round(pin / 2, 6)
        completion_ratio[mid] = round(pout / pin, 6)
        if pcache > 0:
            cache_ratio[mid] = round(pcache / pin, 6)
    print(f"  {mid}\n      {pin:.3f} / {pout:.3f}{note}")
print("\nAdd these models? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

for key, value in (("ModelRatio", model_ratio), ("CompletionRatio", completion_ratio), ("CacheRatio", cache_ratio)):
    res = call("PUT", "/api/option/", {"key": key, "value": json.dumps(value)})
    if not res.get("success"):
        sys.exit(f"SET {key} FAILED: " + str(res.get("message")))

new_ids = [m["id"] for m in picked if m["id"] not in existing]
res = call("PUT", "/api/channel/", {"id": chan["id"], "type": chan["type"],
                                    "models": ",".join(existing + new_ids)})
if not res.get("success"):
    sys.exit("UPDATE CHANNEL FAILED: " + str(res.get("message")))
test = call("GET", f"/api/channel/test/{chan['id']}?model={picked[0]['id']}")
print(f"ADDED {len(new_ids)} MODELS. " + ("TEST OK" if test.get("success") else "TEST FAILED: " + str(test.get("message"))))
PY
