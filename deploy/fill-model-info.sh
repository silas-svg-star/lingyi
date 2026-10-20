#!/usr/bin/env bash
# 给渠道里"缺元数据"的模型一次性补上厂商、图标和简介（简介取自 OpenRouter 官方说明）。
# 只新增展示资料，不改价格、不改渠道。
#   cd ~/lingyi && git pull && sudo bash deploy/fill-model-info.sh
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
NAME="${LINGYI_ADMIN:-}"; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
PASS="${LINGYI_PASS:-}"; if [ -z "$PASS" ]; then read -rsp "Admin password (hidden): " PASS; echo; fi
export NAME PASS SITE
python3 - <<'PY'
import json, os, sys, urllib.request, urllib.error, http.cookiejar
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
info = {m["id"]: m for m in catalog}

# OpenRouter prefix -> (vendor name, lobehub icon)
VENDORS = {
    "openai": ("OpenAI", "OpenAI"), "anthropic": ("Anthropic", "Claude.Color"),
    "google": ("Google", "Gemini.Color"), "x-ai": ("xAI", "XAI"),
    "qwen": ("阿里巴巴", "Qwen.Color"), "moonshotai": ("Moonshot", "Moonshot"),
    "z-ai": ("智谱", "Zhipu.Color"), "thudm": ("智谱", "Zhipu.Color"),
    "meta-llama": ("Meta", "Meta.Color"), "mistralai": ("Mistral", "Mistral.Color"),
    "minimax": ("MiniMax", "Minimax.Color"), "deepseek": ("DeepSeek", "DeepSeek.Color"),
    "cohere": ("Cohere", "Cohere.Color"), "perplexity": ("Perplexity", "Perplexity.Color"),
    "nvidia": ("Nvidia", "Nvidia.Color"), "microsoft": ("Microsoft", "AzureAI"),
    "amazon": ("Amazon", "Aws.Color"), "baidu": ("百度", "Wenxin.Color"),
    "tencent": ("腾讯", "Hunyuan.Color"), "bytedance": ("字节跳动", "Doubao.Color"),
    "stepfun": ("阶跃星辰", "Stepfun.Color"),
}
GUESS = [("gpt", "openai"), ("o1", "openai"), ("o3", "openai"), ("o4", "openai"), ("claude", "anthropic"),
         ("gemini", "google"), ("grok", "x-ai"), ("qwen", "qwen"), ("kimi", "moonshotai"),
         ("glm", "z-ai"), ("llama", "meta-llama"), ("mistral", "mistralai"), ("minimax", "minimax"),
         ("deepseek", "deepseek")]

def prefix_of(name):
    if "/" in name:
        return name.split("/")[0].lower()
    low = name.lower()
    for key, p in GUESS:
        if low.startswith(key) or key in low:
            return p
    return None

# Existing vendors and model metadata.
vendors, page = [], 1
while True:
    d = call("GET", f"/api/vendors/?p={page}&page_size=100")["data"]
    vendors += d.get("items") or []
    if len(d.get("items") or []) < 100:
        break
    page += 1
def find_vendor(vname):
    for v in vendors:
        n = v["name"].lower()
        if n == vname.lower() or n.startswith(vname.lower() + " "):
            return v["id"]
    return None

have, rows, page = set(), {}, 1
while True:
    d = call("GET", f"/api/models/?p={page}&page_size=100")["data"]
    items = d.get("items") or []
    for m in items:
        if m.get("id"):
            have.add(m["model_name"])
            rows[m["model_name"]] = m
    if len(items) < 100:
        break
    page += 1

names, page = set(), 1
while True:
    items = call("GET", f"/api/channel/?p={page}&page_size=100")["data"].get("items") or []
    for c in items:
        names.update(x.strip() for x in (c.get("models") or "").split(",") if x.strip())
    if len(items) < 100:
        break
    page += 1

todo = sorted(n for n in names if n not in have or not rows[n].get("vendor_id"))
print(f"\n{len(names)} models on channels, {len(todo)} without info or vendor.")
if not todo:
    sys.exit("NOTHING TO FILL")
plan = []
for n in todo:
    p = prefix_of(n)
    vname, icon = VENDORS.get(p, (None, None)) if p else (None, None)
    if not vname and ":" in (info.get(n, {}).get("name") or ""):
        vname = info[n]["name"].split(":")[0].strip()  # OpenRouter names look like "Reka: Reka Edge"
    desc = (info.get(n, {}).get("description") or "").strip().replace("\n", " ")
    if len(desc) > 300:
        desc = desc[:297] + "..."
    plan.append((n, vname, icon, desc))
counts = {}
for _, vname, _, _ in plan:
    counts[vname or "(unknown vendor)"] = counts.get(vname or "(unknown vendor)", 0) + 1
for k, v in sorted(counts.items(), key=lambda x: -x[1]):
    print(f"  {k}: {v}")
print(f"\nAdd vendor/icon/description for these {len(todo)} models? Prices and channels are not touched. (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

done = failed = 0
for n, vname, icon, desc in plan:
    vid = 0
    if vname:
        vid = find_vendor(vname)
        if vid is None:
            res = call("POST", "/api/vendors/", {"name": vname, "icon": icon, "status": 1})
            if res.get("success"):
                vendors.append(res["data"])
                vid = res["data"]["id"]
            else:
                vid = 0
    if n in rows:
        if not vid:
            continue
        body = dict(rows[n], vendor_id=vid)
        if not body.get("description"):
            body["description"] = desc
        method = "PUT"
    else:
        body = {"model_name": n, "vendor_id": vid, "description": desc, "status": 1,
                "sync_official": 0, "name_rule": 0}
        method = "POST"
    try:
        res = call(method, "/api/models/", body)
    except urllib.error.HTTPError as e:
        res = {"success": False, "message": str(e)}
    if res.get("success"):
        done += 1
    else:
        failed += 1
        print(f"  failed {n}: {res.get('message')}")
print(f"DONE. Filled {done} models" + (f", {failed} failed" if failed else "") + ".")
PY
