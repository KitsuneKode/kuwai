"""Sandbox tools (no approval: they run in the container) and ask_user."""
from conftest import started
from test_approvals import of_type
from test_tools import answer, call, completion

USER = {"chat": "c42", "messages": [{"role": "user", "content": "do it"}]}
CAPS = {"hermes3:8b": ["completion", "tools"]}
ON = {"RICE_SANDBOX": "on"}


def names(req):
    return [t["function"]["name"] for t in req.get("tools", [])]


def test_sandbox_tools_hidden_when_off(run_agent):
    _, fake = run_agent(USER, [answer()], caps=CAPS)
    assert "sandbox_run" not in names(fake.requests[0]) and "ask_user" in names(fake.requests[0])
    assert "sandbox" not in fake.requests[0]["messages"][0]["content"]


def test_write_then_run_in_chat_folder(run_agent, tmp_path):
    script = [[call("sandbox_write", {"path": "hello.py", "content": "print(6*7)\n"}, cid="a"), {"done": True}],
              [call("sandbox_run", {"command": "python3 hello.py; pwd"}, cid="b"), {"done": True}],
              answer()]
    events, fake = run_agent(USER, script, caps=CAPS, env=ON)
    assert "sandbox_run" in names(fake.requests[0])
    assert not of_type(events, "request.opened")            # no approval
    write = started(events, "file_change")[0]
    assert write["title"] == "Writing hello.py"
    assert completion(events, write["id"])["output"] == "Wrote hello.py (1 lines)"
    run = started(events, "command_execution")[0]
    out = completion(events, run["id"])["output"]
    assert "42" in out and out.endswith("(exit 0)") and str(tmp_path / "sandbox" / "c42") in out
    assert (tmp_path / "sandbox" / "c42" / "hello.py").read_text() == "print(6*7)\n"


def test_write_refuses_escape(run_agent, tmp_path):
    events, _ = run_agent(USER, [[call("sandbox_write", {"path": "../../x", "content": "no"}), {"done": True}],
                                 answer()], caps=CAPS, env=ON)
    done = completion(events, started(events, "file_change")[0]["id"])
    assert done["status"] == "failed" and "outside" in done["output"]
    assert not (tmp_path / "x").exists()


def test_question_answer_goes_back(run_agent):
    q = {"question": "Which size?", "options": ["Small", "Large"]}
    events, fake = run_agent(USER, [[call("ask_user", q), {"done": True}], answer()], caps=CAPS,
                             stdin_lines=[{"type": "request.resolve", "id": "q1", "decision": "accept",
                                           "answer": "Large"}])
    item = started(events, "user_input")[0]
    opened = of_type(events, "request.opened")[0]
    assert opened["kind"] == "question" and opened["summary"] == "Which size?"
    assert opened["options"] == ["Small", "Large"] and opened["itemId"] == item["id"]
    assert of_type(events, "request.resolved")[0]["answer"] == "Large"
    assert completion(events, item["id"])["output"] == "Large"
    assert fake.requests[1]["messages"][-1]["content"] == "The user answered: Large"


def test_question_skipped(run_agent):
    events, fake = run_agent(USER, [[call("ask_user", {"question": "Which?"}), {"done": True}], answer()], caps=CAPS,
                             stdin_lines=[{"type": "request.resolve", "id": "q1", "decision": "decline"}])
    done = completion(events, started(events, "user_input")[0]["id"])
    assert done["status"] == "declined"
    assert "best judgement" in fake.requests[1]["messages"][-1]["content"]
