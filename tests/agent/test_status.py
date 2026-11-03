import json
import os
import subprocess

from conftest import HELPER
from fake_ollama import FakeOllama


def test_status_includes_capabilities_and_size():
    caps = {"hermes3:8b": ["completion", "tools"], "minicpm-v:latest": ["completion", "vision"]}
    with FakeOllama([], caps) as fake:
        out = subprocess.run([str(HELPER), "status"], capture_output=True, text=True, timeout=15,
                             env={**os.environ, "OLLAMA_HOST": fake.url}).stdout
    data = json.loads(out)
    assert data["status"] == "ready"
    assert data["models"] == ["hermes3:8b", "minicpm-v:latest"]
    info = data["info"]
    assert info["hermes3:8b"] == {"capabilities": ["completion", "tools"], "sizeGb": 4.7, "params": "8.0B"}
    assert info["minicpm-v:latest"]["capabilities"] == ["completion", "vision"]
