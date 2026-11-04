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
    assert "isolated Linux sandbox" not in fake.requests[0]["messages"][0]["content"]


def test_write_then_run_in_chat_folder(run_agent, tmp_path):
    script = [[call("write", {"path": "hello.py", "content": "print(6*7)\n"}, cid="a"), {"done": True}],
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


def test_write_outside_sandbox_asks_and_decline_keeps_file(run_agent, tmp_path):
    target = tmp_path / "keep.txt"
    target.write_text("original\n")
    events, _ = run_agent(USER, [[call("write", {"path": "~/keep.txt", "content": "new\n"}), {"done": True}], answer()],
                          caps=CAPS, stdin_lines=[{"type": "request.resolve", "id": "q1", "decision": "decline"}])
    opened = of_type(events, "request.opened")[0]
    assert opened["kind"] == "write" and opened["summary"] == "Overwrite ~/keep.txt"
    assert "-original" in opened["detail"] and "+new" in opened["detail"]
    assert target.read_text() == "original\n"


def test_edit_in_sandbox_no_approval_and_fuzzy_match(run_agent, tmp_path):
    ws = tmp_path / "sandbox" / "c42"
    ws.mkdir(parents=True)
    (ws / "app.py").write_text("def hi():   \n    return 'hi'\n")
    edits = {"path": "app.py", "edits": [{"oldText": "def hi():\n    return 'hi'", "newText": "def hi():\n    return 'hello'"}]}
    events, _ = run_agent(USER, [[call("edit", edits), {"done": True}], answer()], caps=CAPS)
    assert not of_type(events, "request.opened")
    done = completion(events, started(events, "file_change")[0]["id"])
    assert done["output"] == "Successfully replaced 1 block(s) in app.py."
    assert "return 'hello'" in (ws / "app.py").read_text()


def test_edit_not_unique_is_explained(run_agent, tmp_path):
    ws = tmp_path / "sandbox" / "c42"
    ws.mkdir(parents=True)
    (ws / "x.txt").write_text("a\na\n")
    events, _ = run_agent(USER, [[call("edit", {"path": "x.txt", "edits": [{"oldText": "a", "newText": "b"}]}),
                                  {"done": True}], answer()], caps=CAPS)
    done = completion(events, started(events, "file_change")[0]["id"])
    assert done["status"] == "failed" and "Found 2 occurrences" in done["output"]


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


def test_sandbox_output_drops_ansi(run_agent):
    script = [[call("sandbox_run", {"command": "printf '\\033[31mred\\033[0m ok'"}), {"done": True}], answer()]
    events, _ = run_agent(USER, script, caps=CAPS, env=ON)
    out = completion(events, started(events, "command_execution")[0]["id"])["output"]
    assert out.startswith("red ok") and "\x1b" not in out


def test_attached_text_file_goes_inline_and_into_sandbox(run_agent, tmp_path):
    f = tmp_path / "notes.txt"
    f.write_text("budget: 35000\nneeds: 16GB RAM\n")
    req = {"chat": "c42", "messages": [{"role": "user", "content": "what's my budget?",
                                        "context": {"files": [{"path": str(f)}]}}]}
    _, fake = run_agent(req, [answer()], caps=CAPS)
    sent = fake.requests[0]["messages"][-1]["content"]
    assert '<file name="notes.txt">' in sent and "budget: 35000" in sent and sent.endswith("what's my budget?")
    assert (tmp_path / "sandbox" / "c42" / "files" / "notes.txt").read_text().startswith("budget")


def test_big_file_is_cut_to_the_window(run_agent, tmp_path):
    f = tmp_path / "big.log"
    f.write_text("x" * 50_000)
    req = {"chat": "c42", "options": {"num_ctx": 4096},
           "messages": [{"role": "user", "content": "sum up", "context": {"files": [{"path": str(f)}]}}]}
    _, fake = run_agent(req, [answer()], caps=CAPS)
    sent = fake.requests[0]["messages"][-1]["content"]
    assert len(sent) < 7000 and "cut: 50,000 characters in all" in sent and "files/big.log" in sent


def test_update_plan_cleans_steps(run_agent):
    plan = {"steps": [{"step": "Write it", "status": "completed"}, "Test it", {"step": "x", "status": "weird"}]}
    events, fake = run_agent(USER, [[call("update_plan", plan), {"done": True}], answer()], caps=CAPS)
    item = started(events, "todo_list")[0]
    assert item["input"]["steps"] == [{"step": "Write it", "status": "completed"}, {"step": "Test it", "status": "pending"},
                                      {"step": "x", "status": "pending"}]
    assert fake.requests[1]["messages"][-1]["content"].startswith("Plan updated (1 of 3 done)")


def test_context_profile_memory_and_instructions(run_agent, tmp_path):
    cfg = tmp_path / "config" / "rice" / "assistant"
    cfg.mkdir(parents=True)
    (cfg / "AGENTS.md").write_text("Answer in British English.")
    events, fake = run_agent(USER, [[call("remember", {"fact": "Prefers Rust over Go"}), {"done": True}], answer()],
                             caps=CAPS)
    system = fake.requests[0]["messages"][0]["content"]
    assert "About this computer:" in system and "- OS:" in system
    assert "Answer in British English." in system
    assert "Prefers Rust over Go" in (cfg / "memory.md").read_text()
    _, fake2 = run_agent(USER, [answer()], caps=CAPS)
    assert "Prefers Rust over Go" in fake2.requests[0]["messages"][0]["content"]


def test_background_job_and_check(run_agent, tmp_path):
    ws = tmp_path / "sandbox" / "c42" / ".jobs"
    script = [[call("sandbox_run", {"command": "echo hi; sleep 0.1", "background": True}), {"done": True}], answer()]
    events, fake = run_agent(USER, script, caps=CAPS, env=ON)
    out = completion(events, started(events, "command_execution")[0]["id"])["output"]
    assert "hi" in out
    assert list(ws.glob("*.cmd"))
