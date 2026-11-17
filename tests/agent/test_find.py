"""kuwai-ollama find: the assistant's sidebar searches chats that aren't in
memory through their files (ai-chats/<id>.json, OllamaService / chatstore.mjs).
The snippet must be the one the sidebar cuts for the open chat."""
import json
import subprocess

from conftest import HELPER


def chat(path, cid, texts):
    msgs = [{"role": "user" if i % 2 == 0 else "assistant", "text": t} for i, t in enumerate(texts)]
    path.joinpath(cid + ".json").write_text(json.dumps({"version": 2, "id": cid, "title": "T", "messages": msgs}, ensure_ascii=False))


def find(folder, q):
    p = subprocess.run([str(HELPER), "find", str(folder), q], capture_output=True, text=True, timeout=15)
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout)


def test_finds_chats_and_cuts_the_sidebars_snippet(tmp_path):
    chat(tmp_path, "1", ["first message", "Here is   a   long\nanswer about the quarterly numbers and what they mean for you"])
    chat(tmp_path, "2", ["nothing here"])
    assert find(tmp_path, "QUARTERLY") == {"1": "…a long answer about the quarterly numbers and what they mean for you"}


def test_whitespace_quotes_and_non_ascii_still_match(tmp_path):
    chat(tmp_path, "1", ['she said "über\ncool" twice'])
    assert "1" in find(tmp_path, "über cool")
    assert "1" in find(tmp_path, '"über')


def test_ignores_files_that_arent_chats(tmp_path):
    chat(tmp_path, "1", ["needle"])
    tmp_path.joinpath("2.json").write_text('{"id":"2","messages":[{"text":"needle"')     # cut short
    tmp_path.joinpath("not a chat.json").write_text('{"messages":[{"text":"needle"}]}')
    tmp_path.joinpath("3.txt").write_text("needle")
    assert find(tmp_path, "needle") == {"1": "needle"}


def test_empty_query_or_missing_folder(tmp_path):
    chat(tmp_path, "1", ["x"])
    assert find(tmp_path, "  ") == {}
    assert find(tmp_path / "nope", "x") == {}
