"""bin/kuwai-render: clipboard Markdown previews never fetch anything."""
import json
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin" / "kuwai-render"


def render(text):
    r = subprocess.run([sys.executable, "-I", str(BIN)], input=text, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_an_image_in_copied_markdown_is_not_loaded():
    pytest.importorskip("markdown")
    out = render("# Notes\n\nSee ![the plan](https://tracker.example/pixel.png?u=me) and <img src=\"https://tracker.example/b.gif\">\n\n- one\n- two\n")
    assert out["kind"] == "markdown"
    assert "<img" not in out["html"]
    assert "tracker.example" not in out["html"].split("[image")[0] or "src=" not in out["html"]
    assert "src=" not in out["html"]
    assert "[image: the plan]" in out["html"]
