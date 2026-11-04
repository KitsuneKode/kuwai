"""The rice assistant's local agent (called as `rice-ollama agent <request.json>`).

Drives Ollama's /api/chat, runs tools, and prints one JSON event per line on
stdout, using T3 Code's runtime vocabulary so other providers can emit the same:

  turn.started      {model}
  turn.phase        {phase: loading|waiting}   before the first item
  item.started      {id, itemType, title, input, where?: "sandbox"}
  item.delta        {id, text}
  item.completed    {id, status: completed|failed|declined, output}
  request.opened    {id, itemId, kind: command|launch|open_url|question, summary, detail, options?}
  request.resolved  {id, decision: accept|decline|timeout, answer?}
  turn.completed    {status: completed|interrupted|failed|max_tool_rounds|repeating, error, stats, unapplied}
  turn.steered      {id, text}   a message from the user, taken into the running turn
Every event also carries ts (ms since the epoch).

itemType: reasoning | assistant_message | command_execution | file_change | web_search |
          image_view | dynamic_tool_call | user_input | context_compaction
stdin: {"type": "request.resolve", "id": "q1", "decision": "accept"|"decline", "answer"?: "…"}
       {"type": "turn.steer", "id": "s-1", "text": "…"}   (cuts text being written; else lands after the tool)

Stdlib only.
"""

import base64
import json
import os
import signal
import sys
import time
import urllib.error
import urllib.request

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
UA = {"User-Agent": "rice-ollama/1.0"}
MAX_TOOL_ROUNDS = 10
CHAT = ""            # the chat's id: its sandbox folder
# Ollama's num_predict is unlimited by default; a small model that falls into
# a loop then writes forever. 2048 tokens is ~8k characters, plenty for an answer.
NUM_PREDICT = 2048


class Repeating(Exception):
    """The answer is looping: the same stretch keeps coming back."""


def is_repeating(text, window=200, times=5):
    if len(text) < window * times:
        return False
    return text.count(text[-window:]) >= times

SYSTEM_GENERAL = (
    "You are a local AI assistant and systems architect running directly on Arch Linux with direct desktop "
    "integration. Be direct, concise, and technically rigorous. Never give corporate boilerplate or claim to be "
    "fictional. For code, output clean idiomatic snippets."
)
# Measured 2026-11-03 against the real models (5 prompts × 3 runs): with this
# wording hermes3 calls run_command 3/3 (0/3 before: it asked "type yes" in
# text), and deepseek-r1 answers a plain question in ~15 s instead of 90+ s of
# reasoning about tool JSON. Don't say "the user approves it" in tool
# descriptions: small models read it as "ask first".
TOOL_GUIDE = (
    "\n\nYou can use tools on this computer. Call a tool when the request is about this computer, the screen, "
    "the user's files or clipboard, running or opening something, or anything recent you'd need to look up. "
    "Otherwise answer directly with no tool. When the user asks you to run, open or do something, call the "
    "tool in this reply: the app shows the user a Run / Don't run prompt itself, so never ask for permission "
    "or confirmation in text. Never tell the user to use a tool: use it yourself (after web_search, read the "
    "best link with web_fetch when the snippets aren't enough). After a tool returns, answer from its result; "
    "if it failed or was declined, say so in one line."
)
SANDBOX_GUIDE = (
    " You also have your own isolated Linux sandbox: use sandbox_write and sandbox_run to write and run code, "
    "check calculations, or try things out, without asking; fix errors and run again until it works. For a "
    "task with several steps, call update_plan first and keep it current. Use run_command only for things on "
    "the user's own computer."
)
SYSTEM_VISION = (
    "You are a visual AI assistant operating on Arch Linux. Inspect screenshots, code, and interfaces with high "
    "fidelity and precision."
)


# ── Output ────────────────────────────────────────────────────────────────

def emit(ev):
    ev["ts"] = int(time.time() * 1000)
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


class Ids:
    def __init__(self):
        self.n = {}

    def next(self, letter):
        self.n[letter] = self.n.get(letter, 0) + 1
        return f"{letter}{self.n[letter]}"


ITEM_LETTER = {"reasoning": "r", "assistant_message": "m"}


class Stream:
    """Keeps one streaming item open at a time (reasoning or message) and
    switches items when the kind of text changes."""

    def __init__(self, ids):
        self.ids = ids
        self.kind = None
        self.id = None
        self.text = {}

    def write(self, kind, text):
        if not text:
            return
        if kind != self.kind:
            if kind == "assistant_message":
                text = text.lstrip()
                if not text:
                    return
            self.close()
            self.kind = kind
            self.id = self.ids.next(ITEM_LETTER[kind])
            self.text[self.id] = ""
            emit({"type": "item.started", "id": self.id, "itemType": kind,
                  "title": "Thinking" if kind == "reasoning" else "", "input": {}})
        self.text[self.id] += text
        emit({"type": "item.delta", "id": self.id, "text": text})

    def close(self, status="completed"):
        if self.id is not None:
            emit({"type": "item.completed", "id": self.id, "status": status, "output": ""})
        self.kind = None
        self.id = None

    def message_text(self):
        return "".join(t for i, t in self.text.items() if i.startswith("m"))


class ThinkSplitter:
    """Splits content carrying <think>…</think> into (kind, text) pieces, even
    when a tag is cut across chunks."""

    def __init__(self):
        self.buf = ""
        self.inside = False

    def _kind(self):
        return "reasoning" if self.inside else "assistant_message"

    def feed(self, text):
        self.buf += text
        out = []
        while self.buf:
            tag = "</think>" if self.inside else "<think>"
            i = self.buf.find(tag)
            if i >= 0:
                if i:
                    out.append((self._kind(), self.buf[:i]))
                self.buf = self.buf[i + len(tag):]
                self.inside = not self.inside
                continue
            keep = 0
            for k in range(min(len(tag) - 1, len(self.buf)), 0, -1):
                if tag.startswith(self.buf[-k:]):
                    keep = k
                    break
            cut = len(self.buf) - keep
            if cut:
                out.append((self._kind(), self.buf[:cut]))
            self.buf = self.buf[cut:]
            break
        return out

    def flush(self):
        rest, self.buf = self.buf, ""
        return [(self._kind(), rest)] if rest else []


# ── Ollama ────────────────────────────────────────────────────────────────

_caps = {}


def capabilities(model):
    if model not in _caps:
        try:
            body = json.dumps({"model": model}).encode()
            req = urllib.request.Request(f"{OLLAMA_HOST}/api/show", data=body,
                                         headers={"Content-Type": "application/json", **UA})
            with urllib.request.urlopen(req, timeout=3) as resp:
                _caps[model] = json.loads(resp.read().decode()).get("capabilities", []) or []
        except Exception:
            _caps[model] = []
    return _caps[model]


def is_loaded(model):
    try:
        req = urllib.request.Request(f"{OLLAMA_HOST}/api/ps", headers=UA)
        with urllib.request.urlopen(req, timeout=2) as resp:
            return any(m.get("name") == model or m.get("model") == model
                       for m in json.loads(resp.read().decode()).get("models", []))
    except Exception:
        return False


