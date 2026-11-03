import json

from conftest import parse_events, started
from test_tools import answer, call, completion

CAPS = {"hermes3:8b": ["completion", "tools"]}
USER = {"messages": [{"role": "user", "content": "what window is this?"}]}
STEER = {"type": "turn.steer", "id": "s-1", "text": "also tell me the workspace"}


def test_steer_lands_after_a_tool_round(run_agent):
    events, fake = run_agent(USER, [[call("active_window"), {"done": True}], answer("kitty, workspace 2")],
                             caps=CAPS, stdin_lines=[STEER])
    steered = [e for e in events if e["type"] == "turn.steered"]
    assert steered == [{"type": "turn.steered", "id": "s-1", "text": "also tell me the workspace", "ts": steered[0]["ts"]}]
    sent = fake.requests[1]["messages"]
    assert sent[-2]["role"] == "tool"
    assert sent[-1] == {"role": "user", "content": "also tell me the workspace"}
    assert events[-1]["status"] == "completed"


def test_steer_cuts_streaming_text_and_the_model_answers_it(start_agent):
    slow = [{"message": {"content": f"word{i} "}} if i % 2 == 0 else {"_sleep": 0.05} for i in range(200)]
    script = [slow + [{"done": True}], answer("Sure: workspace 2.")]
    with start_agent(USER, script, CAPS) as (proc, fake):
        lines = []
        for line in proc.stdout:
            lines.append(line)
            if json.loads(line)["type"] == "item.delta":
                proc.stdin.write(json.dumps(STEER) + "\n")
                proc.stdin.flush()
                break
        out, _ = proc.communicate(timeout=20)
        events = parse_events("".join(lines) + out)
    first = started(events, "assistant_message")[0]
    partial = "".join(e["text"] for e in events if e["type"] == "item.delta" and e["id"] == first["id"])
    assert 0 < len(partial) < len("".join(f"word{i} " for i in range(0, 200, 2)))
    assert completion(events, first["id"])["status"] == "completed"
    assert [e["type"] for e in events].count("turn.steered") == 1
    sent = fake.requests[1]["messages"]
    assert sent[-2]["role"] == "assistant" and sent[-2]["content"].startswith("word0")
    assert sent[-1] == {"role": "user", "content": "also tell me the workspace"}
    assert events[-1]["status"] == "completed"
    answers = started(events, "assistant_message")
    assert len(answers) == 2
