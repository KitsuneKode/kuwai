"""Measure the small models' tool habits against the real Ollama.

python3 tests/agent/live/toolhabits.py <current|v2> <model> <trials>   (real Ollama; "current" is the shipped wording)
Prints, per prompt: how many trials called the expected tool, and seconds per turn.
Approvals are declined automatically, so nothing runs.
"""
import io
import json
import sys
import time
from contextlib import redirect_stdout

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "bin"))
import rice_agent as a  # noqa: E402

VARIANTS = {
    "current": None,
    "v2": (
        "\n\nYou can use tools on this computer. Call a tool when the request is about this computer, the screen, "
        "the user's files or clipboard, running or opening something, or anything recent you'd need to look up. "
        "Otherwise answer directly with no tool. When the user asks you to run, open or do something, call the "
        "tool in this reply: the app shows the user a Run / Don't run prompt itself, so never ask for permission "
        "or confirmation in text. After a tool returns, answer from its result; if it failed or was declined, say "
        "so in one line."
    ),
}

PROMPTS = [
    ("Run the shell command: touch ~/approval-test.txt", "run_command"),
    ("Open Firefox for me.", "launch_app"),
    ("Is 391 a prime number?", None),
    ("What's the capital of Australia?", None),
    ("What app am I using right now?", "active_window"),
]


class Decline:
    pending = None
    answer = ""

    def has_steer(self):
        return False

    def take_steers(self):
        return []

    def ask(self, ids, item_id, kind, summary, detail, options=None, timeout=None):
        a.emit({"type": "request.opened", "id": "q", "itemId": item_id, "kind": kind, "summary": summary, "detail": detail})
        a.emit({"type": "request.resolved", "id": "q", "decision": "decline"})
        return "decline"

    def cancel_pending(self):
        pass


def trial(model, prompt):
    a.APPROVALS = Decline()
    buf = io.StringIO()
    t0 = time.time()
    with redirect_stdout(buf):
        a.run_turn({"model": model, "keep_alive": "10m", "options": {"num_ctx": 4096, "temperature": 0.4},
                    "messages": [{"role": "user", "content": prompt}]})
    events = [json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]
    tools = [e["title"] for e in events if e["type"] == "item.started" and e["itemType"] not in ("reasoning", "assistant_message")]
    names = [e for e in events if e["type"] == "request.opened"]
    return events, time.time() - t0


def main():
    variant, model, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    if VARIANTS[variant] is not None:
        a.TOOL_GUIDE = VARIANTS[variant]
        d = {"run_command": "Run a bash command on this computer and get its output.",
             "launch_app": "Open a desktop app by name.",
             "open_url": "Open a web link in the browser."}
        for k, v in d.items():
            a.TOOLS[k]["schema"]["function"]["description"] = v
    for prompt, want in PROMPTS:
        hits, secs = 0, []
        for _ in range(n):
            events, dt = trial(model, prompt)
            secs.append(dt)
            called = [e for e in events if e["type"] == "item.started" and e["itemType"] not in ("reasoning", "assistant_message")]
            titles = [e["title"] for e in called]
            if want is None:
                hits += 1 if not called else 0
            else:
                want_title = a.TOOLS[want]["title"]({})
                kinds = {"run_command": "command_execution"}
                ok = any(e["itemType"] == kinds.get(want, e["itemType"]) and (want != "launch_app" or e["title"].startswith("Open"))
                         and (want != "active_window" or e["title"] == "Active window") for e in called)
                hits += 1 if ok else 0
        label = want or "no tool"
        print(f"{variant:8} {model:16} {hits}/{n} {label:14} {sum(secs)/n:5.1f}s  {prompt}")


main()
