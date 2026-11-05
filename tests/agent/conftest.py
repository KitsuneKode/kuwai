import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from fake_ollama import FakeOllama  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "bin" / "rice-ollama"
STUBS = Path(__file__).parent / "stubs"


def parse_events(stdout):
    return [json.loads(line) for line in stdout.splitlines() if line.strip()]


@pytest.fixture
def run_agent(tmp_path):
    """run_agent(req, script, caps={}, stdin_lines=[], env={}) -> (events, fake)"""

    def run(req, script, caps=None, stdin_lines=(), env=None, host=None, pages=None):
        req = {"model": "hermes3:8b", "options": {"num_ctx": 4096}, **req}
        req_file = tmp_path / "request.json"
        req_file.write_text(json.dumps(req))
        with FakeOllama(script, caps, pages) as fake:
            e = {
                **os.environ,
                "OLLAMA_HOST": host or fake.url,
                "RICE_SEARCH_DDG_URL": fake.url + "/ddg",
                "RICE_SEARCH_BING_URL": fake.url + "/bing",
                "RICE_SEARCH_WIKI_URL": fake.url + "/wiki",
                "RICE_SHOP_AMAZON_URL": fake.url + "/amz",
                "RICE_SEARXNG_URL": "",
                "OLLAMA_API_KEY": "",
                "PATH": f"{STUBS}:{os.environ['PATH']}",
                "HOME": str(tmp_path),
                "RICE_TEST_TMP": str(tmp_path),
                "RICE_SANDBOX": "off",
                "RICE_AGENT_TOOLS": "all",
                "RICE_FETCH_ALLOW_LOCAL": "1",      # the fake web lives on 127.0.0.1
                "XDG_CONFIG_HOME": str(tmp_path / "config"),
                "XDG_CACHE_HOME": str(tmp_path / "cache"),
                "RICE_SANDBOX_DIR": str(tmp_path / "sandbox"),
                **(env or {}),
            }
            stdin = "".join(json.dumps(l) + "\n" for l in stdin_lines)
            proc = subprocess.run(
                [str(HELPER), "agent", str(req_file)],
                input=stdin, capture_output=True, text=True, env=e, timeout=30,
            )
        assert proc.returncode == 0, proc.stderr
        return parse_events(proc.stdout), fake

    return run


@pytest.fixture
def start_agent(tmp_path):
    """start_agent(req, script, caps) -> context manager yielding (Popen, fake)"""
    import contextlib

    @contextlib.contextmanager
    def start(req, script, caps=None):
        req = {"model": "hermes3:8b", "options": {"num_ctx": 4096}, **req}
        req_file = tmp_path / "request.json"
        req_file.write_text(json.dumps(req))
        with FakeOllama(script, caps) as fake:
            e = {**os.environ, "OLLAMA_HOST": fake.url, "PATH": f"{STUBS}:{os.environ['PATH']}",
                 "HOME": str(tmp_path), "RICE_TEST_TMP": str(tmp_path)}
            proc = subprocess.Popen([str(HELPER), "agent", str(req_file)], stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=e)
            try:
                yield proc, fake
            finally:
                if proc.poll() is None:
                    proc.kill()
                proc.wait(timeout=10)

    return start


def types(events):
    return [e["type"] for e in events]


def item_text(events, item_id):
    return "".join(e["text"] for e in events if e["type"] == "item.delta" and e["id"] == item_id)


def started(events, item_type):
    return [e for e in events if e["type"] == "item.started" and e["itemType"] == item_type]
