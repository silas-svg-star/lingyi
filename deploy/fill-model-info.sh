#!/usr/bin/env bash
# 给渠道里的模型一次性补上厂商、图标和简介（简介取自 OpenRouter 官方说明）。
# 只新增展示资料，不改价格、不改渠道。
#   cd ~/lingyi && git pull && sudo bash deploy/fill-model-info.sh
set -e
SITE="${SITE:-http://127.0.0.1:3000}"
NAME="${LINGYI_ADMIN:-}"; while [ -z "$NAME" ]; do read -rp "Admin username: " NAME; done
PASS="${LINGYI_PASS:-}"; if [ -z "$PASS" ]; then read -rsp "Admin password (hidden): " PASS; echo; fi
export NAME PASS SITE
python3 - <<'PY'
import json, os, re, sys, urllib.request, urllib.error, http.cookiejar
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

if os.environ.get("OR_MODELS_FILE"):
    catalog = json.load(open(os.environ["OR_MODELS_FILE"]))["data"]
else:
    with urllib.request.urlopen("https://openrouter.ai/api/v1/models", timeout=60) as r:
        catalog = json.load(r)["data"]
info = {m["id"]: m for m in catalog}

# Icon names the web UI can draw (@lobehub/icons).
ICON_IDS = "Ace Adobe.Color AdobeFirefly.Color AgentVoice.Color AgnesAI Agui Ai2.Color Ai21 Ai302.Color Ai360.Color AiHubMix.Color AiMass.Color AionLabs.Color AirJelly.Color AiStudio AkashChat.Color AlephAlpha Alibaba.Color AlibabaCloud.Color AMDRadeonCloud.Color Amp.Color Anspire.Color AntGroup.Color Anthropic Antigravity.Color Anyscale.Color Apertis.Color Apple Arcee.Color AskVerdict.Color AssemblyAI.Color AtlasCloud Automatic.Color Aws.Color Aya.Color Azure.Color AzureAI.Color BAAI Baichuan.Color Baidu.Color BaiduCloud.Color Bailian.Color Baseten Bedrock.Color Bfl Bilibili.Color BilibiliIndex Bing.Color Bocha.Color Brave.Color BriaAI.Color Browserless BurnCloud.Color ByteDance.Color CapCut CelestoAI.Color CentML.Color Cerebras.Color ChatGLM.Color CherryStudio.Color Chutes Civitai.Color Claude.Color ClaudeCode.Color Cline Clipdrop Cloudflare.Color CodeBuddy.Color CodeFlicker.Color CodeGeeX.Color Codex.Color CogVideo.Color CogView.Color Cohere.Color Colab.Color CometAPI.Color ComfyUI.Color CommandA.Color CommandCode.Color Copilot.Color CopilotKit.Color Coqui.Color Coze CrewAI.Color Crusoe.Color Cursor CyberCut Dalle.Color Dbrx.Color Decart.Color DeepAI DeepCogito.Color DeepInfra.Color DeepL.Color DeepMind.Color DeepSeek.Color Devin.Color Dify.Color DigitalOcean Doc2X.Color DocSearch.Color Dolphin DotsStudio Doubao.Color DreamMachine ElevenLabs ElevenX EssentialAI.Color Exa.Color Fal.Color FastGPT.Color Featherless.Color Figma.Color Firecrawl.Color Fireworks.Color FishAudio Flora Flowith Flux Friendli Gemini.Color GeminiCLI.Color Gemma.Color GiteeAI Github GithubCopilot Glama Glif GLMV.Color GmiCloud Google.Color GoogleCloud.Color Goose Gradio.Color Greptile.Color Grok Groq Hailuo.Color Haiper HappyHorse Hedra HermesAgent Higress.Color Huawei.Color HuaweiCloud.Color HuggingFace.Color Hunyuan.Color Hyperbolic.Color IBM Ideogram IFlyTekCloud.Color Inception Inceptron.Color Inference Infermatic.Color Infinigence.Color Inflection InternLM.Color IoNet Jimeng.Color Jina Junie.Color Kagi KiloCode Kimi.Color Kiro.Color Kling.Color Kluster.Color Kolors.Color Krea KwaiKAT Kwaipilot.Color Lambda LangChain.Color Langfuse.Color LangGraph.Color LangSmith.Color LeptonAI.Color LG.Color Lightricks Liquid LiveKit.Color LlamaIndex.Color LLaVA.Color LlmApi.Color LmStudio LobeHub.Color LongCat.Color Lovable.Color Lovart Luma.Color Magic Make.Color Manus Mastra MCP McpSo.Color Menlo.Color Meshy.Color Meta.Color MetaAI.Color MetaGPT Microsoft.Color Midjourney Minimax.Color Mistral.Color ModelScope.Color Monica.Color Moonshot Morph.Color Moxt.Color MyShell.Color N8n.Color NanoBanana.Color Nebius NewAPI.Color Nextbit.Color NotebookLM Notion NousResearch Nova.Color NovelAI Novita.Color NPLCloud.Color Nvidia.Color Obsidian.Color Ollama OpenAI OpenChat.Color OpenClaw.Color OpenCode OpenHands.Color OpenHuman OpenRouter.Color OpenWebUI PaLM.Color Parasail Perceptron Perplexity.Color Phala.Color Phidata.Color Phind Pi Pika PixVerse.Color Player2.Color Poe.Color Pollinations Poolside.Color PPIO.Color PrunaAI.Color PydanticAI.Color Qingyan.Color Qiniu.Color Qoder.Color Qwen.Color Railway Recraft Reka Relace Replicate Replit.Color Reve RooCode RSSHub.Color Runway Rwkv.Color Sakana.Color SambaNova.Color Search1API.Color SearchApi SearXNG.Color SenseNova.Color SiliconCloud.Color SillyTavern.Color Skywork.Color Slock Smithery.Color Snowflake.Color SophNet.Color Sora.Color Spark.Color SpeedAI.Color Stability.Color StateCloud.Color Stepfun Straico.Color StreamLake.Color SubModel.Color Suno Sync Targon.Color Tavily.Color Tencent.Color TencentCloud.Color Tiangong.Color TII.Color Together.Color TopazLabs Trae.Color Tripo.Color TuriX Udio.Color UnionAlpha.Color Unsloth.Color Unstructured.Color Upstage.Color V0 VectorizerAI Venice.Color Vercel VertexAI.Color Vidu.Color Viggle Vllm.Color Volcengine.Color Voyage.Color Wafer Wandb.Color WaveSpeed Wenxin.Color Windsurf WorkersAI.Color WorldRouter XAI XiaomiMiMo Xinference.Color Xpay.Color Xuanyuan.Color Yandex Yi.Color YouMind Yuanbao.Color ZAI Zapier.Color Zeabur.Color Zencoder.Color ZenMux ZeroOne.Color Zhipu.Color".split()
ICON_BY_KEY = {re.sub(r"[^a-z0-9]", "", i.split(".")[0].lower()): i for i in ICON_IDS}

