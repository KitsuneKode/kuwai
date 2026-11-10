"""Files the container can write never steer host-side reads or writes (synthetic files, no Docker)."""
import os
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
sys.path.insert(0, str(BIN))
import rice_sandbox as sb  # noqa: E402

JID = "jabc123"


@pytest.fixture
def env(tmp_path, monkeypatch):
    root = tmp_path / "sandbox"
    host = tmp_path / "host"
    host.mkdir()
    secret = host / "secret.txt"
    secret.write_text("HOST SECRET\n")
    monkeypatch.setenv("RICE_SANDBOX_DIR", str(root))
    monkeypatch.setattr(sb, "ensure", lambda *a, **k: "rice-sandbox-test")
    monkeypatch.setattr(sb, "_docker", lambda *a, **k: None)
    jobs = sb.workspace("c1") / ".jobs"
    jobs.mkdir()
    (jobs / f"{JID}.cmd").write_text("sleep 1")
    return root, jobs, secret


def test_plain_job_reads_and_stops(env):
    _, jobs, _ = env
    (jobs / f"{JID}.log").write_text("hello\n")
    assert sb.job_state("c1", JID) == ("running", None, "hello\n", "sleep 1")
    sb.stop_job("c1", JID)
    assert sb.job_state("c1", JID)[:2] == ("done", 143)
    assert sb.finished_unnotified() == [{"chat": "c1", "id": JID, "command": "sleep 1", "exit": "143"}]
    assert sb.finished_unnotified() == []


def test_log_link_is_not_followed(env):
    _, jobs, secret = env
    (jobs / f"{JID}.log").symlink_to(secret)
    with pytest.raises(sb.SandboxError):
        sb.job_state("c1", JID)


def test_stop_does_not_write_through_a_status_link(env):
    _, jobs, secret = env
    (jobs / f"{JID}.status").symlink_to(secret)
    with pytest.raises(sb.SandboxError):
        sb.stop_job("c1", JID)
    assert secret.read_text() == "HOST SECRET\n"


def test_jobs_folder_link_is_refused(env):
    root, jobs, secret = env
    for f in jobs.iterdir():
        f.unlink()
    jobs.rmdir()
    jobs.symlink_to(secret.parent)
    (secret.parent / f"{JID}.cmd").write_text("x")
    (secret.parent / f"{JID}.status").write_text("0")
    with pytest.raises(sb.SandboxError):
        sb.job_state("c1", JID)
    assert sb.finished_unnotified() == []
    assert not (secret.parent / f"{JID}.notified").exists()


def test_notified_mark_does_not_create_through_a_dangling_link(env):
    _, jobs, secret = env
    (jobs / f"{JID}.status").write_text("0")
    target = secret.parent / "planted"
    (jobs / f"{JID}.notified.tmp").write_text("")  # unrelated noise
    (jobs / f"{JID}.notified").symlink_to(target)
    sb.finished_unnotified()
    assert not target.exists()


def test_hard_link_and_fifo_are_refused(env):
    _, jobs, _ = env
    other = jobs / "other"
    other.write_text("inside")
    os.link(other, jobs / f"{JID}.log")
    with pytest.raises(sb.SandboxError):
        sb.job_state("c1", JID)
    (jobs / f"{JID}.log").unlink()
    os.mkfifo(jobs / f"{JID}.log")
    with pytest.raises(sb.SandboxError):     # and doesn't hang on the FIFO
        sb.job_state("c1", JID)


@pytest.mark.parametrize("jid", ["../../host/secret", "j12", "jabc123/../x", "", "JABC123"])
def test_job_ids_are_validated(env, jid):
    with pytest.raises(sb.SandboxError):
        sb.job_state("c1", jid)
    with pytest.raises(sb.SandboxError):
        sb.stop_job("c1", jid)


@pytest.mark.parametrize("chat,slug", [("..", "scratch"), (".", "scratch"), (".home", "home"),
                                       ("a/../b", "a..b"), ("c1", "c1")])
def test_chat_slugs_stay_inside(chat, slug):
    assert sb.chat_slug(chat) == slug


def test_chat_folder_replaced_by_link_is_refused(env):
    root, _, secret = env
    (root / "c2").symlink_to(secret.parent)
    with pytest.raises(sb.SandboxError):
        sb.workspace("c2")


def test_attachment_copy_does_not_follow_a_link(env, tmp_path):
    root, _, secret = env
    files = root / "c1" / "files"
    files.mkdir()
    (files / "notes.txt").symlink_to(secret)
    src = tmp_path / "notes.txt"
    src.write_text("attachment")
    with pytest.raises(sb.SandboxError):
        sb.copy_in("c1", ["files", "notes.txt"], src)
    assert secret.read_text() == "HOST SECRET\n"
    sb.copy_in("c1", ["files", "fresh.txt"], src)
    assert (files / "fresh.txt").read_text() == "attachment"


def test_log_is_read_as_a_bounded_tail(env):
    _, jobs, _ = env
    (jobs / f"{JID}.log").write_text("x" * (sb.JOB_LOG_MAX + 50) + "END")
    out = sb.job_state("c1", JID)[2]
    assert len(out) == sb.JOB_LOG_MAX and out.endswith("END")