def chat_stream(payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(f"{OLLAMA_HOST}/api/chat", data=body,
                                 headers={"Content-Type": "application/json", **UA})
    with urllib.request.urlopen(req, timeout=180) as resp:
        while True:
            line = resp.readline()
            if not line:
                return
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue


def installed_models():
    try:
        req = urllib.request.Request(f"{OLLAMA_HOST}/api/tags", headers=UA)
        with urllib.request.urlopen(req, timeout=3) as resp:
            return [m.get("name", "") for m in json.loads(resp.read().decode()).get("models", []) if m.get("name")]
    except Exception:
        return []


def read_image(path):
    if not path or not os.path.isfile(path):
        return ""
    try:
        with open(path, "rb") as f:
            return base64.b64encode(f.read()).decode()
    except OSError:
        return ""


def context_block(ctx):
    """The snapshot fields the user kept, as a short block before their text.
    Order: App, Window, Workspace, Folder, Git, Selection, Clipboard."""
    if not isinstance(ctx, dict):
        return ""
    lines = []
    for key, label in (("app", "App"), ("title", "Window"), ("workspace", "Workspace"), ("cwd", "Folder")):
        if ctx.get(key):
            lines.append(f"{label}: {ctx[key]}")
    git = ctx.get("git")
    if isinstance(git, dict) and git.get("name"):
        g = f"Git: {git['name']} on {git.get('branch', '')}"
        if git.get("dirty_files"):
            g += "; changed: " + ", ".join(git["dirty_files"][:5])
        lines.append(g)
    for key, label in (("selection", "Selected text"), ("clipboard", "Clipboard")):
        if ctx.get(key):
            lines.append(f"{label}:\n```\n{_cap(str(ctx[key]), 4096)}\n```")
    files = files_block(ctx.get("files"))
    if not lines:
        return files
    return "Context (what I'm looking at):\n" + "\n".join(lines) + "\n\n" + files


FILE_BUDGET = 6000      # characters of attached files per message; run_turn sizes it to the window


def file_text(path):
    """A file's readable text: PDFs through pdftotext, text as UTF-8; None for binary."""
    if path.lower().endswith(".pdf"):
        p = _run(["pdftotext", "-layout", "-l", "40", path, "-"], timeout=20)
        if p.returncode != 0:
            raise ToolError(f"pdftotext failed: {p.stderr.strip()[:120]}")
        return p.stdout
    with open(path, "rb") as f:
        head = f.read(200_000)
    if b"\0" in head[:8192]:
        return None
    return head.decode("utf-8", errors="replace")


def files_block(files):
    """Attached files: their text inline (the budget split between them), and a
    copy in the chat's sandbox folder (files/) so code can work on the whole thing."""
    import shutil
    if not isinstance(files, list) or not files:
        return ""
    files = [f for f in files if isinstance(f, dict) and f.get("path")][:6]
    share = max(1500, FILE_BUDGET // max(1, len(files)))
    out = []
    for f in files:
        path = os.path.expanduser(str(f["path"]))
        name = os.path.basename(path)
        where = ""
        try:
            if os.path.getsize(path) <= 50_000_000:
                dest = rice_sandbox.workspace(CHAT) / "files"
                dest.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, dest / name)
                where = f" (also in your sandbox at files/{name})"
        except OSError:
            pass
        try:
            text = file_text(path)
        except (OSError, ToolError) as e:
            out.append(f"<file name=\"{name}\">Couldn't read it: {e}</file>")
            continue
        if text is None:
            out.append(f'<file name="{name}">A binary file{where}.</file>')
            continue
        cut = len(text) > share
        body = text[:share] + (f"\n… (cut: {len(text):,} characters in all{where})" if cut else "")
        out.append(f'<file name="{name}"{" cut" if cut else ""}>{where}\n{body}\n</file>')
    return "Attached files:\n" + "\n".join(out) + "\n\n"


def to_ollama_messages(messages, vision):
    """Request messages → Ollama's. Images go only to a vision model; for the
    others the caller replaces the last one with a description."""
    out = []
    for m in messages:
        content = context_block(m.get("context")) + (m.get("content") or "")
        entry = {"role": m.get("role", "user"), "content": content}
        img = m.get("image") or ""
        if img:
            if vision:
                b64 = read_image(img)
                if b64:
                    entry["images"] = [b64]
            else:
                entry["_image"] = img
        out.append(entry)
    return out


DESCRIBE = ("Describe this screenshot for another assistant who can't see it. Name the app, quote the text that "
            "matters (code, errors, headings) exactly, and say what the user seems to be doing. Plain text, under "
            "200 words.")


def vision_hop(ids, messages, stats):
    """Turn images into text for a model that can't see: the last image is
    described by an installed vision model (unloaded right after, one model
    in VRAM at a time); earlier ones become a short note."""
    last = max((i for i, m in enumerate(messages) if m.get("_image")), default=-1)
    for i, m in enumerate(messages):
        if i != last and m.pop("_image", ""):
            m["content"] += "\n\n[A screenshot was attached here.]"
    if last < 0:
        return
    img = messages[last].pop("_image", "") or ""
    item_id = ids.next("t")
    emit({"type": "item.started", "id": item_id, "itemType": "image_view",
          "title": "Looking at the screenshot", "input": {}})
    have = installed_models()
    # The everyday model sees images and is the quickest to load; else any vision model.
    vision = "qwen3.5:4b" if "qwen3.5:4b" in have else next((m for m in have if "vision" in capabilities(m)), None)
    b64 = read_image(img)
    if not vision or not b64:
        why = "No vision model is installed" if not vision else "The screenshot is gone"
        emit({"type": "item.completed", "id": item_id, "status": "failed", "output": why})
        messages[last]["content"] += "\n\n[A screenshot was attached but couldn't be read.]"
        return
    payload = {"model": vision, "stream": True, "keep_alive": 0, "options": {"num_ctx": 4096},
               "messages": [{"role": "user", "content": DESCRIBE, "images": [b64]}]}
    if "thinking" in capabilities(vision):
        payload["think"] = False
    text = ""
    for chunk in chat_stream(payload):
        if chunk.get("error"):
            raise RuntimeError(chunk["error"])
        text += (chunk.get("message") or {}).get("content") or ""
    text = text.strip()
    emit({"type": "item.completed", "id": item_id, "status": "completed", "output": text})
    messages[last]["content"] += f"\n\n[Screenshot: {text}]"


# ── Tools ─────────────────────────────────────────────────────────────────
# Each tool: schema for Ollama, the item type the UI shows, a title for the
# row, whether it needs the user's approval, and run(args) -> str. A tool
# raises ToolError for a failure the model should read.

class ToolError(Exception):
    pass


def _run(argv, timeout=3, input_text=None):
    import subprocess
    try:
        p = subprocess.run(argv, input=input_text, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise ToolError(f"{argv[0]} is not installed")
    except subprocess.TimeoutExpired:
        raise ToolError(f"{argv[0]} timed out")
    return p


ANSI = None


def strip_ansi(text):
    """Terminal colour and cursor codes: noise for the model and the UI."""
    global ANSI
    import re
    if ANSI is None:
        ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*(\x07|\x1b\\)|\r(?!\n)")
    return ANSI.sub("", text or "")


def _cap(text, limit):
    text = text or ""
    if len(text.encode()) <= limit:
        return text
    return text.encode()[:limit].decode(errors="ignore") + "\n… (cut)"


def tool_active_window(_args):
    p = _run(["hyprctl", "activewindow", "-j"])
    try:
        w = json.loads(p.stdout or "{}")
    except ValueError:
        raise ToolError("hyprctl gave no window")
    ws = (w.get("workspace") or {}).get("name", "")
    return f"App: {w.get('class', '')}\nWindow: {w.get('title', '')}\nWorkspace: {ws}"


def tool_system_info(_args):
    lines = []
    w = tool_active_window({})
    lines.append(w)
    p = _run(["free", "-h"])
    mem = (p.stdout or "").splitlines()
    if len(mem) >= 2:
        lines.append("Memory: " + " ".join(mem[1].split()[1:4]) + " (total used free)")
    try:
        with open("/proc/loadavg") as f:
            lines.append("Load: " + " ".join(f.read().split()[:3]))
    except OSError:
        pass
    try:
        p = _run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total,temperature.gpu",
                  "--format=csv,noheader,nounits"])
        if p.returncode == 0 and p.stdout.strip():
            lines.append("GPU: " + p.stdout.strip() + " (name, MiB used, MiB total, °C)")
    except ToolError:
        pass
    return "\n".join(lines)


