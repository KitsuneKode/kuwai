"""Tool routing: each request offers the tools the recent messages point to."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "bin"))
import rice_agent as a  # noqa: E402


def route(*texts):
    return a.route_tools([{"role": "user", "content": t} for t in texts])


def test_plain_chat_gets_only_the_web():
    assert route("hi, how are you?") == {"web_search", "web_fetch", "ask_user"}


def test_prices_get_shopping():
    assert "shop_search" in route("best laptop under ₹60,000")


def test_code_gets_the_sandbox_and_files_get_file_tools():
    r = route("write a python script that sorts a csv")
    assert {"sandbox_run", "write", "edit"} <= r
    assert {"read", "grep", "find"} <= route("what does ~/Projects/rice/shell/shell.qml load?")


def test_desktop_and_actions():
    assert "active_window" in route("what app am I using?")
    assert {"launch_app", "run_command"} <= route("open firefox")


def test_follow_up_keeps_the_previous_group():
    assert "shop_search" in route("find me a phone under 20000", "and the cheapest one?")


def test_all_switch():
    import os
    os.environ["RICE_AGENT_TOOLS"] = "all"
    try:
        assert route("hi") == set(a.TOOLS)
    finally:
        del os.environ["RICE_AGENT_TOOLS"]
