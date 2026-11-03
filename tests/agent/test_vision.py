from conftest import started
from test_tools import answer, completion

CAPS = {"hermes3:8b": ["completion", "tools"], "minicpm-v:latest": ["completion", "vision"]}


def shot(tmp_path):
    p = tmp_path / "shot.png"
    p.write_bytes(b"\x89PNG fake")
    return str(p)


def test_vision_hop_for_text_model(run_agent, tmp_path):
    req = {"messages": [{"role": "user", "content": "what is this?", "image": shot(tmp_path)}]}
    events, fake = run_agent(req, [[{"message": {"content": "A terminal showing ls."}}, {"done": True}],
                                   answer("It's a terminal.")], caps=CAPS)
    hop, main = fake.requests
    assert hop["model"] == "minicpm-v:latest"
    assert hop["keep_alive"] == 0
    assert hop["messages"][-1]["images"]
    assert "tools" not in hop
    assert main["model"] == "hermes3:8b"
    last = main["messages"][-1]
    assert "images" not in last
    assert "[Screenshot: A terminal showing ls.]" in last["content"]
    item = started(events, "image_view")[0]
    assert completion(events, item["id"])["output"] == "A terminal showing ls."
    assert events[-1]["status"] == "completed"


def test_vision_model_gets_image_directly(run_agent, tmp_path):
    req = {"model": "minicpm-v:latest",
           "messages": [{"role": "user", "content": "what is this?", "image": shot(tmp_path)}]}
    events, fake = run_agent(req, [answer()], caps=CAPS)
    assert len(fake.requests) == 1
    assert fake.requests[0]["messages"][-1]["images"]
    assert started(events, "image_view") == []


def test_no_vision_model_installed(run_agent, tmp_path):
    req = {"messages": [{"role": "user", "content": "what is this?", "image": shot(tmp_path)}]}
    events, fake = run_agent(req, [answer()], caps={"hermes3:8b": ["completion", "tools"]})
    item = started(events, "image_view")[0]
    assert completion(events, item["id"])["status"] == "failed"
    assert "images" not in fake.requests[0]["messages"][-1]
    assert events[-1]["status"] == "completed"


def test_context_block(run_agent):
    ctx = {"app": "kitty", "title": "zsh — ~/rice", "workspace": "", "selection": "error: x", "clipboard": ""}
    req = {"messages": [{"role": "user", "content": "fix this", "context": ctx}]}
    _, fake = run_agent(req, [answer()], caps=CAPS)
    text = fake.requests[0]["messages"][-1]["content"]
    assert text.index("App: kitty") < text.index("Window: zsh — ~/rice") < text.index("error: x") < text.index("fix this")
    assert "Clipboard" not in text
    assert "Workspace" not in text
