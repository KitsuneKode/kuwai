from conftest import started, types

USER = {"messages": [{"role": "user", "content": "what window is focused?"}]}
TOOLS_CAPS = {"hermes3:8b": ["completion", "tools"]}


def call(name, args=None, cid="call_1"):
    return {"message": {"tool_calls": [{"id": cid, "function": {"index": 0, "name": name, "arguments": args or {}}}]}}


def answer(text="Done."):
    return [{"message": {"content": text}}, {"done": True}]


def tool_items(events):
    return [e for e in events if e["type"] == "item.started" and e["itemType"] not in ("reasoning", "assistant_message")]


def completion(events, item_id):
    return next(e for e in events if e["type"] == "item.completed" and e["id"] == item_id)


def test_tool_call_runs_and_answers(run_agent):
    events, fake = run_agent(USER, [[call("active_window"), {"done": True}], answer("You are in kitty.")],
                             caps=TOOLS_CAPS)
    tool = started(events, "dynamic_tool_call")[0]
    assert tool["title"] == "Active window"
    assert tool["input"] == {}
    done = completion(events, tool["id"])
    assert done["status"] == "completed"
    assert "stub-title" in done["output"]
    assert events.index(started(events, "assistant_message")[0]) > events.index(done)
    assert {t["function"]["name"] for t in fake.requests[0]["tools"]} >= {"active_window", "web_search", "read_file"}
    sent = fake.requests[1]["messages"]
    assert sent[-2]["role"] == "assistant" and sent[-2]["tool_calls"][0]["function"]["name"] == "active_window"
    assert sent[-1]["role"] == "tool" and sent[-1]["tool_name"] == "active_window"
    assert events[-1]["status"] == "completed"


def test_no_tools_for_incapable_model(run_agent):
    events, fake = run_agent({**USER, "model": "minicpm-v:latest"}, [answer()],
                             caps={"minicpm-v:latest": ["completion", "vision"]})
    assert "tools" not in fake.requests[0]
    assert events[-1]["status"] == "completed"


def test_unknown_tool_fails_item_not_turn(run_agent):
    events, fake = run_agent(USER, [[call("rm_everything"), {"done": True}], answer()], caps=TOOLS_CAPS)
    tool = tool_items(events)[0]
    done = completion(events, tool["id"])
    assert done["status"] == "failed"
    assert done["output"].startswith("Unknown tool")
    assert fake.requests[1]["messages"][-1]["content"].startswith("Unknown tool")
    assert events[-1]["status"] == "completed"


def test_string_arguments_are_parsed(run_agent):
    events, _ = run_agent(USER, [[call("read_file", '{"path": "notes.txt"}'), {"done": True}], answer()],
                          caps=TOOLS_CAPS)
    tool = tool_items(events)[0]
    assert tool["input"] == {"path": "notes.txt"}


def test_tool_round_cap(run_agent):
    rounds = [[call("active_window", cid=f"c{i}"), {"done": True}] for i in range(11)]
    events, fake = run_agent(USER, rounds, caps=TOOLS_CAPS)
    assert len(tool_items(events)) == 10
    assert events[-1]["status"] == "max_tool_rounds"
    assert "tools" not in fake.requests[-1]


def test_read_file_refuses_outside_home(run_agent):
    events, _ = run_agent(USER, [[call("read_file", {"path": "/etc/shadow"}), {"done": True}], answer()],
                          caps=TOOLS_CAPS)
    done = completion(events, tool_items(events)[0]["id"])
    assert done["status"] == "failed"
    assert "home" in done["output"].lower()


def test_read_file_reads_inside_home(run_agent, tmp_path):
    (tmp_path / "notes.txt").write_text("remember the milk")
    events, _ = run_agent(USER, [[call("read_file", {"path": "~/notes.txt"}), {"done": True}], answer()],
                          caps=TOOLS_CAPS)
    done = completion(events, tool_items(events)[0]["id"])
    assert done["status"] == "completed"
    assert "remember the milk" in done["output"]


def test_clipboard_and_selection(run_agent):
    events, _ = run_agent(USER, [[call("read_clipboard"), {"done": True}],
                                 [call("read_selection", cid="c2"), {"done": True}], answer()], caps=TOOLS_CAPS)
    outs = [completion(events, t["id"])["output"] for t in tool_items(events)]
    assert outs == ["clipboard text", "selected text"]
