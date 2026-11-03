"""Recall after compaction, against the real Ollama: does the model answer from the summary + kept
messages? python3 tests/agent/live/recall.py current 3   (prints facts recalled out of 5 per run)"""
import io
import json
import sys
from contextlib import redirect_stdout

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "bin"))
import rice_agent as a  # noqa: E402

SUMMARY = "- The user's name is Kitsune.\n- They have an RTX 4050 GPU.\n- The user prefers Lua configs over hyprlang."
MSGS = [
    {"role": "user", "content": "Remember: my editor is Neovim. Answer with just OK."},
    {"role": "assistant", "content": "OK"},
    {"role": "user", "content": "Remember: my repo is ~/Projects/rice. Answer with just OK."},
    {"role": "assistant", "content": "OK"},
    {"role": "user", "content": "Without using any tools: what's my name, GPU, config preference, editor and repo?"},
]
FACTS = ["Kitsune", "4050", "Lua", "Neovim", "Projects/rice"]


def run(variant):
    buf = io.StringIO()
    with redirect_stdout(buf):
        a.run_turn({"model": "hermes3:8b", "keep_alive": "10m", "summary": SUMMARY, "messages": MSGS,
                    "options": {"num_ctx": 4096, "temperature": 0.4}})
    ev = [json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]
    return "".join(e["text"] for e in ev if e["type"] == "item.delta")


variant, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    out = run(variant)
    got = [f for f in FACTS if f in out]
    print(f"{variant} {len(got)}/5 {out[:160]!r}")
