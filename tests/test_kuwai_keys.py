"""bin/kuwai-keys: your own chords for kuwai's shortcuts, in a file updates never touch."""
import json
import os
import stat
import subprocess
from pathlib import Path

BIN = Path(__file__).resolve().parents[1] / "bin" / "kuwai-keys"


def run(tmp_path, *args):
    env = {k: v for k, v in os.environ.items() if k != "HYPRLAND_INSTANCE_SIGNATURE"}
    env["XDG_CONFIG_HOME"] = str(tmp_path)
    return subprocess.run([str(BIN), *args, "--no-apply"], env=env, capture_output=True, text=True, timeout=10)


def listed(tmp_path):
    r = run(tmp_path, "list", "--json")
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_set_reset_and_the_file(tmp_path):
    assert listed(tmp_path) == {}
    assert run(tmp_path, "set", "SUPER+E", "SUPER + CTRL + E", "Files").returncode == 0
    assert listed(tmp_path) == {"SUPER+E": {"keys": "SUPER + CTRL + E", "text": "Files"}}
    f = tmp_path / "kuwai" / "keys.tsv"
    assert f.read_text() == "SUPER+E\tSUPER + CTRL + E\tFiles\n"
    assert stat.S_IMODE(f.stat().st_mode) == 0o600
    assert run(tmp_path, "reset", "SUPER+E").returncode == 0
    assert listed(tmp_path) == {}


def test_a_workspace_key_moves_by_keycode_and_none_is_allowed(tmp_path):
    r = run(tmp_path, "set", "SUPER+CODE:10", "SUPER + CTRL + code:10", "Workspace 1", "SUPER+T", "", "Terminal")
    assert r.returncode == 0, r.stderr
    assert listed(tmp_path) == {"SUPER+CODE:10": {"keys": "SUPER + CTRL + code:10", "text": "Workspace 1"},
                                "SUPER+T": {"keys": "", "text": "Terminal"}}


def test_the_default_chord_again_is_a_reset(tmp_path):
    run(tmp_path, "set", "SUPER+E", "SUPER + CTRL + E", "Files")
    assert run(tmp_path, "set", "SUPER+E", "SUPER + E", "Files").returncode == 0
    assert listed(tmp_path) == {}


def test_bad_input_changes_nothing(tmp_path):
    run(tmp_path, "set", "SUPER+E", "SUPER + CTRL + E", "Files")
    for args in (["set", "SUPER+E", "SUPER + E + SHIFT", "Files"], ["set", "SUPER+E", "SUPER + $(reboot)", "Files"],
                 ["set", "super e", "SUPER + E", "Files"], ["set", "SUPER+E", "SUPER + SUPER + E", "Files"],
                 ["set", "SUPER+E", "SUPER + CTRL + E"], ["nope"]):
        assert run(tmp_path, *args).returncode == 2, args
    assert listed(tmp_path) == {"SUPER+E": {"keys": "SUPER + CTRL + E", "text": "Files"}}


def test_two_actions_on_one_chord_are_refused(tmp_path):
    run(tmp_path, "set", "SUPER+E", "SUPER + CTRL + E", "Files")
    r = run(tmp_path, "set", "SUPER+T", "CTRL + SUPER + E", "Terminal")
    assert r.returncode == 2 and "two actions" in r.stderr
    assert run(tmp_path, "set", "SUPER+T", "SUPER + CTRL + E", "Terminal", "SUPER+E", "", "Files").returncode == 0


def test_names_cannot_break_lines(tmp_path):
    run(tmp_path, "set", "SUPER+E", "SUPER + CTRL + E", "Files\tand\nmore")
    assert (tmp_path / "kuwai" / "keys.tsv").read_text().count("\n") == 1
    assert run(tmp_path, "reset-all").returncode == 0
    assert listed(tmp_path) == {}


def test_a_hand_edited_bad_line_is_skipped(tmp_path):
    d = tmp_path / "kuwai"
    d.mkdir()
    (d / "keys.tsv").write_text("SUPER+E\tSUPER + CTRL + E\tFiles\ngarbage\nSUPER+T\tSUPER + ; rm\tTerminal\n")
    assert listed(tmp_path) == {"SUPER+E": {"keys": "SUPER + CTRL + E", "text": "Files"}}


def test_a_bare_key_is_refused_and_lock_keeps_a_chord(tmp_path):
    for keys in ("Return", "A", "SHIFT + A", "code:36"):
        assert run(tmp_path, "set", "SUPER+E", keys, "Files").returncode == 2, keys
    assert run(tmp_path, "set", "SUPER+E", "F7", "Files").returncode == 0
    r = run(tmp_path, "set", "SUPER+L", "", "Lock")
    assert r.returncode == 2 and "Lock" in r.stderr
    assert run(tmp_path, "set", "SUPER+L", "SUPER + ALT + L", "Lock").returncode == 0


def test_edits_at_the_same_time_all_land(tmp_path):
    env = {k: v for k, v in os.environ.items() if k != "HYPRLAND_INSTANCE_SIGNATURE"}
    env["XDG_CONFIG_HOME"] = str(tmp_path)
    keys = [f"SUPER + CTRL + ALT + F{n}" for n in range(1, 13)] + [f"SUPER + CTRL + SHIFT + F{n}" for n in range(1, 9)]
    procs = [subprocess.Popen([str(BIN), "set", f"SUPER+F{n}", k, f"Action {n}", "--no-apply"], env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for n, k in enumerate(keys)]
    assert all(p.wait(timeout=30) == 0 for p in procs)
    lines = (tmp_path / "kuwai/keys.tsv").read_text().splitlines()
    assert len([l for l in lines if l.strip()]) == len(keys), "every concurrent edit was kept"
