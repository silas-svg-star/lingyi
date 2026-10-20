#!/usr/bin/env bash
# 给渠道里所有还没定价的 OpenRouter 模型，按 OpenRouter 官方价格一次性定价：
#   cd ~/lingyi && git pull && sudo bash deploy/price-openrouter-all.sh
# 已经设过价格的模型不改；免费模型和画图等非文字模型会跳过（列出来告诉你）。
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
by_id = {m["id"]: m for m in catalog}

def price(m, field):
    try:
        return float(m.get("pricing", {}).get(field) or 0) * 1e6  # USD per 1M tokens
    except ValueError:
        return 0.0

# Every model name configured on any channel.
names, page = set(), 1
while True:
    data = call("GET", f"/api/channel/?p={page}&page_size=100")["data"]
    items = data.get("items") or []
    for c in items:
        names.update(x.strip() for x in (c.get("models") or "").split(",") if x.strip())
    if len(items) < 100:
        break
    page += 1

opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
model_ratio = json.loads(opts.get("ModelRatio") or "{}")
model_price = json.loads(opts.get("ModelPrice") or "{}")
completion_ratio = json.loads(opts.get("CompletionRatio") or "{}")
cache_ratio = json.loads(opts.get("CacheRatio") or "{}")

added, free, non_text, unknown = [], [], [], []
for name in sorted(names):
    if name in model_ratio or name in model_price:
        continue
    m = by_id.get(name)
    if m is None:
        if "/" in name:  # names without a provider prefix are other channels' models
            unknown.append(name)
        continue
    if m.get("architecture", {}).get("output_modalities", ["text"]) != ["text"]:
        non_text.append(name)
        continue
    pin, pout, pcache = price(m, "prompt"), price(m, "completion"), price(m, "input_cache_read")
    if pin <= 0 or pout <= 0:
        free.append(name)
        continue
    model_ratio[name] = round(pin / 2, 6)
    completion_ratio[name] = round(pout / pin, 6)
    if pcache > 0:
        cache_ratio[name] = round(pcache / pin, 6)
    added.append((name, pin, pout))

for label, rows in (("Free models (skipped)", free), ("Image/audio models (skipped)", non_text),
                    ("Not on OpenRouter (skipped)", unknown)):
    if rows:
        print(f"\n{label}: {len(rows)}")
        for r in rows:
            print("  " + r)
print(f"\nNew prices: {len(added)} models (USD per 1M tokens, input / output)")
for name, pin, pout in added:
    print(f"  {name}\n      {pin:.3f} / {pout:.3f}")
if not added:
    sys.exit("NOTHING TO PRICE")
print(f"\nSet prices for these {len(added)} models? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")
for key, value in (("ModelRatio", model_ratio), ("CompletionRatio", completion_ratio), ("CacheRatio", cache_ratio)):
    res = call("PUT", "/api/option/", {"key": key, "value": json.dumps(value)})
    if not res.get("success"):
        sys.exit(f"SET {key} FAILED: " + str(res.get("message")))
print(f"DONE. {len(added)} models priced.")
PY
