"""A scripted stand-in for Ollama's HTTP API, for the agent tests.

Each POST /api/chat pops the next round from `script` and streams it as NDJSON.
POST /api/show answers {"capabilities": caps[model]}; GET /api/tags lists caps' models. Request bodies are kept.
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FakeOllama:
    def __init__(self, script, caps=None):
        self.script = list(script)
        self.caps = caps or {}
        self.requests = []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _body(self):
                n = int(self.headers.get("Content-Length") or 0)
                return json.loads(self.rfile.read(n) or b"{}")

            def do_GET(self):
                if self.path == "/api/tags":
                    data = json.dumps({"models": [{"name": m} for m in fake.caps]}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                self.send_response(404)
                self.end_headers()

            def do_POST(self):
                body = self._body()
                if self.path == "/api/show":
                    model = body.get("model", "")
                    caps = fake.caps.get(model, ["completion"])
                    data = json.dumps({"capabilities": caps}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                if self.path == "/api/chat":
                    fake.requests.append(body)
                    chunks = fake.script.pop(0) if fake.script else [{"done": True}]
                    self.send_response(200)
                    self.send_header("Content-Type", "application/x-ndjson")
                    self.end_headers()
                    for c in chunks:
                        c = dict(c)
                        c.setdefault("model", body.get("model", ""))
                        c.setdefault("done", False)
                        if "message" in c:
                            c["message"] = {"role": "assistant", "content": "", **c["message"]}
                        self.wfile.write((json.dumps(c) + "\n").encode())
                        self.wfile.flush()
                    return
                self.send_response(404)
                self.end_headers()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()