# OpenRouter prefix -> (vendor name, icon)
VENDORS = {
    "openai": ("OpenAI", "OpenAI"), "anthropic": ("Anthropic", "Claude.Color"),
    "google": ("Google", "Gemini.Color"), "x-ai": ("xAI", "XAI"),
    "qwen": ("阿里巴巴", "Qwen.Color"), "alibaba": ("阿里巴巴", "Qwen.Color"),
    "moonshotai": ("Moonshot", "Kimi.Color"), "z-ai": ("智谱", "Zhipu.Color"),
    "thudm": ("智谱", "Zhipu.Color"), "meta-llama": ("Meta", "Meta.Color"),
    "mistralai": ("Mistral", "Mistral.Color"), "minimax": ("MiniMax", "Minimax.Color"),
    "deepseek": ("DeepSeek", "DeepSeek.Color"), "cohere": ("Cohere", "Cohere.Color"),
    "perplexity": ("Perplexity", "Perplexity.Color"), "nvidia": ("Nvidia", "Nvidia.Color"),
    "microsoft": ("Microsoft", "Microsoft.Color"), "amazon": ("Amazon", "Nova.Color"),
    "baidu": ("百度", "Wenxin.Color"), "tencent": ("腾讯", "Hunyuan.Color"),
    "bytedance": ("字节跳动", "Doubao.Color"), "bytedance-seed": ("字节跳动", "Doubao.Color"),
    "stepfun": ("阶跃星辰", "Stepfun"), "stepfun-ai": ("阶跃星辰", "Stepfun"),
    "xiaomi": ("小米", "XiaomiMiMo"), "meituan": ("美团", "LongCat.Color"),
    "ai21": ("AI21", "Ai21"), "aion-labs": ("AionLabs", "AionLabs.Color"),
    "rekaai": ("Reka", "Reka"), "nousresearch": ("Nous Research", "NousResearch"),
    "arcee-ai": ("Arcee", "Arcee.Color"), "ibm-granite": ("IBM", "IBM"),
    "allenai": ("Ai2", "Ai2.Color"), "inception": ("Inception", "Inception"),
    "liquid": ("Liquid", "Liquid"), "inflection": ("Inflection", "Inflection"),
    "cognitivecomputations": ("Dolphin", "Dolphin"), "deepcogito": ("Deep Cogito", "DeepCogito.Color"),
    "kwaipilot": ("Kwaipilot", "Kwaipilot.Color"), "openrouter": ("OpenRouter", "OpenRouter.Color"),
}
GUESS = [("gpt", "openai"), ("o1", "openai"), ("o3", "openai"), ("o4", "openai"), ("claude", "anthropic"),
         ("gemini", "google"), ("grok", "x-ai"), ("qwen", "qwen"), ("kimi", "moonshotai"),
         ("glm", "z-ai"), ("llama", "meta-llama"), ("mistral", "mistralai"), ("minimax", "minimax"),
         ("deepseek", "deepseek")]

