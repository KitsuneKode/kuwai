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

itemType: reasoning | assistant_message | command_execution | web_search |
          image_view | dynamic_tool_call
stdin (approvals): {"type": "request.resolve", "id": "q1", "decision": "accept"|"decline"}

Stdlib only.
"""

import base64
import json
import os
import sys
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
SYSTEM_VISION = (
    "You are a visual AI assistant operating on Arch Linux. Inspect screenshots, code, and interfaces with high "
    "fidelity and precision."
)


# ── Output ────────────────────────────────────────────────────────────────

def emit(ev):
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


def to_ollama_messages(messages):
    out = []
    for m in messages:
        entry = {"role": m.get("role", "user"), "content": m.get("content", "")}
        img = m.get("image") or ""
        if img and os.path.isfile(img):
            try:
                with open(img, "rb") as f:
                    entry["images"] = [base64.b64encode(f.read()).decode()]
            except OSError:
                pass
        out.append(entry)
    return out


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


def _fn(name, description, props=None, required=()):
    return {"type": "function", "function": {
        "name": name, "description": description,
        "parameters": {"type": "object", "properties": props or {}, "required": list(required)}}}


TOOLS = {
    "web_search": dict(
        schema=_fn("web_search", "Search the web. Use for facts you don't know or anything recent.",
                   {"query": {"type": "string", "description": "What to search for"}}, ["query"]),
        item="web_search", title=lambda a: f"Searching “{a.get('query', '')}”", approve=False, run=tool_web_search),
    "active_window": dict(
        schema=_fn("active_window", "The app and window title the user is looking at right now."),
        item="dynamic_tool_call", title=lambda a: "Active window", approve=False, run=tool_active_window),
    "system_info": dict(
        schema=_fn("system_info", "Live CPU load, memory, GPU and the focused window."),
        item="dynamic_tool_call", title=lambda a: "System info", approve=False, run=tool_system_info),
    "read_clipboard": dict(
        schema=_fn("read_clipboard", "The text on the user's clipboard."),
        item="dynamic_tool_call", title=lambda a: "Reading clipboard", approve=False, run=tool_read_clipboard),
    "read_selection": dict(
        schema=_fn("read_selection", "The text the user has selected (highlighted) on screen."),
        item="dynamic_tool_call", title=lambda a: "Reading selection", approve=False, run=tool_read_selection),
    "read_file": dict(
        schema=_fn("read_file", "Read a text file in the user's home folder.",
                   {"path": {"type": "string", "description": "Path, e.g. ~/notes.txt"}}, ["path"]),
        item="dynamic_tool_call", title=lambda a: f"Reading {a.get('path', '')}", approve=False, run=tool_read_file),
}


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
    if not tool:
        status, output = "failed", f"Unknown tool: {name}. Use only the tools you were given."
    elif bad:
        status, output = "failed", bad
    else:
        try:
            status, output = "completed", tool["run"](args)
        except ToolError as e:
            status, output = "failed", str(e)
        except Exception as e:
            status, output = "failed", f"{name} failed: {e}"
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
    messages = [{"role": "system", "content": system}] + to_ollama_messages(req.get("messages") or [])
    stats = {"evalCount": 0, "promptEvalCount": 0, "numCtx": int(options.get("num_ctx", 4096)), "tokensPerSec": 0.0}

    stream = Stream(ids)
    status, error = "completed", ""
    rounds = 0
    try:
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
    except urllib.error.URLError as e:
        stream.close("failed")
        status, error = "failed", f"Can't reach Ollama at {OLLAMA_HOST} ({e.reason})"
    except Exception as e:  # a broken stream must still end the turn
        stream.close("failed")
        status, error = "failed", str(e) or e.__class__.__name__

    emit({"type": "turn.completed", "status": status, "error": error, "stats": stats})


def main(req_file):
    try:
        with open(req_file, "r", encoding="utf-8") as f:
            req = json.load(f)
    except (OSError, ValueError) as e:
        emit({"type": "turn.completed", "status": "failed", "error": f"Bad request file: {e}", "stats": {}})
        return
    run_turn(req)
