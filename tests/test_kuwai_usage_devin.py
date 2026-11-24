"""kuwai-usage reads every Devin profile's quota, as dvwho does."""
import json
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Devin(BaseHTTPRequestHandler):
    seen = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        key = body["metadata"]["api_key"]
        Devin.seen.append((self.path, key))
        out = {"userStatus": {"email": key + "@example.com", "planStatus": {
            "planInfo": {"planName": "Max", "hideDailyQuota": True},
            "weeklyQuotaRemainingPercent": 92 if key == "one" else 0,
            "weeklyQuotaResetAtUnix": 4102444800}}}
        data = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


def test_each_devin_profile_is_an_account(tmp_path):
    srv = HTTPServer(("127.0.0.1", 0), Devin)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_port}"
    data = tmp_path / "data"
    for rel, key in (("devin", "one"), ("devin-personal/devin", "two")):
        (data / rel).mkdir(parents=True)
        (data / rel / "credentials.toml").write_text(f'windsurf_api_key = "{key}"\napi_server_url = "{url}"\n')
    env = dict(os.environ, HOME=str(tmp_path), XDG_DATA_HOME=str(data), XDG_STATE_HOME=str(tmp_path / "state"),
               T3CODE_HOME=str(tmp_path / "t3"))
    r = subprocess.run(["node", str(ROOT / "bin/kuwai-usage")], env=env, capture_output=True, text=True, timeout=30)
    srv.shutdown()
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    devin = next(p for p in out["providers"] if p["driver"] == "devin")
    acc = {a["name"]: a for a in devin["accounts"]}
    assert set(acc) == {"Devin", "Devin-2"}
    used = sorted(a["windows"][0]["used"] for a in acc.values())
    assert used == [8, 100]
    assert all(a["windows"][0]["label"] == "Weekly" and a["windows"][0]["resetsAt"] == 4102444800000 for a in acc.values())
    assert all(p == "/exa.seat_management_pb.SeatManagementService/GetUserStatus" for p, _ in Devin.seen)
