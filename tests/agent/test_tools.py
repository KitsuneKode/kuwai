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
    assert {t["function"]["name"] for t in fake.requests[0]["tools"]} >= {"active_window", "web_search", "read", "edit", "grep"}
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
    events, _ = run_agent(USER, [[call("read", '{"path": "notes.txt"}'), {"done": True}], answer()],
                          caps=TOOLS_CAPS)
    tool = tool_items(events)[0]
    assert tool["input"] == {"path": "notes.txt"}


def test_tool_round_cap(run_agent):
    rounds = [[call("active_window", cid=f"c{i}"), {"done": True}] for i in range(11)]
    events, fake = run_agent(USER, rounds, caps=TOOLS_CAPS)
    assert len(tool_items(events)) == 10
    assert events[-1]["status"] == "max_tool_rounds"
    assert "tools" not in fake.requests[-1]


def test_read_refuses_secrets(run_agent, tmp_path):
    (tmp_path / ".ssh").mkdir()
    (tmp_path / ".ssh" / "id_ed25519").write_text("PRIVATE")
    events, _ = run_agent(USER, [[call("read", {"path": "~/.ssh/id_ed25519"}), {"done": True}], answer()],
                          caps=TOOLS_CAPS)
    done = completion(events, tool_items(events)[0]["id"])
    assert done["status"] == "failed" and "secrets" in done["output"] and "PRIVATE" not in done["output"]


def test_read_home_file_with_offset_note(run_agent, tmp_path):
    (tmp_path / "notes.txt").write_text("\n".join(f"line {i}" for i in range(1, 401)))
    events, _ = run_agent(USER, [[call("read", {"path": "~/notes.txt"}), {"done": True}], answer()],
                          caps=TOOLS_CAPS)
    done = completion(events, tool_items(events)[0]["id"])
    assert done["status"] == "completed" and done["output"].startswith("line 1\n")
    assert "[Showing lines 1-250 of 400. Use offset=251 to continue.]" in done["output"]


def test_missing_argument_is_explained(run_agent):
    events, fake = run_agent(USER, [[call("grep", {}), {"done": True}], answer()], caps=TOOLS_CAPS)
    out = fake.requests[1]["messages"][-1]["content"]
    assert out.startswith('Validation failed for tool "grep": missing pattern') and "Received arguments" in out


def test_cut_off_calls_are_not_run(run_agent, tmp_path):
    cut = [call("write", {"path": "a.txt", "content": "half"}), {"done": True, "done_reason": "length"}]
    events, fake = run_agent(USER, [cut, answer()], caps=TOOLS_CAPS)
    assert not tool_items(events) and not (tmp_path / "a.txt").exists()
    assert "hit the output limit" in fake.requests[1]["messages"][-1]["content"]


def test_clipboard_and_selection(run_agent):
    events, _ = run_agent(USER, [[call("read_clipboard"), {"done": True}],
                                 [call("read_selection", cid="c2"), {"done": True}], answer()], caps=TOOLS_CAPS)
    outs = [completion(events, t["id"])["output"] for t in tool_items(events)]
    assert outs == ["clipboard text", "selected text"]


def test_silent_finish_after_tools_gets_one_nudge(run_agent):
    silent = [{"message": {"thinking": "all done, I think"}}, {"done": True}]
    events, fake = run_agent(USER, [[call("active_window"), {"done": True}], silent, answer("It's kitty.")],
                             caps={"hermes3:8b": ["completion", "tools", "thinking"]})
    assert fake.requests[2]["messages"][-1]["content"] == "(Now answer my request from what you found.)"
    text = "".join(e["text"] for e in events if e["type"] == "item.delta")
    assert "It's kitty." in text and events[-1]["status"] == "completed"


def test_system_audit_is_read_only_and_needs_no_approval(run_agent):
    events, _ = run_agent(USER, [[call("system_audit"), {"done": True}], answer()], caps=TOOLS_CAPS)
    assert not [e for e in events if e["type"] == "request.opened"]
    out = completion(events, tool_items(events)[0]["id"])["output"]
    assert "## Ports reachable from the network" in out and "## Firewall services" in out


def test_broken_tool_call_is_retried_not_fatal(run_agent):
    broken = [{"error": "XML syntax error on line 3: element <function> closed by </parameter>"}]
    events, fake = run_agent(USER, [broken, answer("Fine now.")], caps=TOOLS_CAPS)
    assert events[-1]["status"] == "completed"
    assert "couldn't be read" in fake.requests[1]["messages"][-1]["content"]


def test_chat_mode_offers_no_changing_tools(run_agent):
    _, fake = run_agent({"mode": "chat", "messages": [{"role": "user", "content": "open firefox and edit ~/x"}]},
                        [answer()], caps=TOOLS_CAPS, env={"RICE_AGENT_TOOLS": ""})
    names = {t["function"]["name"] for t in fake.requests[0]["tools"]}
    assert not names & {"write", "edit", "run_command", "launch_app", "sandbox_run"}
    assert "Mode: chat." in fake.requests[0]["messages"][0]["content"]


def test_chat_mode_refuses_a_changing_tool_even_when_named(run_agent, tmp_path):
    script = [[call("write", {"path": "~/owned.txt", "content": "x"}), {"done": True}], answer()]
    events, fake = run_agent({"mode": "chat", "messages": [{"role": "user", "content": "hi"}]}, script, caps=TOOLS_CAPS)
    done = completion(events, tool_items(events)[0]["id"])
    assert done["status"] == "failed" and "Chat mode" in done["output"]
    assert not (tmp_path / "owned.txt").exists() and not [e for e in events if e["type"] == "request.opened"]


def test_plan_only_rounds_are_capped(run_agent):
    plan = [call("update_plan", {"steps": [{"step": "x", "status": "pending"}]}), {"done": True}]
    events, fake = run_agent(USER, [plan] * 30 + [answer()], caps=TOOLS_CAPS)
    assert len(fake.requests) <= 6 and events[-1]["status"] == "max_tool_rounds"
