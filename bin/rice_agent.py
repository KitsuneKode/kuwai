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


# ── The turn ──────────────────────────────────────────────────────────────

def run_turn(req):
    model = req.get("model") or "hermes3:8b"
    options = req.get("options") or {"num_ctx": 4096}
    caps = capabilities(model)
    ids = Ids()
    emit({"type": "turn.started", "model": model})

    system = SYSTEM_VISION if ("vision" in caps and "tools" not in caps) else SYSTEM_GENERAL
    messages = [{"role": "system", "content": system}] + to_ollama_messages(req.get("messages") or [])
    stats = {"evalCount": 0, "promptEvalCount": 0, "numCtx": int(options.get("num_ctx", 4096)), "tokensPerSec": 0.0}

    stream = Stream(ids)
    status, error = "completed", ""
    try:
        payload = {"model": model, "messages": messages, "stream": True,
                   "keep_alive": req.get("keep_alive", "5m"), "options": options}
        if "thinking" in caps:
            payload["think"] = True
        splitter = ThinkSplitter()
        for chunk in chat_stream(payload):
            if chunk.get("error"):
                raise RuntimeError(chunk["error"])
            msg = chunk.get("message") or {}
            if msg.get("thinking"):
                stream.write("reasoning", msg["thinking"])
            if msg.get("content"):
                for kind, text in splitter.feed(msg["content"]):
                    stream.write(kind, text)
            if chunk.get("done"):
                for kind, text in splitter.flush():
                    stream.write(kind, text)
                ev, dur = chunk.get("eval_count") or 0, chunk.get("eval_duration") or 0
                stats["evalCount"] = ev
                stats["promptEvalCount"] = chunk.get("prompt_eval_count") or 0
                stats["tokensPerSec"] = round(ev / (dur / 1e9), 1) if dur else 0.0
        stream.close()
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