def tool_read_clipboard(_args):
    p = _run(["wl-paste", "--no-newline", "--type", "text"])
    if p.returncode != 0:
        raise ToolError("The clipboard is empty or holds no text")
    return _cap(p.stdout, 8192)


def tool_read_selection(_args):
    p = _run(["wl-paste", "--no-newline", "--primary"])
    if p.returncode != 0 or not p.stdout:
        raise ToolError("Nothing is selected")
    return _cap(p.stdout, 8192)


def tool_read_file(args):
    raw = str(args.get("path") or "").strip()
    if not raw:
        raise ToolError("Give a path")
    home = os.path.realpath(os.path.expanduser("~"))
    path = os.path.realpath(os.path.join(home, os.path.expanduser(raw)))
    if path != home and not path.startswith(home + os.sep):
        raise ToolError("Only files under your home folder can be read")
    if not os.path.isfile(path):
        raise ToolError(f"No such file: {raw}")
    with open(path, "rb") as f:
        data = f.read(16384 + 1)
    if b"\0" in data[:4096]:
        raise ToolError("That file isn't text")
    return _cap(data.decode(errors="replace"), 16384)


# ── Web ───────────────────────────────────────────────────────────────────
# Search, free and keyless by default: SearXNG when you run one
# (RICE_SEARXNG_URL, JSON format enabled), Ollama's hosted search when
# OLLAMA_API_KEY is set, then DuckDuckGo's HTML endpoint, Bing's, Wikipedia. web_fetch reads a
# page as plain text. Checked 2026-11-03: html.duckduckgo.com/html returns
# `a.result__a` (title, link) and `a.result__snippet` per result.

BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"


def _http(url, data=None, headers=None, timeout=8, limit=2_000_000):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": BROWSER_UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read(limit)
        charset = resp.headers.get_content_charset() or "utf-8"
        return raw.decode(charset, errors="replace"), resp.headers.get_content_type()


def _real_link(href):
    import html as h
    import urllib.parse
    href = h.unescape(href or "")
    if "duckduckgo.com/l/?" in href:
        q = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
        href = (q.get("uddg") or [href])[0]
    if href.startswith("//"):
        href = "https:" + href
    return href


def _strip_tags(text):
    import html as h
    import re
    return re.sub(r"\s+", " ", h.unescape(re.sub(r"<[^>]+>", "", text or ""))).strip()


