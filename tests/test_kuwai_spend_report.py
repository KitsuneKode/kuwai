"""bin/kuwai-spend-report: the Usage panel's Spend and Tokens.

Without a token, or with T3 Code closed, it reads the totals kuwai-spend keeps
from this machine's logs and says why, each model's share of the day's money.
"""
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-spend-report"


def run(home, period):
    runner = shutil.which("bun") or shutil.which("node")
    env = {"PATH": os.environ.get("PATH", ""), "HOME": str(home), "XDG_STATE_HOME": str(home / "state"),
           "XDG_CACHE_HOME": str(home / "cache"), "T3CODE_HOME": str(home / "t3"), "TZ": "UTC",
           "KUWAI_NOW_MS": str(int(time.mktime((2026, 11, 22, 12, 0, 0, 0, 0, 0)) * 1000))}
    out = subprocess.run([runner, str(BIN), period], env=env, capture_output=True, text=True, timeout=60, check=True)
    return json.loads(out.stdout)


def test_without_a_token_it_reads_the_local_logs(tmp_path):
    cache = tmp_path / "cache" / "kuwai"
    cache.mkdir(parents=True)
    (cache / "spend.json").write_text(json.dumps({"version": 1, "files": {}, "days": {
        "claude": {"2026-11-22": {"tokens": 300, "cost": 3.0, "unpriced": 0, "models": {"opus": 200, "sonnet": 100}},
                   "2026-10-01": {"tokens": 999, "cost": 9.0, "unpriced": 0, "models": {"opus": 999}}},
        "codex": {"2026-11-20": {"tokens": 50, "cost": 0, "unpriced": 50, "models": {"gpt": 50}}}}}))
    d = run(tmp_path, "7d")
    assert d["source"] == "local" and d["why"] == "token" and d["period"] == "7d"
    by = {(b["provider"], b["model"]): b for b in d["buckets"]}
    assert set(by) == {("claude", "opus"), ("claude", "sonnet"), ("codex", "gpt")}
    assert abs(by[("claude", "opus")]["cost"] - 2.0) < 1e-9
    assert by[("codex", "gpt")]["priced"] is False


def test_nothing_recorded_is_an_empty_report(tmp_path):
    d = run(tmp_path, "24h")
    assert d["source"] == "local" and d["buckets"] == [] and d["period"] == "24h"


def test_an_unknown_period_is_a_week(tmp_path):
    assert run(tmp_path, "nonsense")["period"] == "7d"


