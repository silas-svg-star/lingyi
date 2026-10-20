#!/usr/bin/env bash
# 把 OpenRouter 渠道里的模型名改成官方写法：anthropic/claude-sonnet-5.5 -> claude-sonnet-5.5。
# 用户调用新名字时，渠道会自动转成 OpenRouter 认的完整名字；价格、图标、简介跟着搬过去。
#   cd ~/lingyi && git pull && sudo bash deploy/official-names.sh
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
    try:
        with opener.open(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"success": False, "message": str(e)}

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

# new-api forces its own output/input ratio for some bare names (models with "/" are exempt).
# Mirrors getHardcodedCompletionModelRatio's locked cases in setting/ratio_setting/model_ratio.go.
def locked_completion(n):
    if n.startswith("gpt-"):
        if n == "gpt-4o-2024-05-13": return 3
        if n.startswith("gpt-4o"): return None
        if n.startswith("gpt-5"):
            if "." not in n: return 8
            if n.startswith("gpt-5.4-nano"): return 6.25
            if n.startswith("gpt-5.4"): return 6
            return None
        if n.startswith("gpt-4.5-preview"): return 2
        if n.startswith("gpt-4-turbo") or n.endswith("gpt-4-1106") or n.endswith("gpt-4-1105"): return 3
        if n.startswith("gpt-3.5"):
            if n == "gpt-3.5-turbo" or n.endswith("0125"): return 3
            if n.endswith("1106"): return 2
            return 4 / 3
        return None
    if n.startswith("o1") or n.startswith("o3"): return 4
    if n == "chatgpt-4o-latest": return 3
    if any(k in n for k in ("claude-3", "claude-sonnet-4", "claude-opus-4", "claude-haiku-4")): return 5
    if n.startswith("mistral-"): return 3
    if n.startswith("gemini-1.5") or n.startswith("gemini-2.0"): return 4
    if n in ("command-r", "command-r-plus", "command-r-08-2024", "command-r-plus-08-2024"):
        return {"command-r": 3, "command-r-plus": 5}.get(n, 4)
    if n.startswith(("ERNIE-Speed-", "ERNIE-Lite-", "ERNIE-Character", "ERNIE-Functions")): return 2
    return {"llama2-70b-4096": 0.8 / 0.64, "llama3-8b-8192": 2, "llama3-70b-8192": 0.79 / 0.59}.get(n)

chans = pages("/api/channel/")
orch = [c for c in chans if c.get("name") == "OpenRouter"]
if not orch:
    sys.exit("NO OPENROUTER CHANNEL")
chan = call("GET", f"/api/channel/{max(orch, key=lambda c: c['id'])['id']}")["data"]
models = [x.strip() for x in (chan.get("models") or "").split(",") if x.strip()]
try:
    mapping = json.loads(chan.get("model_mapping") or "{}") or {}
except ValueError:
    mapping = {}
taken = set()
for c in chans:
    if c["id"] != chan["id"]:
        taken.update(x.strip() for x in (c.get("models") or "").split(",") if x.strip())

opts = {o["key"]: o["value"] for o in call("GET", "/api/option/")["data"]}
ratio = json.loads(opts.get("ModelRatio") or "{}")
price = json.loads(opts.get("ModelPrice") or "{}")
comp = json.loads(opts.get("CompletionRatio") or "{}")
cache = json.loads(opts.get("CacheRatio") or "{}")

full = [x for x in models if "/" in x]
shorts = {}
for x in full:
    shorts.setdefault(x.split("/", 1)[1], []).append(x)

rename, kept = {}, []
for x in full:
    s = x.split("/", 1)[1]
    why = None
    if len(shorts[s]) > 1:
        why = "two vendors use this name"
    elif s in taken:
        why = "another channel already uses this name"
    elif s in models:
        why = "name already on this channel"
    elif x not in ratio and x not in price:
        why = "no price"
    else:
        lock = locked_completion(s)
        if lock is not None and lock + 1e-9 < float(comp.get(x, 1)):
            why = "built-in billing rule would undercharge"
    if why:
        kept.append((x, why))
    else:
        rename[x] = s

print(f"\nOpenRouter channel #{chan['id']}: {len(models)} models")
print(f"  rename to official name: {len(rename)}")
for x, s in list(rename.items())[:15]:
    print(f"    {x}  ->  {s}")
if len(rename) > 15:
    print(f"    ... and {len(rename) - 15} more")
if kept:
    print(f"  keep full name: {len(kept)}")
    for x, why in kept:
        print(f"    {x}  ({why})")
if not rename:
    sys.exit("NOTHING TO RENAME")
print(f"\nRename these {len(rename)} models? (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

# 1. Prices: copy each full-name entry to the short name (old keys stay, harmless).
for table in (ratio, price, comp, cache):
    for x, s in rename.items():
        if x in table:
            table[s] = table[x]
for key, value in (("ModelRatio", ratio), ("ModelPrice", price), ("CompletionRatio", comp), ("CacheRatio", cache)):
    res = call("PUT", "/api/option/", {"key": key, "value": json.dumps(value)})
    if not res.get("success"):
        sys.exit(f"SET {key} FAILED, channel not changed: " + str(res.get("message")))

# 2. Channel: short names on the list, mapped to OpenRouter's full id.
mapping.update({s: x for x, s in rename.items()})
new_models = [rename.get(x, x) for x in models]
res = call("PUT", "/api/channel/", {"id": chan["id"], "type": chan["type"],
                                    "models": ",".join(new_models), "model_mapping": json.dumps(mapping)})
if not res.get("success"):
    sys.exit("UPDATE CHANNEL FAILED: " + str(res.get("message")))

# 3. Model info cards: move vendor/icon/description to the short name.
moved = 0
for row in pages("/api/models/"):
    s = rename.get(row.get("model_name"))
    if row.get("id") and s:
        if call("PUT", "/api/models/", dict(row, model_name=s)).get("success"):
            moved += 1

test_model = next(iter(rename.values()))
test = call("GET", f"/api/channel/test/{chan['id']}?model={test_model}")
print(f"DONE. Renamed {len(rename)} models, moved {moved} info cards. Test {test_model}: " +
      ("OK" if test.get("success") else "FAILED: " + str(test.get("message"))))
PY
