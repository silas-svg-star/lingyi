#!/usr/bin/env bash
# 接入 GeToken（api.getoken.tech）当渠道，优先用它，失败时自动退回 OpenRouter：
#   cd ~/lingyi && git pull && sudo bash deploy/add-getoken.sh
# GeToken 的一个 Key 只能调它所在分组的模型，所以 Claude / GPT / Gemini 各填一个 Key（没有的直接回车跳过）。
# 管理员密码和 Key 只在服务器终端里输入，不显示、不存文件。
# 只接本站已经有价格的模型，朋友看到的价格不变；DeepSeek 继续走官方渠道。可以重复运行，会更新同名渠道。
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
BASE="${GETOKEN_BASE:-https://api.getoken.tech}"
NAME="${LINGYI_ADMIN:-}"; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
PASS="${LINGYI_PASS:-}"; if [ -z "$PASS" ]; then read -rsp "Admin password (hidden): " PASS; echo; fi
read -rsp "GeToken key for the Claude group (hidden, Enter to skip): " KEY_CLAUDE; echo
read -rsp "GeToken key for the GPT group (hidden, Enter to skip): " KEY_GPT; echo
read -rsp "GeToken key for the Gemini group (hidden, Enter to skip): " KEY_GEMINI; echo
export NAME PASS SITE BASE KEY_CLAUDE KEY_GPT KEY_GEMINI
cd "$(dirname "$0")"
python3 - <<'PY'
import json, os, re, sys, urllib.request, urllib.error, http.cookiejar
site, base = os.environ["SITE"], os.environ["BASE"].rstrip("/")
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
token = None
def call(method, path, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(site + path, method=method,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    try:
        with opener.open(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"success": False, "message": str(e)}

# family -> (channel name, new-api channel type, which of our model names belong to it)
# Claude goes through the native Anthropic protocol (14) so thinking/cache fields pass through; the rest use OpenAI (1).
families = [
    ("claude", "GeToken-Claude", 14, lambda n: n.startswith("claude-")),
    ("gpt", "GeToken-GPT", 1, lambda n: re.match(r"(gpt-|o\d|chatgpt-|codex-)", n) is not None),
    ("gemini", "GeToken-Gemini", 1, lambda n: n.startswith("gemini-")),
]
keys = {f: os.environ.get("KEY_" + f.upper(), "").strip() for f, *_ in families}
if not any(keys.values()):
    sys.exit("NO KEY ENTERED, nothing changed")

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

def pages(path):
    out, page = [], 1
    while True:
        d = call("GET", f"{path}?p={page}&page_size=100").get("data") or {}
        items = d.get("items") or []
        out += items
        if len(items) < 100:
            return out
        page += 1

def norm(n):
    # claude-opus-4.7 (OpenRouter style) and claude-opus-4-7 (Anthropic style) are the same model.
    return n.split("/", 1)[-1].lower().replace(".", "-")

# Every model name already sold on this site (from the existing channels), with a price.
chans = pages("/api/channel/")
opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
priced = set(json.loads(opts.get("ModelRatio") or "{}")) | set(json.loads(opts.get("ModelPrice") or "{}"))
ours = set()
for c in chans:
    if not c.get("name", "").startswith("GeToken"):
        ours.update(x.strip() for x in (c.get("models") or "").split(",") if x.strip())
ours = {n for n in ours if n in priced and "deepseek" not in n.lower()}

plan = []
for fam, cname, ctype, belongs in families:
    key = keys[fam]
    if not key:
        continue
    req = urllib.request.Request(base + "/v1/models", headers={"Authorization": "Bearer " + key})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            theirs = [m["id"] for m in json.load(r).get("data", [])]
    except Exception as e:
        sys.exit(f"CANNOT LIST GETOKEN MODELS for {fam} key: {e}")
    by_norm = {norm(t): t for t in theirs}
    models, mapping = [], {}
    for n in sorted(ours):
        short = n.split("/", 1)[-1]
        if not belongs(short):
            continue
        t = by_norm.get(norm(n))
        if t:
            models.append(n)
            if t != n:
                mapping[n] = t
    plan.append((fam, cname, ctype, key, models, mapping, len(theirs)))

retry = int(opts.get("RetryTimes") or 0)
print()
for fam, cname, ctype, key, models, mapping, total in plan:
    print(f"{cname}: GeToken lists {total} models, {len(models)} match models this site already sells")
    for n in models[:12]:
        print(f"    {n}" + (f"  ->  {mapping[n]}" if n in mapping else ""))
    if len(models) > 12:
        print(f"    ... and {len(models) - 12} more")
print(f"\nGeToken channels get priority 10, so they are tried first; OpenRouter stays as backup.")
if retry < 2:
    print(f"Retry on failure is {retry}; it will be set to 2 so a failed request falls back to OpenRouter.")
print("Privacy policy will list GeToken among the upstream providers.")
print("Prices are not changed.\n\nGo ahead? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

# Disclose the new upstream before any request is routed to it.
res = call("PUT", "/api/option/", {"key": "legal.privacy_policy", "value": open("legal/privacy-policy.md").read()})
if not res.get("success"):
    sys.exit("UPDATE PRIVACY POLICY FAILED, nothing else changed: " + str(res.get("message")))
if retry < 2:
    call("PUT", "/api/option/", {"key": "RetryTimes", "value": "2"})

for fam, cname, ctype, key, models, mapping, total in plan:
    if not models:
        print(f"{cname}: no matching models, skipped")
        continue
    body = {"type": ctype, "name": cname, "key": key, "base_url": base, "models": ",".join(models),
            "model_mapping": json.dumps(mapping) if mapping else "", "group": "default", "priority": 10}
    old = [c for c in chans if c.get("name") == cname]
    if old:
        res = call("PUT", "/api/channel/", dict(body, id=max(c["id"] for c in old)))
    else:
        res = call("POST", "/api/channel/", {"mode": "single", "channel": body})
    if not res.get("success"):
        print(f"{cname}: SAVE FAILED: {res.get('message')}")
        continue
    cid = max(c["id"] for c in pages("/api/channel/") if c.get("name") == cname)
    test = call("GET", f"/api/channel/test/{cid}?model={models[0]}")
    print(f"{cname} #{cid}: {len(models)} models, test {models[0]}: " +
          ("OK" if test.get("success") else "FAILED: " + str(test.get("message"))))
print("\nDONE. To stop using GeToken: 渠道管理 → disable the GeToken channels.")
PY