def t3_fixture(home):
    """A statev2.sqlite in T3 Code's shape (v0.1.12-nightly.20261125), synthetic: three Claude turns on two instances,
    one Cursor turn on a model without a price, one turn with no usage record, one recorded in part."""
    import sqlite3
    db = home / "t3" / "userdata" / "statev2.sqlite"
    db.parent.mkdir(parents=True)
    c = sqlite3.connect(db)
    c.executescript("""
    create table orchestration_v2_projection_runs (run_id text primary key, thread_id text, ordinal integer, provider text,
      provider_thread_id text, status text, requested_at text, completed_at text, payload_json text, provider_instance_id text);
    create table orchestration_v2_projection_provider_threads (provider_thread_id text primary key, thread_id text, owner_node_id text,
      provider text, provider_session_id text, status text, first_run_ordinal integer, last_run_ordinal integer, updated_at text,
      payload_json text, driver text, provider_instance_id text);
    create table orchestration_v2_projection_provider_turns (provider_turn_id text primary key, thread_id text, provider_thread_id text,
      node_id text, run_attempt_id text, ordinal integer, status text, started_at text, completed_at text, payload_json text);
    """)
    def thread(pt, th, inst, driver, native):
        c.execute("insert into orchestration_v2_projection_provider_threads values (?,?,?,?,?,?,?,?,?,?,?,?)",
                  (pt, th, "n", inst, None, "idle", 1, 1, "2026-11-22T10:00:00.000Z",
                   json.dumps({"nativeThreadRef": {"driver": driver, "nativeId": native}}), driver, inst))
    thread("pt1", "th1", "claudeAgent_2", "claudeAgent", "0a1b2c3d-0000-4000-8000-000000000001")
    thread("pt2", "th2", "claudeAgent", "claudeAgent", "0a1b2c3d-0000-4000-8000-000000000002")
    thread("pt3", "th3", "cursor_2", "cursor", "calm-otter")
    c.execute("insert into orchestration_v2_projection_runs values (?,?,?,?,?,?,?,?,?,?)",
              ("r3", "th3", 1, "cursor_2", "pt3", "completed", "2026-11-22T09:00:00.000Z", None,
               json.dumps({"activeAttemptId": "att3", "modelSelection": {"model": "composer-2.5"}}), "cursor_2"))
    def turn(tid, pt, th, at, usage, model=None, attempt=None):
        p = {"turnTokenUsage": usage} if usage else {}
        if model:
            p["model"] = model
        c.execute("insert into orchestration_v2_projection_provider_turns values (?,?,?,?,?,?,?,?,?,?)",
                  (tid, th, pt, "n", attempt, int(tid[1:]), "completed", at, at, json.dumps(p)))
    u = lambda inp, cached, out, status="complete": {"usageStatus": status, "inputTokens": inp, "cachedInputTokens": cached,
                                                      "cacheCreationTokens": 0, "outputTokens": out, "models": ["claude-opus-5-5"]}
    turn("t1", "pt1", "th1", "2026-11-22T10:00:00.000Z", u(1_000_000, 900_000, 10_000), "claude-opus-5-5")
    turn("t2", "pt1", "th1", "2026-11-21T10:00:00.000Z", u(200_000, 0, 1_000, "partial"), "claude-opus-5-5")
    turn("t3", "pt2", "th2", "2026-11-22T11:00:00.000Z", u(100_000, 0, 1_000), "claude-opus-5-5")
    turn("t4", "pt3", "th3", "2026-11-22T09:00:00.000Z", {"usageStatus": "complete", "inputTokens": 5_000, "cachedInputTokens": 0,
                                                       "cacheCreationTokens": 0, "outputTokens": 500}, attempt="att3")
    turn("t5", "pt3", "th3", "2026-11-22T09:30:00.000Z", None)
    turn("t6", "pt1", "th1", "2026-10-01T10:00:00.000Z", u(9, 0, 9), "claude-opus-5-5")
    c.commit()
    c.close()


def test_t3s_own_turn_records_without_a_token(tmp_path):
    t3_fixture(tmp_path)
    cache = tmp_path / "cache" / "kuwai"
    cache.mkdir(parents=True)
    day = {"tokens": 40, "cost": 0.4, "unpriced": 0, "models": {"claude-opus-5-5": 40}}
    (cache / "spend.json").write_text(json.dumps({"version": 2, "days": {}, "files": {
        "/a.jsonl": {"provider": "claude", "sid": "0a1b2c3d-0000-4000-8000-000000000001", "days": {"2026-11-22": dict(day, tokens=1_000_000)}},
        "/b.jsonl": {"provider": "claude", "sid": "0a1b2c3d-0000-4000-8000-0000000000ff", "days": {"2026-11-22": day}},
    }}))
    d = run(tmp_path, "7d")
    assert d["source"] == "t3-db" and d["why"] == "token"
    assert d["coverage"] == {"complete": 3, "partial": 1, "unavailable": 1}
    assert d["sessions"] == {"claude": 3, "cursor": 1}
    assert sorted(d["instances"]["claude"]) == ["claudeAgent", "claudeAgent_2"]
    by = {}
    for b in d["buckets"]:
        by.setdefault((b["provider"], b["model"], b.get("local", False)), []).append(b)
    assert sum(b["tokens"] for b in by[("claude", "claude-opus-5-5", False)]) == 1_010_000 + 201_000 + 101_000
    cursor = by[("cursor", "composer-2.5", False)][0]
    assert cursor["priced"] is False and cursor["cost"] == 0 and cursor["tokens"] == 5_500
    assert [b["tokens"] for b in by[("claude", "claude-opus-5-5", True)]] == [40], "the log T3 ran is not counted twice"
    assert d["outside"] == 40
    assert all(b["day"] >= "2026-11-16" for b in d["buckets"])


def test_t3s_turn_records_by_hour(tmp_path):
    t3_fixture(tmp_path)
    d = run(tmp_path, "24h")
    assert d["source"] == "t3-db"
    hours = {b["hour"] for b in d["buckets"]}
    assert {"2026-11-22T10:00", "2026-11-22T11:00", "2026-11-22T09:00"} <= hours
    assert all(h.startswith("2026-11-2") for h in hours), "nothing from before the last day"
    assert d["outside"] == 0
