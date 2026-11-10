"""The jail holds: nothing the model or the container does reaches the host
without approval. Each test is something that must FAIL to escape."""
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))


@pytest.fixture
def agent(tmp_path, monkeypatch):
    monkeypatch.setenv("RICE_SANDBOX_DIR", str(tmp_path / "sandbox"))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    (tmp_path / "home").mkdir()
    import importlib
    import rice_sandbox
    import rice_files
    import rice_agent
    importlib.reload(rice_sandbox)
    importlib.reload(rice_files)
    a = importlib.reload(rice_agent)
    a.CHAT = "c1"
    return a, tmp_path


def test_link_swapped_in_after_the_decision_doesnt_write_to_the_host(agent):
    a, tmp = agent
    ws = a.rice_sandbox.workspace("c1")
    (ws / "d").mkdir()
    host = tmp / "home" / "victim"
    host.mkdir()
    args = {"path": "d/file.txt", "content": "pwned"}
    assert a._write_request(args) is None          # decided: sandbox, no approval
    (ws / "d").rmdir()
    os.symlink(host, ws / "d")                     # the container swaps the folder for a link
    with pytest.raises(a.ToolError):
        a.tool_write(args)
    assert not (host / "file.txt").exists()


def test_relative_dotdot_cannot_leave_the_sandbox(agent):
    a, tmp = agent
    with pytest.raises(a.ToolError):
        a._classify({"path": "../../home/x"})


def test_work_prefix_maps_into_this_chat_only(agent):
    a, _ = agent
    full, inside, parts = a._classify({"path": "/work/c1/src/main.py"})
    assert inside and parts == ["src", "main.py"]
    full, inside, parts = a._classify({"path": "/work/other/x"})
    assert inside and parts == ["other", "x"]          # still inside this chat's folder, never another's


def test_home_path_is_a_host_write_that_needs_approval(agent):
    a, tmp = agent
    req = a._write_request({"path": "~/notes.md", "content": "x"})
    assert req and req[0] == "write"


def test_symlinked_file_in_sandbox_not_followed_on_write(agent):
    a, tmp = agent
    ws = a.rice_sandbox.workspace("c1")
    target = tmp / "home" / ".bashrc"
    target.write_text("original")
    os.symlink(target, ws / "rc")
    args = {"path": "rc", "content": "evil"}
    assert a._write_request(args) is None
    with pytest.raises(a.ToolError):
        a.tool_write(args)
    assert target.read_text() == "original"
