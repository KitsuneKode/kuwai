"""A scripted stand-in for Ollama's HTTP API, for the agent tests.

Each POST /api/chat pops the next round from `script` and streams it as NDJSON.
POST /api/show answers {"capabilities": caps[model]}; GET /api/tags lists caps' models. Request bodies are kept.
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FakeOllama:
    def __init__(self, script, caps=None, pages=None):
        self.script = list(script)
        self.caps = caps or {}
        # Other paths served as-is (search results, web pages): {path: (content_type, body)}.
        self.pages = pages or {}
        self.loaded = []          # what /api/ps reports as in memory
        self.requests = []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _body(self):
                n = int(self.headers.get("Content-Length") or 0)
                return json.loads(self.rfile.read(n) or b"{}")

            def _page(self):
                path = self.path.split("?")[0]
                if path not in fake.pages:
                    return False
                ctype, body = fake.pages[path]
                data = body.encode() if isinstance(body, str) else body
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return True

            def do_GET(self):
                if self._page():
                    return
                if self.path == "/api/ps":
                    data = json.dumps({"models": [{"name": m} for m in fake.loaded]}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                if self.path == "/api/tags":
                    data = json.dumps({"models": [{"name": m, "size": 4_700_000_000, "details": {"parameter_size": "8.0B"}} for m in fake.caps]}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                self.send_response(404)
                self.end_headers()

            def do_POST(self):
                if self.path.split("?")[0] in fake.pages:
                    self.rfile.read(int(self.headers.get("Content-Length") or 0))
                    self._page()
                    return
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
                        line = json.dumps(c).replace("__FAKE__", fake.url)   # scripts can point at this server
                        self.wfile.write((line + "\n").encode())
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