def prefix_of(name):
    if "/" in name:
        return name.split("/")[0].lstrip("~").lower()
    low = name.lower()
    for key, p in GUESS:
        if key in low:
            return p
    return None

def icon_for(prefix, vname):
    if prefix in VENDORS:
        return VENDORS[prefix][1]
    for k in (prefix or "", vname or ""):
        k = re.sub(r"[^a-z0-9]", "", k.lower())
        for cand in (k, k.removesuffix("ai"), k.removesuffix("labs")):
            if cand and cand in ICON_BY_KEY:
                return ICON_BY_KEY[cand]
    return ""

def pages(path):
    out, page = [], 1
    while True:
        d = call("GET", f"{path}?p={page}&page_size=100").get("data") or {}
        items = d.get("items") or []
        out += items
        if len(items) < 100:
            return out
        page += 1

vendors = pages("/api/vendors/")
def find_vendor(vname):
    for v in vendors:
        n = v["name"].lower()
        if n == vname.lower() or n.startswith(vname.lower() + " "):
            return v
    return None

rows = {m["model_name"]: m for m in pages("/api/models/") if m.get("id")}
names = set()
for c in pages("/api/channel/"):
    names.update(x.strip() for x in (c.get("models") or "").split(",") if x.strip())

plan = []
for n in sorted(names):
    row = rows.get(n)
    p = prefix_of(n)
    vname = VENDORS[p][0] if p in VENDORS else None
    if not vname and ":" in (info.get(n, {}).get("name") or ""):
        vname = info[n]["name"].split(":")[0].strip()  # OpenRouter names look like "Reka: Reka Edge"
    icon = icon_for(p, vname)
    need_vendor = bool(vname) and not (row and row.get("vendor_id"))
    need_icon = bool(icon) and not (row and row.get("icon"))
    if row is None or need_vendor or need_icon:
        plan.append((n, row, vname, icon))

print(f"\n{len(names)} models on channels, {len(plan)} need vendor, icon or description.")
if not plan:
    sys.exit("NOTHING TO FILL")
counts = {}
for _, _, vname, icon in plan:
    k = (vname or "(unknown vendor)") + ("" if icon else ", no icon")
    counts[k] = counts.get(k, 0) + 1
for k, v in sorted(counts.items(), key=lambda x: -x[1]):
    print(f"  {k}: {v}")
print(f"\nFill these {len(plan)} models? Prices and channels are not touched. (y/n): ", end="", flush=True)
answer = os.environ.get("CONFIRM") or open("/dev/tty").readline()
if answer.strip().lower() != "y":
    sys.exit("CANCELLED, nothing changed")

def vendor_id(vname, icon):
    if not vname:
        return 0
    v = find_vendor(vname)
    if v is None:
        res = call("POST", "/api/vendors/", {"name": vname, "icon": icon, "status": 1})
        if not res.get("success"):
            return 0
        v = res["data"]
        vendors.append(v)
    elif icon and not v.get("icon"):
        res = call("PUT", "/api/vendors/", dict(v, icon=icon))
        if res.get("success"):
            v["icon"] = icon
    return v["id"]

done = failed = 0
for n, row, vname, icon in plan:
    vid = vendor_id(vname, icon)
    desc = (info.get(n, {}).get("description") or "").strip().replace("\n", " ")
    if len(desc) > 300:
        desc = desc[:297] + "..."
    if row:
        body = dict(row)
        if vid and not body.get("vendor_id"):
            body["vendor_id"] = vid
        if icon and not body.get("icon"):
            body["icon"] = icon
        if not body.get("description"):
            body["description"] = desc
        res = call("PUT", "/api/models/", body)
    else:
        res = call("POST", "/api/models/", {"model_name": n, "vendor_id": vid, "icon": icon,
                                            "description": desc, "status": 1,
                                            "sync_official": 0, "name_rule": 0})
    if res.get("success"):
        done += 1
    else:
        failed += 1
        print(f"  failed {n}: {res.get('message')}")
print(f"DONE. Filled {done} models" + (f", {failed} failed" if failed else "") + ".")
PY