def search_duckduckgo(q, n):
    import re
    import urllib.parse
    url = os.environ.get("RICE_SEARCH_DDG_URL") or "https://html.duckduckgo.com/html/"
    page, _ = _http(url, data=urllib.parse.urlencode({"q": q}).encode())
    out = []
    for block in re.split(r'<div[^>]+class="[^"]*\bresult\b', page)[1:]:
        a = re.search(r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>', block, re.S)
        if not a or "/y.js?" in a.group(1) or "result--ad" in block[:300]:
            continue          # no link, or an ad (y.js click-through)
        snip = re.search(r'class="result__snippet"[^>]*>(.*?)</a>', block, re.S)
        out.append({"title": _strip_tags(a.group(2)), "url": _real_link(a.group(1)),
                    "snippet": _strip_tags(snip.group(1)) if snip else ""})
        if len(out) >= n:
            break
    return out


def search_bing(q, n):
    """Bing's HTML results: `li.b_algo` → `h2 a` (href is a /ck/a redirect whose
    `u=a1<base64url>` is the real link) and `p.b_lineclamp*` (snippet)."""
    import base64
    import re
    import urllib.parse
    base = os.environ.get("RICE_SEARCH_BING_URL") or "https://www.bing.com/search"
    page, _ = _http(base + "?" + urllib.parse.urlencode({"q": q}))
    out = []
    for block in page.split('<li class="b_algo"')[1:]:
        a = re.search(r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', block, re.S)
        if not a:
            continue
        import html as h
        href = h.unescape(a.group(1))
        u = urllib.parse.parse_qs(urllib.parse.urlparse(href).query).get("u", [""])[0]
        if u.startswith("a1"):
            try:
                href = base64.urlsafe_b64decode(u[2:] + "=" * (-len(u[2:]) % 4)).decode()
            except Exception:
                pass
        snip = re.search(r'<p class="b_lineclamp\d*"[^>]*>(.*?)</p>', block, re.S) or re.search(r'<p[^>]*>(.*?)</p>', block, re.S)
        out.append({"title": _strip_tags(a.group(2)), "url": href, "snippet": _strip_tags(snip.group(1)) if snip else ""})
        if len(out) >= n:
            break
    return out


def search_wikipedia(q, n):
    import urllib.parse
    base = os.environ.get("RICE_SEARCH_WIKI_URL") or "https://en.wikipedia.org/w/rest.php/v1/search/page"
    page, _ = _http(base + "?" + urllib.parse.urlencode({"q": q, "limit": n}))
    return [{"title": p.get("title", ""), "url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(p.get("key", "")),
             "snippet": _strip_tags(p.get("excerpt", ""))} for p in (json.loads(page).get("pages") or [])[:n]]


def search_searxng(base, q, n):
    import urllib.parse
    page, _ = _http(base.rstrip("/") + "/search?" + urllib.parse.urlencode({"q": q, "format": "json"}))
    d = json.loads(page)
    return [{"title": r.get("title", ""), "url": r.get("url", ""), "snippet": r.get("content", "")}
            for r in (d.get("results") or [])[:n]]


def search_ollama(key, q, n):
    body = json.dumps({"query": q, "max_results": n}).encode()
    page, _ = _http("https://ollama.com/api/web_search", data=body,
                    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    d = json.loads(page)
    return [{"title": r.get("title", ""), "url": r.get("url", ""), "snippet": (r.get("content") or "")[:300]}
            for r in (d.get("results") or [])[:n]]


def tool_web_search(args):
    q = str(args.get("query") or "").strip()
    if not q:
        raise ToolError("Give a query")
    n = 6
    chain = []
    if os.environ.get("RICE_SEARXNG_URL"):
        chain.append(lambda: search_searxng(os.environ["RICE_SEARXNG_URL"], q, n))
    if os.environ.get("OLLAMA_API_KEY"):
        chain.append(lambda: search_ollama(os.environ["OLLAMA_API_KEY"], q, n))
    # DuckDuckGo starts answering an "anomaly" (bot check) page after a burst of
    # searches (seen 2026-11-03), so Bing's HTML and then Wikipedia back it up.
    chain.append(lambda: search_duckduckgo(q, n))
    chain.append(lambda: search_bing(q, n))
    chain.append(lambda: search_wikipedia(q, n))
    errors, results = [], []
    for source in chain:
        try:
            results = source()
        except Exception as e:
            errors.append(str(e))
            continue
        if results:
            break
    if not results:
        raise ToolError("No results" + (f" ({errors[-1]})" if errors else ""))
    lines = []
    for i, r in enumerate(results, 1):
        lines.append(f"{i}. {r['title']} — {r['url']}")
        if r["snippet"]:
            lines.append("   " + r["snippet"])
    lines.append("\nIf these snippets don't answer the question, call web_fetch on the most relevant link "
                 "now, before answering.")
    return _cap("\n".join(lines), 6000)


# ── Shopping: live prices from the stores' own search pages ─────────────
# Amazon.in answers a plain request with full HTML (22 results, measured);
# Flipkart builds its results with JavaScript, so it goes through the
# sandbox's headless Chromium (~13 s). Both read 2026-11-03.

def _amazon(q, n):
    import html as h
    import re
    import urllib.parse
    base = os.environ.get("RICE_SHOP_AMAZON_URL") or "https://www.amazon.in"
    page, _ = _http(f"{base}/s?k={urllib.parse.quote_plus(q)}", timeout=12, limit=4_000_000,
                    headers={"Accept-Language": "en-IN,en;q=0.9", "Accept": "text/html"})
    out = []
    for b in re.split(r'data-component-type="s-search-result"', page)[1:]:
        b = b[:40000]
        title = re.search(r'<h2[^>]*aria-label="([^"]+)"', b) or re.search(r'<h2[^>]*>.*?<span[^>]*>([^<]+)</span>', b, re.S)
        link = re.search(r'href="(/[^"]*?/dp/\w+)', b)
        prices = re.findall(r'class="a-offscreen">([^<]+)<', b)
        if not (title and link and prices):
            continue
        rating = re.search(r'(\d\.\d) out of 5 stars', b)
        mrp = next((x.replace("M.R.P: ", "").replace("M.R.P.: ", "") for x in prices[1:] if x != prices[0]), "")
        asin = link.group(1).rsplit("/dp/", 1)[1]
        out.append({"title": h.unescape(title.group(1)).replace("Sponsored Ad - ", "").strip(), "price": prices[0],
                    "mrp": mrp, "rating": rating.group(1) if rating else "", "url": f"{base}/dp/{asin}",
                    "store": "Amazon"})
        if len(out) >= n:
            break
    return out


def _flipkart(q, n):
    import html as h
    import re
    import urllib.parse
    url = f"https://www.flipkart.com/search?q={urllib.parse.quote_plus(q)}"
    page = rice_sandbox.render_page(url, timeout=30)
    links = list(re.finditer(r'<a[^>]+href="(/[^"]+/p/itm[^"&]+)[^"]*"', page))
    out, seen = [], set()
    for i, m in enumerate(links):
        href = m.group(1)
        if href in seen:
            continue
        seen.add(href)
        nxt = next((x.start() for x in links[i + 1:] if x.group(1) != href), m.start() + 8000)
        text = h.unescape(re.sub(r"<[^>]+>", "\n", page[m.start():nxt]))
        lines = [l.strip() for l in text.split("\n") if l.strip() and l.strip() != "Add to Compare"]
        prices = [l for l in lines if re.fullmatch(r"₹[\d,]+", l)]
        title = next((l for l in lines if len(l) > 25 and not l.startswith("₹")), "")
        if not (title and prices):
            continue
        rating = next((l for l in lines if re.fullmatch(r"[1-5]\.\d", l)), "")
        out.append({"title": title, "price": prices[0], "mrp": prices[1] if len(prices) > 1 else "",
                    "rating": rating, "url": "https://www.flipkart.com" + href, "store": "Flipkart"})
        if len(out) >= n:
            break
    return out


def tool_shop_search(args):
    q = str(args.get("query") or "").strip()
    if not q:
        raise ToolError("Give a product to search for")
    store = str(args.get("store") or "both").lower()
    want = [("amazon", _amazon), ("flipkart", _flipkart)]
    lines, errors, i = [], [], 0
    for name, fn in want:
        if store not in ("both", "all", "") and store != name:
            continue
        if name == "flipkart" and not sandbox_ready():
            errors.append("Flipkart needs the sandbox's browser")
            continue
        try:
            found = fn(q, 5)
        except Exception as e:
            errors.append(f"{name.title()}: {e}")
            continue
        for r in found:
            i += 1
            t = r["title"] if len(r["title"]) <= 100 else r["title"][:99].rstrip(" ,-(/") + "…"
            lines.append(f"{i}. {t} — {r['url']}")
            extra = [f"{r['store']} {r['price']}"]
            if r["mrp"]:
                extra.append(f"MRP {r['mrp']}")
            if r["rating"]:
                extra.append(f"{r['rating']}★")
            lines.append("   " + " · ".join(extra))
    if not lines:
        raise ToolError("No products found" + (f" ({'; '.join(errors)})" if errors else ""))
    lines.append(f"\nLive prices, {time.strftime('%d %b %Y %H:%M')}. Quote prices and links exactly as listed here."
                 + (f" ({'; '.join(errors)})" if errors else ""))
    return _cap("\n".join(lines), 6000)


def page_text(html_text):
    """Readable text of a page: the title, then the body without scripts,
    styles, navigation, headers and footers; blocks become lines."""
    from html.parser import HTMLParser

    class P(HTMLParser):
        SKIP = {"script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "template"}
        BLOCK = {"p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "section", "article", "pre",
                 "blockquote", "main", "table", "ul", "ol"}

        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.skip = 0
            self.dates = []        # datetime of open <time>/<relative-time>: "03 Nov" → "03 Nov (2026-11-03)"
            self.in_title = False
            self.title = ""
            self.parts = []

        def handle_starttag(self, tag, attrs):
            if tag in self.SKIP:
                self.skip += 1
            elif tag == "title":
                self.in_title = True
            elif tag in ("time", "relative-time"):
                self.dates.append((dict(attrs).get("datetime") or "")[:10])
            elif tag in self.BLOCK:
                self.parts.append("\n")

        def handle_endtag(self, tag):
            if tag in self.SKIP:
                self.skip = max(0, self.skip - 1)
            elif tag == "title":
                self.in_title = False
            elif tag in ("time", "relative-time") and self.dates:
                d = self.dates.pop()
                if d and not self.skip:
                    self.parts.append(f" ({d})")
            elif tag in self.BLOCK:
                self.parts.append("\n")

        def handle_data(self, data):
            if self.in_title:
                self.title += data
            elif not self.skip:
                self.parts.append(data)

    import re
    p = P()
    p.feed(html_text)
    body = "".join(p.parts).replace("\xa0", " ")
    lines = [re.sub(r"[ \t]+", " ", l).strip() for l in body.split("\n")]
    text = "\n".join(l for l in lines if l)
    title = re.sub(r"\s+", " ", p.title).strip()
    return (title + "\n\n" if title else "") + text


def tool_web_fetch(args):
    url = str(args.get("url") or "").strip()
    if not (url.startswith("https://") or url.startswith("http://")):
        raise ToolError("Only http and https links can be read")
    try:
        page, ctype = _http(url, timeout=10)
    except Exception as e:
        raise ToolError(f"Couldn't read the page: {e}")
    looks_html = "html" in (ctype or "") or page.lstrip()[:200].lower().startswith(("<!doctype html", "<html"))
    text = page_text(page) if looks_html else page
    # Shops and apps fill the page with JavaScript: little text, or "enable JavaScript".
    if looks_html and (len(text) < 800 or "enable javascript" in text.lower()) and sandbox_ready():
        try:
            rendered = page_text(rice_sandbox.render_page(url))
            if len(rendered) > len(text):
                text = rendered
        except rice_sandbox.SandboxError:
            pass
    if not text.strip():
        raise ToolError("The page has no readable text")
    return _cap(text, 8000)       # ~2k tokens


def tool_run_command(args):
    import subprocess
    cmd = str(args.get("command") or "")
    cwd = os.path.expanduser(str(args.get("cwd") or "~"))
    if not os.path.isdir(cwd):
        cwd = os.path.expanduser("~")
    try:
        p = subprocess.run(["bash", "-lc", cmd], cwd=cwd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        raise ToolError("The command ran for 30 s and was stopped")
    out = strip_ansi((p.stdout or "") + (("\n" + p.stderr) if p.stderr else ""))
    out = _cap(out.strip(), 8192)
    return (out + "\n" if out else "(no output)\n") + f"(exit {p.returncode})"


# ── Sandbox (bin/rice_sandbox.py): its own Linux box, so no approval ─────

import rice_sandbox  # noqa: E402

_SANDBOX = None


def sandbox_ready():
    global _SANDBOX
    if _SANDBOX is None:
        if os.environ.get("RICE_SANDBOX") == "off":
            _SANDBOX = False
        else:
            try:
                _SANDBOX = rice_sandbox.state() != "no-image"
            except rice_sandbox.SandboxError:
                _SANDBOX = False
    return _SANDBOX


def tool_sandbox_run(args):
    cmd = str(args.get("command") or "").strip()
    if not cmd:
        raise ToolError("No command given")
    try:
        code, out = rice_sandbox.run(CHAT, cmd, timeout=120)
    except rice_sandbox.SandboxError as e:
        raise ToolError(str(e))
    out = _cap(strip_ansi(out), 8192)
    return (out + "\n" if out else "(no output)\n") + f"(exit {code})"


def tool_sandbox_write(args):
    try:
        full = rice_sandbox.resolve(CHAT, args.get("path"))
    except rice_sandbox.SandboxError as e:
        raise ToolError(str(e))
    content = str(args.get("content") or "")
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")
    rel = full.relative_to(rice_sandbox.workspace(CHAT))
    return f"Wrote {rel} ({content.count(chr(10)) + (1 if content and not content.endswith(chr(10)) else 0)} lines)"


def tool_sandbox_read(args):
    try:
        full = rice_sandbox.resolve(CHAT, args.get("path"))
    except rice_sandbox.SandboxError as e:
        raise ToolError(str(e))
    if not full.is_file():
        raise ToolError("No such file in the sandbox")
    with open(full, "rb") as f:
        data = f.read(16385)
    return _cap(data.decode(errors="replace"), 16384)


def tool_update_plan(args):
    steps = args.get("steps") or []
    if not isinstance(steps, list) or not steps:
        raise ToolError("Give the steps")
    clean = []
    for s in steps[:12]:
        if isinstance(s, str):
            s = {"step": s}
        if not isinstance(s, dict) or not str(s.get("step") or "").strip():
            continue
        st = str(s.get("status") or "pending")
        clean.append({"step": str(s["step"]).strip()[:160],
                      "status": st if st in ("pending", "in_progress", "completed") else "pending"})
    if not clean:
        raise ToolError("Give the steps")
    args["steps"] = clean          # the UI reads the cleaned list from the item's input
    done = sum(1 for s in clean if s["status"] == "completed")
    return f"Plan updated ({done} of {len(clean)} done). Carry on with the next step."


def _question_request(args):
    q = str(args.get("question") or "").strip()
    if not q:
        raise ToolError("No question given")
    opts = [str(o).strip() for o in (args.get("options") or []) if str(o).strip()][:6]
    return "question", q, "", opts


def desktop_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    rest = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return [os.path.join(d, "applications") for d in [home] + rest if d]


def find_app(query):
    """(desktop_id, name) like OllamaService.findApp: exact, prefix, substring."""
    q = (query or "").strip().lower()
    if not q:
        return None
    apps, seen = [], set()
    for d in desktop_dirs():
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".desktop") or fn in seen:
                continue
            seen.add(fn)
            name, hidden, in_entry = "", False, False
            try:
                with open(os.path.join(d, fn), encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("["):
                            in_entry = line == "[Desktop Entry]"
                        elif in_entry and line.startswith("Name=") and not name:
                            name = line[5:]
                        elif in_entry and line in ("NoDisplay=true", "Hidden=true"):
                            hidden = True
            except OSError:
                continue
            if name and not hidden:
                apps.append((fn[:-8], name))
    for test in (lambda i, n: n.lower() == q or i.lower() == q,
                 lambda i, n: n.lower().startswith(q),
                 lambda i, n: q in n.lower()):
        for i, n in apps:
            if test(i, n):
                return i, n
    return None


def tool_launch_app(args):
    found = find_app(args.get("name"))
    if not found:
        raise ToolError(f"No app called {args.get('name')!r}")
    p = _run(["gtk-launch", found[0]], timeout=5)
    if p.returncode != 0:
        raise ToolError(f"Couldn't open {found[1]}: {p.stderr.strip()}")
    return f"Opened {found[1]}."


def check_url(args):
    url = str(args.get("url") or "").strip()
    if not (url.startswith("https://") or url.startswith("http://")):
        raise ToolError("Only http and https links can be opened")
    return url


def tool_open_url(args):
    url = check_url(args)
    p = _run(["xdg-open", url], timeout=5)
    if p.returncode != 0:
        raise ToolError(f"Couldn't open the link: {p.stderr.strip()}")
    return f"Opened {url}."


def _launch_request(args):
    found = find_app(args.get("name"))
    if not found:
        raise ToolError(f"No app called {args.get('name')!r}")
    return "launch", f"Open {found[1]}", found[0]


def _url_request(args):
    url = check_url(args)
    return "open_url", "Open a link", url


def _fn(name, description, props=None, required=()):
    return {"type": "function", "function": {
        "name": name, "description": description,
        "parameters": {"type": "object", "properties": props or {}, "required": list(required)}}}


TOOLS = {
    "web_search": dict(
        schema=_fn("web_search", "Search the web. Use for facts you don't know or anything recent.",
                   {"query": {"type": "string", "description": "What to search for"}}, ["query"]),
        item="web_search", title=lambda a: f"Searching “{a.get('query', '')}”", approve=None, run=tool_web_search),
    "shop_search": dict(
        schema=_fn("shop_search", "Live product prices and links from Amazon.in and Flipkart. Use for any "
                   "question about buying something or what it costs now.",
                   {"query": {"type": "string", "description": "The product, e.g. laptop 16GB RAM under 60000"},
                    "store": {"type": "string", "enum": ["both", "amazon", "flipkart"]}}, ["query"]),
        item="web_search", title=lambda a: f"Shopping “{a.get('query', '')}”", approve=None, run=tool_shop_search),
    "web_fetch": dict(
        schema=_fn("web_fetch", "Read a web page as plain text, e.g. a link from web_search.",
                   {"url": {"type": "string", "description": "An http(s) URL"}}, ["url"]),
        item="dynamic_tool_call", title=lambda a: f"Reading {a.get('url', '')}", approve=None, run=tool_web_fetch),
    "active_window": dict(
        schema=_fn("active_window", "The app and window title the user is looking at right now."),
        item="dynamic_tool_call", title=lambda a: "Active window", approve=None, run=tool_active_window),
    "system_info": dict(
        schema=_fn("system_info", "Live CPU load, memory, GPU and the focused window."),
        item="dynamic_tool_call", title=lambda a: "System info", approve=None, run=tool_system_info),
    "read_clipboard": dict(
        schema=_fn("read_clipboard", "The text on the user's clipboard."),
        item="dynamic_tool_call", title=lambda a: "Reading clipboard", approve=None, run=tool_read_clipboard),
    "read_selection": dict(
        schema=_fn("read_selection", "The text the user has selected (highlighted) on screen."),
        item="dynamic_tool_call", title=lambda a: "Reading selection", approve=None, run=tool_read_selection),
    "read_file": dict(
        schema=_fn("read_file", "Read a text file in the user's home folder.",
                   {"path": {"type": "string", "description": "Path, e.g. ~/notes.txt"}}, ["path"]),
        item="dynamic_tool_call", title=lambda a: f"Reading {a.get('path', '')}", approve=None, run=tool_read_file),
    "sandbox_run": dict(
        schema=_fn("sandbox_run", "Run bash in your own isolated Linux sandbox (Debian with python3, node, npm, "
                   "git, curl, gcc, jq, rg). Use it to run code, test, calculate, convert files or install packages "
                   "with pip/npm. It can't see the user's files. Runs in the chat's folder.",
                   {"command": {"type": "string", "description": "The bash command"}}, ["command"]),
        item="command_execution", title=lambda a: str(a.get("command", ""))[:80], approve=None,
        run=tool_sandbox_run, sandbox=True),
    "sandbox_write": dict(
        schema=_fn("sandbox_write", "Create or overwrite a file in the sandbox folder.",
                   {"path": {"type": "string", "description": "File path relative to the folder, e.g. main.py"},
                    "content": {"type": "string", "description": "The whole file"}}, ["path", "content"]),
        item="file_change", title=lambda a: f"Writing {a.get('path', '')}", approve=None,
        run=tool_sandbox_write, sandbox=True),
    "sandbox_read": dict(
        schema=_fn("sandbox_read", "Read a file from the sandbox folder.",
                   {"path": {"type": "string", "description": "File path relative to the folder"}}, ["path"]),
        item="dynamic_tool_call", title=lambda a: f"Reading {a.get('path', '')}", approve=None,
        run=tool_sandbox_read, sandbox=True),
    "update_plan": dict(
        schema=_fn("update_plan", "For a task with several steps (coding, research, setup): write the plan "
                   "first, then call again as each step starts and finishes. Keep it to 2-8 short steps.",
                   {"steps": {"type": "array", "description": "The whole plan, in order",
                              "items": {"type": "object", "properties": {
                                  "step": {"type": "string"},
                                  "status": {"type": "string", "enum": ["pending", "in_progress", "completed"]}},
                                  "required": ["step", "status"]}}}, ["steps"]),
        item="todo_list", title=lambda a: "Plan", approve=None, run=tool_update_plan),
    "ask_user": dict(
        schema=_fn("ask_user", "Ask the user a short question when you need their choice or a detail you can't "
                   "find out yourself. Give 2-4 likely answers as options; they can also type their own.",
                   {"question": {"type": "string", "description": "The question"},
                    "options": {"type": "array", "items": {"type": "string"}, "description": "Likely answers"}},
                   ["question"]),
        item="user_input", title=lambda a: str(a.get("question", ""))[:80], approve=None, ask=_question_request,
        run=None),
    # These act on the machine: each asks first (request.opened → stdin).
    # approve(args) -> (kind, summary, detail); it may raise ToolError to
    # fail the call before anyone is asked.
    "run_command": dict(
        schema=_fn("run_command", "Run a bash command on this computer and get its output.",
                   {"command": {"type": "string", "description": "The bash command"},
                    "cwd": {"type": "string", "description": "Folder to run in (default ~)"}}, ["command"]),
        item="command_execution", title=lambda a: str(a.get("command", ""))[:80],
        approve=lambda a: ("command", "Run a command", str(a.get("command", ""))), run=tool_run_command),
    "launch_app": dict(
        schema=_fn("launch_app", "Open a desktop app by name.",
                   {"name": {"type": "string", "description": "App name, e.g. Firefox"}}, ["name"]),
        item="dynamic_tool_call", title=lambda a: f"Open {a.get('name', '')}",
        approve=_launch_request, run=tool_launch_app),
    "open_url": dict(
        schema=_fn("open_url", "Open a web link in the browser.",
                   {"url": {"type": "string", "description": "An http(s) URL"}}, ["url"]),
        item="dynamic_tool_call", title=lambda a: f"Open {a.get('url', '')}",
        approve=_url_request, run=tool_open_url),
}


# ── Approvals and cancel ──────────────────────────────────────────────────

class Interrupted(Exception):
    pass


class Steer(Exception):
    """A message from the user arrived mid-turn: cut the text being written."""


class Approvals:
    """Reads stdin on a thread: approvals ({"type":"request.resolve"}) and
    steers ({"type":"turn.steer","id","text"}: a message into the running turn)."""

    def __init__(self):
        import queue
        import threading
        self.queue = queue.Queue()
        self.lock = threading.Lock()
        self.steers = []
        self.pending = None
        self.timeout = float(os.environ.get("RICE_AGENT_APPROVAL_TIMEOUT") or 120)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in sys.stdin:
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("type") == "request.resolve":
                self.queue.put((msg.get("id"), msg.get("decision"), str(msg.get("answer") or "").strip()))
            elif msg.get("type") == "turn.steer" and str(msg.get("text") or "").strip():
                with self.lock:
                    self.steers.append({"id": str(msg.get("id") or ""), "text": str(msg["text"]).strip()})

    def has_steer(self):
        with self.lock:
            return bool(self.steers)

    def take_steers(self):
        with self.lock:
            out, self.steers = self.steers, []
        return out

    def ask(self, ids, item_id, kind, summary, detail, options=None, timeout=None):
        """Open a request and wait for its answer. Returns the decision; a
        question's typed or picked answer is left in self.answer."""
        import queue
        import time
        rid = ids.next("q")
        self.pending = rid
        self.answer = ""
        ev = {"type": "request.opened", "id": rid, "itemId": item_id, "kind": kind, "summary": summary, "detail": detail}
        if options is not None:
            ev["options"] = options
        emit(ev)
        deadline = time.monotonic() + (timeout or self.timeout)
        decision = "timeout"
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                break
            try:
                got_id, got, answer = self.queue.get(timeout=min(left, 0.25))
            except queue.Empty:
                continue
            if got_id == rid and got in ("accept", "decline"):
                decision = got
                self.answer = answer if got == "accept" else ""
                break
        self.pending = None
        ev = {"type": "request.resolved", "id": rid, "decision": decision}
        if self.answer:
            ev["answer"] = self.answer
        emit(ev)
        return decision

    def cancel_pending(self):
        if self.pending:
            emit({"type": "request.resolved", "id": self.pending, "decision": "decline"})
            self.pending = None


APPROVALS = None


def parse_args(raw):
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            v = json.loads(raw)
        except ValueError:
            raise ToolError("Bad arguments (not JSON)")
        if isinstance(v, dict):
            return v
        raise ToolError("Bad arguments (not an object)")
    return {}


def run_tool(ids, name, raw_args):
    """Run one tool call as an item. Returns (status, output) for the model."""
    tool = TOOLS.get(name)
    try:
        args = parse_args(raw_args)
    except ToolError as e:
        args, bad = {}, str(e)
    else:
        bad = ""
    item_type = tool["item"] if tool else "dynamic_tool_call"
    title = tool["title"](args) if tool else name
    item_id = ids.next("t")
    if tool and name == "update_plan" and not bad:
        try:
            tool_update_plan(args)         # clean the steps before the UI sees them
        except ToolError:
            pass
    ev = {"type": "item.started", "id": item_id, "itemType": item_type, "title": title, "input": args}
    if tool and tool.get("sandbox"):
        ev["where"] = "sandbox"
    emit(ev)
    try:
        if not tool:
            status, output = "failed", f"Unknown tool: {name}. Use only the tools you were given."
        elif bad:
            status, output = "failed", bad
        else:
            try:
                if tool.get("ask"):
                    kind, question, detail, options = tool["ask"](args)
                    # A question waits longer than an approval: the user may need to think.
                    decision = APPROVALS.ask(ids, item_id, kind, question, detail, options, timeout=600)
                    answer = APPROVALS.answer
                    if decision != "accept" or not answer:
                        emit({"type": "item.completed", "id": item_id, "status": "declined",
                              "output": "Timed out" if decision == "timeout" else "Skipped"})
                        return "declined", "The user didn't answer. Carry on with your best judgement and say what you assumed."
                    emit({"type": "item.completed", "id": item_id, "status": "completed", "output": answer})
                    return "completed", f"The user answered: {answer}"
                if tool["approve"]:
                    kind, summary, detail = tool["approve"](args)
                    decision = APPROVALS.ask(ids, item_id, kind, summary, detail)
                    if decision != "accept":
                        what = "command" if kind == "command" else "action"
                        emit({"type": "item.completed", "id": item_id, "status": "declined",
                              "output": "Timed out" if decision == "timeout" else "Declined"})
                        return "declined", (f"The user declined this {what}. Don't run it again or try another way "
                                            "to do it; say in one line that you didn't, and carry on without it.")
                status, output = "completed", tool["run"](args)
            except ToolError as e:
                status, output = "failed", str(e)
            except Interrupted:
                raise
            except Exception as e:
                status, output = "failed", f"{name} failed: {e}"
    except Interrupted:
        APPROVALS.cancel_pending()
        emit({"type": "item.completed", "id": item_id, "status": "declined", "output": "Stopped"})
        raise
    emit({"type": "item.completed", "id": item_id, "status": status, "output": output})
    return status, output


# ── The turn ──────────────────────────────────────────────────────────────

# ── Compaction ────────────────────────────────────────────────────────────
# Codex's approach, sized for a 4k window: when the UI says the chat is near
# full (`compact: true`), everything before the last two exchanges becomes a
# short handoff note written by the same model (already loaded), and the
# turn runs on note + recent messages. The UI keeps the note (`summary`).

COMPACT_PROMPT = (
    "Summarise this conversation for yourself, so you can carry on with less context. Keep what the user wants "
    "and prefers, the facts and decisions so far, names, numbers, paths, commands and apps exactly as written, "
    "and anything still open. If there is an earlier summary, carry over every point from it unless the "
    "conversation changed it. Plain bullet points, at most 200 words. Don't answer anything and don't add "
    "anything new."
)
SUMMARY_HEAD = "Here is a summary of what I told you earlier in this conversation (older messages were compacted):\n"


def compact(ids, model, caps, options, summary, convo):
    users = [i for i, m in enumerate(convo) if m.get("role") == "user"]
    if len(users) < 2 or users[-2] == 0:
        return summary, convo
    keep_from = users[-2]
    older = convo[:keep_from]
    # Each message cut to 1,500 characters, so one runaway answer can't crowd out the rest.
    lines = [("User: " if m["role"] == "user" else "Assistant: ") + _cap(m.get("content") or "", 1500) for m in older]
    text = ("Earlier summary:\n" + summary + "\n\n" if summary else "") + "Conversation:\n" + "\n\n".join(lines)
    item_id = ids.next("t")
    emit({"type": "item.started", "id": item_id, "itemType": "context_compaction",
          "title": "Summarising earlier messages", "input": {"kept": len(convo) - keep_from}})
    payload = {"model": model, "stream": True, "keep_alive": "5m", "options": options,
               "messages": [{"role": "system", "content": COMPACT_PROMPT}, {"role": "user", "content": _cap(text, 12000)}]}
    if "thinking" in caps:
        payload["think"] = False
    out, splitter = "", ThinkSplitter()
    try:
        for chunk in chat_stream(payload):
            if chunk.get("error"):
                raise RuntimeError(chunk["error"])
            for kind, t in splitter.feed((chunk.get("message") or {}).get("content") or ""):
                if kind == "assistant_message":
                    out += t
        out += "".join(t for k, t in splitter.flush() if k == "assistant_message")
    except Exception as e:
        emit({"type": "item.completed", "id": item_id, "status": "failed", "output": f"Couldn't summarise: {e}"})
        return summary, convo
    out = out.strip()
    if not out:
        emit({"type": "item.completed", "id": item_id, "status": "failed", "output": "The summary came back empty"})
        return summary, convo
    emit({"type": "item.completed", "id": item_id, "status": "completed", "output": out})
    return out, convo[keep_from:]


def stream_round(payload, stream, stats):
    """One /api/chat call. Streams text/reasoning items, returns tool calls."""
    splitter = ThinkSplitter()
    calls = []
    for chunk in chat_stream(payload):
        if chunk.get("error"):
            raise RuntimeError(chunk["error"])
        msg = chunk.get("message") or {}
        if stream.kind is not None and not calls and APPROVALS is not None and APPROVALS.has_steer():
            raise Steer()
        if msg.get("thinking"):
            stream.write("reasoning", msg["thinking"])
        if msg.get("content"):
            for kind, text in splitter.feed(msg["content"]):
                stream.write(kind, text)
            if stream.kind == "assistant_message" and len(stream.text[stream.id]) % 400 < len(msg["content"]) \
                    and is_repeating(stream.text[stream.id]):
                raise Repeating()
        if msg.get("tool_calls"):
            calls.extend(msg["tool_calls"])
        if chunk.get("done"):
            for kind, text in splitter.flush():
                stream.write(kind, text)
            ev, dur = chunk.get("eval_count") or 0, chunk.get("eval_duration") or 0
            stats["evalCount"] += ev
            stats["promptEvalCount"] = chunk.get("prompt_eval_count") or stats["promptEvalCount"]
            stats["tokensPerSec"] = round(ev / (dur / 1e9), 1) if dur else stats["tokensPerSec"]
    stream.close()
    return calls


def apply_steers(messages):
    for st in APPROVALS.take_steers():
        emit({"type": "turn.steered", "id": st["id"], "text": st["text"]})
        messages.append({"role": "user", "content": st["text"]})


def run_turn(req):
    global CHAT, FILE_BUDGET
    CHAT = str(req.get("chat") or "")
    # Files may fill about 40% of the window (≈3.5 characters a token).
    FILE_BUDGET = int(int((req.get("options") or {}).get("num_ctx", 4096)) * 1.4)
    model = req.get("model") or "qwen3.5:4b"
    options = dict(req.get("options") or {"num_ctx": 4096})
    options.setdefault("num_predict", NUM_PREDICT)
    caps = capabilities(model)
    use_tools = "tools" in caps
    ids = Ids()
    emit({"type": "turn.started", "model": model})
    # Before the first word: is the model still loading into VRAM (~10 s cold) or just thinking?
    emit({"type": "turn.phase", "phase": "waiting" if is_loaded(model) else "loading"})

    system = SYSTEM_VISION if ("vision" in caps and not use_tools) else SYSTEM_GENERAL
    # Small models fill in years from their training data ("released 2022"): give them today,
    # and ask for what the source says, as written.
    system += time.strftime(" Today is %A, %d %B %Y.") + (
        " When you answer from a tool result or a page, copy dates, numbers and names exactly as written there.")
    tools = [t["schema"] for t in TOOLS.values() if not t.get("sandbox") or sandbox_ready()]
    if use_tools:
        system += TOOL_GUIDE + (SANDBOX_GUIDE if sandbox_ready() else "")
    convo = to_ollama_messages(req.get("messages") or [], "vision" in caps)
    summary = (req.get("summary") or "").strip()
    stats = {"evalCount": 0, "promptEvalCount": 0, "numCtx": int(options.get("num_ctx", 4096)), "tokensPerSec": 0.0}

    stream = Stream(ids)
    status, error = "completed", ""
    rounds = 0
    nudged = False
    try:
        if req.get("compact"):
            summary, convo = compact(ids, model, caps, options, summary, convo)
        messages = [{"role": "system", "content": system}]
        if summary:
            # An opening exchange, not a second system message: with tools offered,
            # hermes3 ignores everything after a second system message (0/5 recall vs 5/5).
            messages += [{"role": "user", "content": SUMMARY_HEAD + summary},
                         {"role": "assistant", "content": "Got it."}]
        messages += convo
        vision_hop(ids, messages, stats)
        while True:
            capped = rounds >= MAX_TOOL_ROUNDS
            payload = {"model": model, "messages": messages, "stream": True,
                       "keep_alive": req.get("keep_alive", "5m"), "options": options}
            if use_tools and not capped:
                payload["tools"] = tools
            if "thinking" in caps:
                payload["think"] = bool(req.get("think", True)) and not capped
            if capped:
                # Out of tool rounds: answer now from what it has, no more thinking or tools.
                payload["messages"] = messages + [{"role": "user", "content":
                    "(You've used all your tool calls for this turn. Answer now from what you have, "
                    "and say what's left undone.)"}]
            try:
                calls = stream_round(payload, stream, stats)
            except Steer:
                # Keep what it had written, then let it hear the user.
                stream.close()
                partial = stream.message_text()
                stream.text.clear()
                if partial:
                    messages.append({"role": "assistant", "content": partial})
                apply_steers(messages)
                continue
            if capped:
                status = "max_tool_rounds"
                break
            if calls:
                # Keeping the plan current isn't work: it doesn't use up a round.
                if any((c.get("function") or {}).get("name") != "update_plan" for c in calls):
                    rounds += 1
                messages.append({"role": "assistant", "content": stream.message_text(), "tool_calls": calls})
                stream.text.clear()
                for c in calls:
                    fn = c.get("function") or {}
                    name = fn.get("name", "")
                    _, output = run_tool(ids, name, fn.get("arguments"))
                    messages.append({"role": "tool", "tool_name": name, "content": output})
            if APPROVALS is not None and APPROVALS.has_steer():
                # A steer that came in during the round or a tool: answer it in this turn.
                if not calls:
                    messages.append({"role": "assistant", "content": stream.message_text()})
                    stream.text.clear()
                apply_steers(messages)
                continue
            if not calls:
                # Small thinking models sometimes finish their tool work, think, and stop
                # without a word (seen with qwen3.5 after a sandbox loop): ask once for the answer.
                if not stream.message_text().strip() and rounds > 0 and not nudged and not capped:
                    nudged = True
                    messages.append({"role": "user", "content": "(Now answer my request from what you found.)"})
                    continue
                break
    except Interrupted:
        stream.close()
        status = "interrupted"
    except Repeating:
        stream.close()
        status = "repeating"
    except urllib.error.URLError as e:
        stream.close("failed")
        status, error = "failed", f"Can't reach Ollama at {OLLAMA_HOST} ({e.reason})"
    except Exception as e:  # a broken stream must still end the turn
        stream.close("failed")
        status, error = "failed", str(e) or e.__class__.__name__

    late = APPROVALS.take_steers() if APPROVALS is not None else []
    emit({"type": "turn.completed", "status": status, "error": error, "stats": stats,
          "unapplied": late})


def _on_term(_sig, _frame):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)  # once: the unwind must finish
    raise Interrupted()


def main(req_file):
    global APPROVALS
    signal.signal(signal.SIGTERM, _on_term)
    APPROVALS = Approvals()
    try:
        with open(req_file, "r", encoding="utf-8") as f:
            req = json.load(f)
    except (OSError, ValueError) as e:
        emit({"type": "turn.completed", "status": "failed", "error": f"Bad request file: {e}", "stats": {}})
        return
    run_turn(req)
