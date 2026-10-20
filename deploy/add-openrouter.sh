#!/usr/bin/env bash
# 在服务器上接入 OpenRouter（GPT、Claude、Gemini、Grok、通义、Kimi、GLM 等）：
#   cd ~/lingyi && git pull && sudo bash deploy/add-openrouter.sh
# 管理员密码和 OpenRouter Key 只在这台服务器的终端里输入，不会显示、不会保存到文件。
# 每家取最新的几款文字模型，按 OpenRouter 官方价格设置倍率（已经设过价格的模型不改）。
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
PER_PROVIDER="${PER_PROVIDER:-8}"
NAME=""; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
read -rsp "Admin password (hidden): " PASS; echo
read -rsp "OpenRouter API key (hidden): " KEY; echo
export NAME PASS KEY SITE PER_PROVIDER
python3 - <<'PY'
import json, os, sys, urllib.request, http.cookiejar
site = os.environ["SITE"]
per_provider = int(os.environ["PER_PROVIDER"])
providers = ["openai", "anthropic", "google", "x-ai", "qwen", "moonshotai",
             "z-ai", "meta-llama", "mistralai", "minimax"]
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

# Public model list with USD prices per token.
if os.environ.get("OR_MODELS_FILE"):
    catalog = json.load(open(os.environ["OR_MODELS_FILE"]))["data"]
else:
    req = urllib.request.Request("https://openrouter.ai/api/v1/models",
        headers={"Authorization": "Bearer " + os.environ["KEY"].strip()})
    with urllib.request.urlopen(req, timeout=60) as r:
        catalog = json.load(r)["data"]

def price(m, field):
    try:
        return float(m.get("pricing", {}).get(field) or 0) * 1e6  # USD per 1M tokens
    except ValueError:
        return 0.0

picked = []
for p in providers:
    rows = [m for m in catalog
            if m["id"].startswith(p + "/") and ":" not in m["id"]
            and m.get("architecture", {}).get("output_modalities", ["text"]) == ["text"]
            and price(m, "prompt") > 0 and price(m, "completion") > 0]
    rows.sort(key=lambda m: m.get("created", 0), reverse=True)
    picked += rows[:per_provider]
if not picked:
    sys.exit("NO MODELS FOUND")

opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
model_ratio = json.loads(opts.get("ModelRatio") or "{}")
completion_ratio = json.loads(opts.get("CompletionRatio") or "{}")
cache_ratio = json.loads(opts.get("CacheRatio") or "{}")

# new-api ratio 1 = $2 per 1M input tokens; quota is sold at the site's Price.
added = []
for m in picked:
    mid = m["id"]
    if mid in model_ratio:
        continue  # keep prices the admin already set
    pin, pout, pcache = price(m, "prompt"), price(m, "completion"), price(m, "input_cache_read")
    model_ratio[mid] = round(pin / 2, 6)
    completion_ratio[mid] = round(pout / pin, 6)
    if pcache > 0:
        cache_ratio[mid] = round(pcache / pin, 6)
    added.append((mid, pin, pout))

print(f"\n{len(picked)} models, {len(added)} new prices (USD per 1M tokens, input / output):")
for mid, pin, pout in added:
    print(f"  {mid:55s} {pin:8.3f} / {pout:8.3f}")
print("\nAdd channel and these prices? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

for key, value in (("ModelRatio", model_ratio), ("CompletionRatio", completion_ratio), ("CacheRatio", cache_ratio)):
    res = call("PUT", "/api/option/", {"key": key, "value": json.dumps(value)})
    if not res.get("success"):
        sys.exit(f"SET {key} FAILED: " + str(res.get("message")))

ids = [m["id"] for m in picked]
res = call("POST", "/api/channel/", {"mode": "single", "channel": {
    "type": 20, "name": "OpenRouter", "key": os.environ["KEY"].strip(),
    "models": ",".join(ids), "group": "default"}})
if not res.get("success"):
    sys.exit("ADD CHANNEL FAILED: " + str(res.get("message")))
items = call("GET", "/api/channel/?p=1&page_size=100")["data"]["items"]
cid = max(c["id"] for c in items if c.get("name") == "OpenRouter")
test_model = next((i for i in ids if i.startswith("openai/")), ids[0])
test = call("GET", f"/api/channel/test/{cid}?model={test_model}")
print(f"CHANNEL ADDED ({len(ids)} models). " + ("TEST OK" if test.get("success") else "TEST FAILED: " + str(test.get("message"))))
PY
