"""The rice assistant's local agent (called as `rice-ollama agent <request.json>`).

Drives Ollama's /api/chat, runs tools, and prints one JSON event per line on
stdout, using T3 Code's runtime vocabulary so other providers can emit the same:

  turn.started      {model}
  item.started      {id, itemType, title, input}
  item.delta        {id, text}
  item.completed    {id, status: completed|failed|declined, output}
  request.opened    {id, itemId, kind, summary, detail}
  request.resolved  {id, decision: accept|decline|timeout}
  turn.completed    {status: completed|interrupted|failed|max_tool_rounds, error, stats}
Every event also carries ts (ms since the epoch).

itemType: reasoning | assistant_message | command_execution | web_search |
          image_view | dynamic_tool_call
stdin (approvals): {"type": "request.resolve", "id": "q1", "decision": "accept"|"decline"}

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
MAX_TOOL_ROUNDS = 6

SYSTEM_GENERAL = (
    "You are a local AI assistant and systems architect running directly on Arch Linux with direct desktop "
    "integration. Be direct, concise, and technically rigorous. Never give corporate boilerplate or claim to be "
    "fictional. For code, output clean idiomatic snippets."
)
TOOL_GUIDE = (
    "\n\nYou have tools. When a tool can answer or do what the user asked, call it right away instead of "
    "describing what you would do. Don't ask for permission in your reply: tools that change things (run_command, "
    "launch_app, open_url) already ask the user to approve before they run. Use only the tools you were given, with "
    "arguments as a JSON object. After a tool returns, answer from its result; if it failed or was declined, say so "
    "briefly and don't retry the same call."
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
    if not lines:
        return ""
    return "Context (what I'm looking at):\n" + "\n".join(lines) + "\n\n"


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
    vision = next((m for m in installed_models() if "vision" in capabilities(m)), None)
    b64 = read_image(img)
    if not vision or not b64:
        why = "No vision model is installed" if not vision else "The screenshot is gone"
        emit({"type": "item.completed", "id": item_id, "status": "failed", "output": why})
        messages[last]["content"] += "\n\n[A screenshot was attached but couldn't be read.]"
        return
    payload = {"model": vision, "stream": True, "keep_alive": 0, "options": {"num_ctx": 4096},
               "messages": [{"role": "user", "content": DESCRIBE, "images": [b64]}]}
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


def tool_web_search(args):
    import urllib.parse
    q = str(args.get("query") or "").strip()
    if not q:
        raise ToolError("Give a query")
    url = "https://api.duckduckgo.com/?" + urllib.parse.urlencode({"q": q, "format": "json", "no_html": 1})
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
    try:
        with urllib.request.urlopen(req, timeout=6) as resp:
            d = json.loads(resp.read().decode())
    except Exception as e:
        raise ToolError(f"Search failed: {e}")
    parts = []
    if d.get("Heading"):
        parts.append(d["Heading"])
    if d.get("AbstractText"):
        parts.append(d["AbstractText"] + (f" ({d['AbstractURL']})" if d.get("AbstractURL") else ""))
    for t in (d.get("RelatedTopics") or [])[:5]:
        if isinstance(t, dict) and t.get("Text"):
            parts.append("- " + t["Text"] + (f" ({t['FirstURL']})" if t.get("FirstURL") else ""))
    if not parts:
        raise ToolError("No results")
    return _cap("\n".join(parts), 6000)


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
    out = (p.stdout or "") + (("\n" + p.stderr) if p.stderr else "")
    out = _cap(out.strip(), 8192)
    return (out + "\n" if out else "(no output)\n") + f"(exit {p.returncode})"


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
    # These act on the machine: each asks first (request.opened → stdin).
    # approve(args) -> (kind, summary, detail); it may raise ToolError to
    # fail the call before anyone is asked.
    "run_command": dict(
        schema=_fn("run_command", "Run a bash command on the user's machine. The user approves it first.",
                   {"command": {"type": "string", "description": "The bash command"},
                    "cwd": {"type": "string", "description": "Folder to run in (default ~)"}}, ["command"]),
        item="command_execution", title=lambda a: str(a.get("command", ""))[:80],
        approve=lambda a: ("command", "Run a command", str(a.get("command", ""))), run=tool_run_command),
    "launch_app": dict(
        schema=_fn("launch_app", "Open a desktop app by name. The user approves it first.",
                   {"name": {"type": "string", "description": "App name, e.g. Firefox"}}, ["name"]),
        item="dynamic_tool_call", title=lambda a: f"Open {a.get('name', '')}",
        approve=_launch_request, run=tool_launch_app),
    "open_url": dict(
        schema=_fn("open_url", "Open a web link in the browser. The user approves it first.",
                   {"url": {"type": "string", "description": "An http(s) URL"}}, ["url"]),
        item="dynamic_tool_call", title=lambda a: f"Open {a.get('url', '')}",
        approve=_url_request, run=tool_open_url),
}


# ── Approvals and cancel ──────────────────────────────────────────────────

class Interrupted(Exception):
    pass


class Approvals:
    """Reads {"type":"request.resolve"} lines from stdin on a thread."""

    def __init__(self):
        import queue
        import threading
        self.queue = queue.Queue()
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
                self.queue.put((msg.get("id"), msg.get("decision")))

    def ask(self, ids, item_id, kind, summary, detail):
        import queue
        import time
        rid = ids.next("q")
        self.pending = rid
        emit({"type": "request.opened", "id": rid, "itemId": item_id, "kind": kind,
              "summary": summary, "detail": detail})
        deadline = time.monotonic() + self.timeout
        decision = "timeout"
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                break
            try:
                got_id, got = self.queue.get(timeout=min(left, 0.25))
            except queue.Empty:
                continue
            if got_id == rid and got in ("accept", "decline"):
                decision = got
                break
        self.pending = None
        emit({"type": "request.resolved", "id": rid, "decision": decision})
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
    emit({"type": "item.started", "id": item_id, "itemType": item_type, "title": title, "input": args})
    try:
        if not tool:
            status, output = "failed", f"Unknown tool: {name}. Use only the tools you were given."
        elif bad:
            status, output = "failed", bad
        else:
            try:
                if tool["approve"]:
                    kind, summary, detail = tool["approve"](args)
                    decision = APPROVALS.ask(ids, item_id, kind, summary, detail)
                    if decision != "accept":
                        what = "command" if kind == "command" else "action"
                        emit({"type": "item.completed", "id": item_id, "status": "declined",
                              "output": "Timed out" if decision == "timeout" else "Declined"})
                        return "declined", f"The user declined this {what}."
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

def stream_round(payload, stream, stats):
    """One /api/chat call. Streams text/reasoning items, returns tool calls."""
    splitter = ThinkSplitter()
    calls = []
    for chunk in chat_stream(payload):
        if chunk.get("error"):
            raise RuntimeError(chunk["error"])
        msg = chunk.get("message") or {}
        if msg.get("thinking"):
            stream.write("reasoning", msg["thinking"])
        if msg.get("content"):
            for kind, text in splitter.feed(msg["content"]):
                stream.write(kind, text)
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


def run_turn(req):
    model = req.get("model") or "hermes3:8b"
    options = req.get("options") or {"num_ctx": 4096}
    caps = capabilities(model)
    use_tools = "tools" in caps
    ids = Ids()
    emit({"type": "turn.started", "model": model})

    system = SYSTEM_VISION if ("vision" in caps and not use_tools) else SYSTEM_GENERAL
    if use_tools:
        system += TOOL_GUIDE
    messages = [{"role": "system", "content": system}] + to_ollama_messages(req.get("messages") or [],
                                                                           "vision" in caps)
    stats = {"evalCount": 0, "promptEvalCount": 0, "numCtx": int(options.get("num_ctx", 4096)), "tokensPerSec": 0.0}

    stream = Stream(ids)
    status, error = "completed", ""
    rounds = 0
    try:
        vision_hop(ids, messages, stats)
        while True:
            capped = rounds >= MAX_TOOL_ROUNDS
            payload = {"model": model, "messages": messages, "stream": True,
                       "keep_alive": req.get("keep_alive", "5m"), "options": options}
            if use_tools and not capped:
                payload["tools"] = [t["schema"] for t in TOOLS.values()]
            if "thinking" in caps:
                payload["think"] = True
            calls = stream_round(payload, stream, stats)
            if capped:
                status = "max_tool_rounds"
                break
            if not calls:
                break
            rounds += 1
            messages.append({"role": "assistant", "content": stream.message_text(), "tool_calls": calls})
            stream.text.clear()
            for c in calls:
                fn = c.get("function") or {}
                name = fn.get("name", "")
                _, output = run_tool(ids, name, fn.get("arguments"))
                messages.append({"role": "tool", "tool_name": name, "content": output})
    except Interrupted:
        stream.close()
        status = "interrupted"
    except urllib.error.URLError as e:
        stream.close("failed")
        status, error = "failed", f"Can't reach Ollama at {OLLAMA_HOST} ({e.reason})"
    except Exception as e:  # a broken stream must still end the turn
        stream.close("failed")
        status, error = "failed", str(e) or e.__class__.__name__

    emit({"type": "turn.completed", "status": status, "error": error, "stats": stats})


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
