from conftest import started
from test_tools import answer, completion

CAPS = {"hermes3:8b": ["completion", "tools"]}


def convo(n_exchanges, last="now?"):
    msgs = []
    for i in range(n_exchanges):
        msgs += [{"role": "user", "content": f"q{i}"}, {"role": "assistant", "content": f"a{i}"}]
    return msgs + [{"role": "user", "content": last}]


def test_compaction_summarises_older_and_keeps_recent(run_agent):
    req = {"messages": convo(4), "compact": True}
    events, fake = run_agent(req, [[{"message": {"content": "- user likes Lua"}}, {"done": True}], answer()], caps=CAPS)
    summary_req, turn_req = fake.requests
    assert "tools" not in summary_req
    sent = "\n".join(m["content"] for m in summary_req["messages"])
    assert "q0" in sent and "a2" in sent and "now?" not in sent

    item = started(events, "context_compaction")[0]
    assert item["title"] == "Summarising earlier messages"
    assert item["input"] == {"kept": 3}
    assert completion(events, item["id"])["output"] == "- user likes Lua"

    msgs = turn_req["messages"]
    assert msgs[0]["role"] == "system"
    assert msgs[1]["role"] == "system" and "- user likes Lua" in msgs[1]["content"]
    assert [m["content"] for m in msgs[2:]] == ["q3", "a3", "now?"]
    assert events[-1]["status"] == "completed"


def test_existing_summary_is_prepended(run_agent):
    req = {"messages": convo(1), "summary": "- earlier: set up the island"}
    _, fake = run_agent(req, [answer()], caps=CAPS)
    msgs = fake.requests[0]["messages"]
    assert msgs[1]["role"] == "system" and "- earlier: set up the island" in msgs[1]["content"]
    assert [m["content"] for m in msgs[2:]] == ["q0", "a0", "now?"]


def test_compaction_folds_in_the_previous_summary(run_agent):
    req = {"messages": convo(3), "summary": "- OLD FACT", "compact": True}
    _, fake = run_agent(req, [[{"message": {"content": "- merged"}}, {"done": True}], answer()], caps=CAPS)
    assert "- OLD FACT" in "\n".join(m["content"] for m in fake.requests[0]["messages"])
    assert "- OLD FACT" not in "\n".join(m["content"] for m in fake.requests[1]["messages"])


def test_compaction_skipped_when_nothing_to_fold(run_agent):
    req = {"messages": convo(1), "compact": True}
    events, fake = run_agent(req, [answer()], caps=CAPS)
    assert len(fake.requests) == 1
    assert started(events, "context_compaction") == []


def test_one_huge_message_cannot_crowd_out_the_rest(run_agent):
    msgs = [{"role": "user", "content": "My editor is Neovim."},
            {"role": "assistant", "content": "loop " * 10000},
            {"role": "user", "content": "I prefer Lua."},
            {"role": "assistant", "content": "Noted."}] + convo(1)
    req = {"messages": msgs, "summary": "- name: Kitsune", "compact": True}
    _, fake = run_agent(req, [[{"message": {"content": "- s"}}, {"done": True}], answer()], caps=CAPS)
    sent = fake.requests[0]["messages"][-1]["content"]
    assert "Neovim" in sent and "I prefer Lua." in sent and "Noted." in sent and "- name: Kitsune" in sent
    assert len(sent) < 6000
    assert "every point" in fake.requests[0]["messages"][0]["content"]
