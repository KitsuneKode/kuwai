"""bin/kuwai-t3: T3 Code's threads, classified the way T3's own sidebar does.

A small statev2.sqlite with one thread per rule; the island must count only
real work (not silent or queued runs, not hidden threads) and put requests
first.
"""
import json
import os
import sqlite3
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin" / "kuwai-t3"

SCHEMA = """
create table orchestration_v2_projection_threads (thread_id text primary key, title text, payload_json text,
  deleted_at text, archived_at text, project_id text);
create table orchestration_v2_projection_runs (run_id text primary key, thread_id text, status text, provider text,
  requested_at text, completed_at text, ordinal integer, payload_json text);
create table orchestration_v2_projection_runtime_requests (thread_id text, status text, kind text);
create table orchestration_v2_projection_turn_items (thread_id text, run_id text, type text, status text,
  payload_json text, updated_at text);
create table projection_projects (project_id text, title text);
"""

NOW = "2099-01-01T00:00:00.000Z"      # every "recent" time below is in the future: within 3 days of now
LATER = "2099-01-02T00:00:00.000Z"


def thread(db, tid, title, **payload):
    db.execute("insert into orchestration_v2_projection_threads values (?,?,?,?,?,?)",
               (tid, title, json.dumps(payload), None, None, None))


def run(db, rid, tid, status, completed=None, ordinal=1, **payload):
    db.execute("insert into orchestration_v2_projection_runs values (?,?,?,?,?,?,?,?)",
               (rid, tid, status, "codex", NOW, completed, ordinal, json.dumps(payload)))


def build(tmp_path):
    db = sqlite3.connect(tmp_path / "statev2.sqlite")
    db.executescript(SCHEMA)
    thread(db, "t-work", "Working")
    run(db, "r-work", "t-work", "running")
    thread(db, "t-silent", "Only a silent run")
    run(db, "r-silent", "t-silent", "running", silent=1)
    thread(db, "t-queued", "Only queued")
    run(db, "r-queued", "t-queued", "queued")
    thread(db, "t-deleg", "Delegated child", delegatedFrom="t-work")
    run(db, "r-deleg", "t-deleg", "running")
    thread(db, "t-settled", "Settled", settledAt=NOW)
    run(db, "r-settled", "t-settled", "running")
    thread(db, "t-ask", "Needs approval")
    run(db, "r-ask", "t-ask", "running")
    db.execute("insert into orchestration_v2_projection_runtime_requests values ('t-ask','pending','command')")
    thread(db, "t-wait", "Waits on a child")
    run(db, "r-wait", "t-wait", "running")
    db.execute("insert into orchestration_v2_projection_turn_items values (?,?,?,?,?,?)",
               ("t-wait", "r-wait", "dynamic_tool", "running", json.dumps({"toolName": "t3_thread_wait"}), NOW))
    thread(db, "t-done", "Done, not seen", lastVisitedAt=NOW)
    run(db, "r-done", "t-done", "completed", completed=LATER)
    thread(db, "t-seen", "Done and seen", lastVisitedAt=LATER)
    run(db, "r-seen", "t-seen", "completed", completed=NOW)
    thread(db, "t-limit", "Hit a limit")
    run(db, "r-limit", "t-limit", "failed", completed=LATER)
    db.execute("insert into orchestration_v2_projection_turn_items values (?,?,?,?,?,?)",
               ("t-limit", "r-limit", "error", "failed", json.dumps({"failure": {"class": "usage_limit"}}), LATER))
    db.commit()
    db.close()
    (tmp_path / "server-runtime.json").write_text(json.dumps({"pid": os.getpid()}))
    (tmp_path / "environment-id").write_text("env-1")


def read(tmp_path):
    out = subprocess.run([str(BIN)], env={**os.environ, "T3_USERDATA": str(tmp_path)},
                         capture_output=True, text=True, timeout=10).stdout
    return json.loads(out)


def test_only_real_work_counts(tmp_path):
    build(tmp_path)
    d = read(tmp_path)
    assert d["alive"] is True and d["env"] == "env-1"
    titles = {i["title"]: i for i in d["items"]}
    # silent, queued, delegated and settled threads are not listed at all
    for hidden in ("Only a silent run", "Only queued", "Delegated child", "Settled", "Done and seen"):
        assert hidden not in titles, hidden
    assert d["running"] == 1                       # Working; the one waiting on a child is not work
    assert titles["Waits on a child"]["blocked"] is True
    assert d["waiting"] == 1 and titles["Needs approval"]["status"] == "waiting"
    assert d["items"][0]["title"] == "Needs approval"       # attention first
    assert titles["Done, not seen"]["status"] == "completed"
    assert titles["Hit a limit"]["status"] == "failed" and titles["Hit a limit"]["limited"] is True
    assert d["finished"] == 2


def test_not_running_without_the_server(tmp_path):
    build(tmp_path)
    (tmp_path / "server-runtime.json").write_text(json.dumps({"pid": 999999999}))
    assert read(tmp_path)["alive"] is False
