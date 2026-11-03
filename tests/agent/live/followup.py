"""Does the model follow a search with web_fetch itself, instead of telling the
user to? Real Ollama and real web. python3 tests/agent/live/followup.py <model> <trials>"""
import io
import json
import sys
import time
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "bin"))
import rice_agent as a  # noqa: E402

PROMPT = "Search the web for the Hyprland 0.57 release date."


class Decline:
    pending = None

    def ask(self, *x):
        return "decline"

    def cancel_pending(self):
        pass


model, n = sys.argv[1], int(sys.argv[2])
a.APPROVALS = Decline()
for _ in range(n):
    buf, t = io.StringIO(), time.time()
    with redirect_stdout(buf):
        a.run_turn({"model": model, "keep_alive": "10m", "messages": [{"role": "user", "content": PROMPT}],
                    "options": {"num_ctx": 4096, "temperature": 0.4}})
    ev = [json.loads(l) for l in buf.getvalue().splitlines() if l.strip()]
    tools = [e["title"][:40] for e in ev if e["type"] == "item.started" and e["itemType"] not in ("reasoning", "assistant_message")]
    ids = {e["id"] for e in ev if e["type"] == "item.started" and e["itemType"] == "assistant_message"}
    ans = "".join(e["text"] for e in ev if e["type"] == "item.delta" and e["id"] in ids)
    fetched = any(x.startswith("Reading http") for x in tools)
    tells = "web_fetch" in ans or "function" in ans.lower()
    print(f"fetched={fetched!s:5} tells_user={tells!s:5} {time.time() - t:5.1f}s {tools} {ans[:100]!r}")
