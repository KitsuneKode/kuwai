from conftest import item_text, started, types

USER = {"messages": [{"role": "user", "content": "hi"}]}


def test_plain_answer_streams_one_message(run_agent):
    events, fake = run_agent(USER, [[
        {"message": {"content": "Hel"}},
        {"message": {"content": "lo"}},
        {"done": True, "eval_count": 20, "eval_duration": 1e9, "prompt_eval_count": 232},
    ]])
    assert types(events) == [
        "turn.started", "turn.phase", "item.started", "item.delta", "item.delta", "item.completed", "turn.completed",
    ]
    msg = started(events, "assistant_message")[0]
    assert item_text(events, msg["id"]) == "Hello"
    done = events[-1]
    assert done["status"] == "completed"
    assert done["stats"]["tokensPerSec"] == 20.0
    assert done["stats"]["promptEvalCount"] == 232
    assert done["stats"]["numCtx"] == 4096
    assert fake.requests[0]["messages"][0]["role"] == "system"


def test_native_thinking_becomes_reasoning_item(run_agent):
    events, fake = run_agent(USER, [[
        {"message": {"thinking": "let me "}},
        {"message": {"thinking": "think"}},
        {"message": {"content": "Answer"}},
        {"done": True},
    ]], caps={"hermes3:8b": ["completion", "tools", "thinking"]})
    r = started(events, "reasoning")[0]
    m = started(events, "assistant_message")[0]
    assert item_text(events, r["id"]) == "let me think"
    assert item_text(events, m["id"]) == "Answer"
    completed_r = next(i for i, e in enumerate(events) if e["type"] == "item.completed" and e["id"] == r["id"])
    started_m = events.index(m)
    assert completed_r < started_m
    assert fake.requests[0]["think"] is True


def test_think_tags_fallback(run_agent):
    events, _ = run_agent(USER, [[
        {"message": {"content": "<thi"}},
        {"message": {"content": "nk>a</th"}},
        {"message": {"content": "ink>b"}},
        {"done": True},
    ]])
    r = started(events, "reasoning")[0]
    m = started(events, "assistant_message")[0]
    assert item_text(events, r["id"]) == "a"
    assert item_text(events, m["id"]) == "b"


def test_ollama_down_fails_turn(run_agent):
    events, _ = run_agent(USER, [], host="http://127.0.0.1:9")
    assert types(events) == ["turn.started", "turn.phase", "turn.completed"]
    assert events[-1]["status"] == "failed"
    assert events[-1]["error"]


def test_output_is_capped_by_default(run_agent):
    _, fake = run_agent(USER, [[{"message": {"content": "hi"}}, {"done": True}]])
    assert fake.requests[0]["options"]["num_predict"] == 2048


def test_repetition_stops_the_turn(run_agent):
    loop = [{"message": {"content": "The island shows the clock. "}} for _ in range(300)]
    events, _ = run_agent(USER, [loop + [{"done": True}]])
    text = "".join(e["text"] for e in events if e["type"] == "item.delta")
    assert len(text) < 300 * 28
    assert events[-1]["type"] == "turn.completed"
    assert events[-1]["status"] == "repeating"


def test_phase_loading_when_model_is_cold(run_agent):
    events, _ = run_agent(USER, [[{"message": {"content": "hi"}}, {"done": True}]])
    phases = [e["phase"] for e in events if e["type"] == "turn.phase"]
    assert phases[0] == "loading"
    first_item = next(i for i, e in enumerate(events) if e["type"] == "item.started")
    assert events.index(next(e for e in events if e["type"] == "turn.phase")) < first_item


def test_phase_waiting_when_model_is_loaded(run_agent, monkeypatch):
    import fake_ollama
    orig = fake_ollama.FakeOllama.__init__

    def warm(self, *a, **k):
        orig(self, *a, **k)
        self.loaded = ["hermes3:8b"]
    monkeypatch.setattr(fake_ollama.FakeOllama, "__init__", warm)
    events, _ = run_agent(USER, [[{"message": {"content": "hi"}}, {"done": True}]])
    assert [e["phase"] for e in events if e["type"] == "turn.phase"][0] == "waiting"
