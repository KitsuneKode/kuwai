"""greeter/sync: what a program running as you may write into the login screen.

The login screen takes the login password, so its code is root's
(greeter/install); sync, which runs as you at every login, copies data only.
A directory from before that split (all yours) keeps working as it did.
"""
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SYNC = REPO / "greeter" / "sync"


def run(dest, home):
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "KUWAI_GREETER_DIR": str(dest)}
    return subprocess.run([str(SYNC)], env=env, capture_output=True, text=True)


def home_with_data(tmp_path):
    home = tmp_path / "home"
    (home / ".config/kuwai").mkdir(parents=True)
    (home / ".config/kuwai/settings.json").write_text('{"clock24": true, "weatherLocation": "Home Street", "agentServers": ["x"]}')
    (home / ".face").write_bytes(b"png")
    return home


def test_locked_layout_gets_data_only(tmp_path):
    home = home_with_data(tmp_path)
    dest = tmp_path / "greeter"
    (dest / "home").mkdir(parents=True)
    (dest / "start").write_text("#!/bin/sh\n# root's\n")
    (dest / "shell").mkdir()
    (dest / "shell" / "greeter.qml").write_text("// root's\n")
    os.chmod(dest / "shell", 0o555)
    os.chmod(dest, 0o555)                      # as root-owned 0755 looks to you
    try:
        r = run(dest, home)
        assert r.returncode == 0, r.stderr
        assert (dest / "start").read_text() == "#!/bin/sh\n# root's\n"
        assert (dest / "shell" / "greeter.qml").read_text() == "// root's\n"
        assert not (dest / "user").exists() and not (dest / "face").exists()
        assert (dest / "home/.kuwai-user").read_text().strip()
        assert (dest / "home/.face").read_bytes() == b"png"
        assert json.loads((dest / "home/.config/kuwai/settings.json").read_text()) == {"clock24": True}, "display fields only"
        assert not (dest / "home/.config/kuwai/settings.json").stat().st_mode & 0o007, "not readable by everyone"
        assert "still writable" not in r.stderr
    finally:
        os.chmod(dest, 0o755)
        os.chmod(dest / "shell", 0o755)


def test_not_installed_does_nothing(tmp_path):
    home = home_with_data(tmp_path)
    dest = tmp_path / "missing"
    assert run(dest, home).returncode == 0
    assert not dest.exists()


@pytest.mark.skipif(os.geteuid() == 0, reason="as root every folder is writable: the check only applies to the user")
def test_a_login_screen_you_can_write_gets_no_code_and_says_how_to_close_it(tmp_path):
    home = home_with_data(tmp_path)
    dest = tmp_path / "greeter"
    dest.mkdir()                                # all yours: the layout before the split
    r = run(dest, home)
    assert r.returncode == 0, r.stderr
    assert "greeter/install --code" in r.stderr
    assert list(dest.iterdir()) == []


def test_install_script_keeps_the_code_roots():
    text = (REPO / "greeter" / "install").read_text()
    assert 'own=(-o root -g root); [ -z "$SYS" ] || own=()' in text, "root owns it, outside a stand-in root"
    assert 'install -d -m755 "${own[@]}" "$DEST"' in text
    assert '-o "$USER_NAME" "$DEST/home"' in text
    assert '-o "$USER_NAME" "$DEST"\n' not in text      # the whole directory is never yours again


# ── Screens and keyboard: data the greeter reads, never runs ─────────────
LUA = shutil.which("lua")
JQ = shutil.which("jq")
CONF = "home/.config/kuwai-greeter.conf"

MONITORS = [
    {"name": "DP-3", "description": "Acer Technologies XV272U X1 7626041D84232", "width": 2560, "height": 1440,
     "refreshRate": 200.0, "x": 1920, "y": 0, "scale": 1, "transform": 0, "currentFormat": "XBGR2101010",
     "disabled": False, "mirrorOf": "none", "colorManagementPreset": "srgb"},
    {"name": "eDP-1", "description": "California Institute of Technology 0x1509", "width": 2560, "height": 1440,
     "refreshRate": 165.00301, "x": 0, "y": 360, "scale": 1.3333334, "transform": 0, "currentFormat": "XRGB8888",
     "disabled": False, "mirrorOf": "none", "colorManagementPreset": "srgb"},
]
HOSTILE = [
    {"name": "HDMI-A-1", "description": 'Evil "]] os.execute("id") --[[', "width": 1920, "height": 1080,
     "refreshRate": 60, "x": 0, "y": 0, "scale": 1, "transform": 0, "currentFormat": "XRGB8888"},
    {"name": "HDMI-A-2", "description": "Two\nlines", "width": 1920, "height": 1080,
     "refreshRate": 60, "x": 0, "y": 0, "scale": 1, "transform": 0},
    {"name": "HDMI-A-3", "description": "Huge", "width": 1e12, "height": 1080,
     "refreshRate": 60, "x": 0, "y": 0, "scale": 1, "transform": 0},
    {"name": "HDMI-A-4", "description": "Strings", "width": "1920", "height": 1080,
     "refreshRate": 60, "x": 0, "y": 0, "scale": 1, "transform": 0},
    {"name": "DP-9", "description": "Turned off", "width": 1920, "height": 1080, "refreshRate": 60,
     "x": 0, "y": 0, "scale": 1, "transform": 0, "disabled": True},
    {"name": "DP-8", "description": "A mirror", "width": 1920, "height": 1080, "refreshRate": 60,
     "x": 0, "y": 0, "scale": 1, "transform": 0, "mirrorOf": "DP-3"},
    {"name": "DP-7", "description": "HDR on", "width": 3840, "height": 2160, "refreshRate": 144,
     "x": 4480, "y": 0, "scale": 1.5, "transform": 0, "currentFormat": "XBGR2101010", "colorManagementPreset": "hdr"},
]


def fake_hyprctl(tmp_path, monitors, options):
    """A hyprctl that answers `-j monitors` and `-j getoption NAME` from fixtures."""
    tools = tmp_path / "tools"
    tools.mkdir(exist_ok=True)
    data = tmp_path / "hyprctl.json"
    data.write_text(json.dumps({"monitors": monitors, "options": options}))
    script = tools / "hyprctl"
    script.write_text(f"""#!{sys.executable}
import json, sys
d = json.load(open({str(data)!r}))
a = [x for x in sys.argv[1:] if x != "-j"]
if a[:1] == ["monitors"]: print(json.dumps(d["monitors"]))
elif a[:1] == ["getoption"]: print(json.dumps({{"option": a[1], "str": d["options"].get(a[1], ""), "set": True}}))
else: sys.exit(1)
""")
    script.chmod(0o755)
    return tools


def locked(tmp_path):
    dest = tmp_path / "greeter"
    (dest / "home").mkdir(parents=True)
    os.chmod(dest, 0o555)
    return dest


def run_with(dest, home, tools=None, hyprland=True):
    env = {"PATH": (str(tools) + ":" if tools else "") + os.environ["PATH"], "HOME": str(home),
           "KUWAI_GREETER_DIR": str(dest)}
    if hyprland:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = "fixture"
    return subprocess.run([str(SYNC)], env=env, capture_output=True, text=True)


def greeter_reads(conf):
    """What greeter/hyprland.lua makes of the file (tests/greeter/parse_conf.lua)."""
    r = subprocess.run([LUA, str(REPO / "tests/greeter/parse_conf.lua"), str(conf)], cwd=REPO,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout.splitlines()


@pytest.mark.skipif(JQ is None, reason="jq is not installed")
def test_screens_and_keyboard_from_the_session(tmp_path):
    home = home_with_data(tmp_path)
    dest = locked(tmp_path)
    tools = fake_hyprctl(tmp_path, MONITORS, {"input:kb_layout": "us,de", "input:kb_variant": ",nodeadkeys",
                                              "input:kb_options": "grp:alt_shift_toggle"})
    try:
        r = run_with(dest, home, tools)
        assert r.returncode == 0, r.stderr
        conf = dest / CONF
        lines = [l for l in conf.read_text().splitlines() if not l.startswith("#")]
        assert lines == [
            "kb_layout=us,de", "kb_variant=,nodeadkeys", "kb_options=grp:alt_shift_toggle",
            "monitor=2560x1440@200;1920;0;1;0;10;srgb;Acer Technologies XV272U X1 7626041D84232",
            "monitor=2560x1440@165.003;0;360;1.333333;0;8;srgb;California Institute of Technology 0x1509",
        ]
        assert stat.S_IMODE(conf.stat().st_mode) == 0o640
        assert not list((dest / "home/.config").glob(".kuwai-greeter.*")), "the temporary file is left behind"
        if LUA:
            got = greeter_reads(conf)
            assert got[0] == "monitor desc:Acer Technologies XV272U X1 7626041D84232|2560x1440@200.000|1920x0|1|0|10|srgb"
            assert got[1].startswith("monitor desc:California Institute of Technology 0x1509|2560x1440@165.003|0x360|1.333333|0||srgb")
            assert got[2] == "monitor |preferred|auto|1|||"
            if os.path.exists("/usr/share/X11/xkb/symbols/de"):
                assert got[3] == "keyboard us,de|,nodeadkeys|grp:alt_shift_toggle"
    finally:
        os.chmod(dest, 0o755)


@pytest.mark.skipif(JQ is None, reason="jq is not installed")
def test_hostile_screens_and_layouts_are_not_written(tmp_path):
    home = home_with_data(tmp_path)
    dest = locked(tmp_path)
    tools = fake_hyprctl(tmp_path, MONITORS[:1] + HOSTILE, {"input:kb_layout": 'us"; reboot; "', "input:kb_variant": "$(id)"})
    try:
        r = run_with(dest, home, tools)
        assert r.returncode == 0, r.stderr
        text = (dest / CONF).read_text()
        assert "kb_" not in text, "a layout with metacharacters was written"
        monitors = [l for l in text.splitlines() if l.startswith("monitor=")]
        assert monitors == [
            "monitor=2560x1440@200;1920;0;1;0;10;srgb;Acer Technologies XV272U X1 7626041D84232",
            "monitor=3840x2160@144;4480;0;1.5;0;10;;HDR on",       # HDR isn't carried; the 10-bit depth is
        ]
        if LUA:
            got = greeter_reads(dest / CONF)
            assert len(got) == 4 and got[-1] == "keyboard us||", got     # the file is taken: nothing in it is bad
    finally:
        os.chmod(dest, 0o755)


def test_keyboard_from_kuwai_state_outside_hyprland(tmp_path):
    home = home_with_data(tmp_path)
    (home / ".local/state/kuwai").mkdir(parents=True)
    (home / ".local/state/kuwai/state").write_text("mode=focus\nkb_layout=de\nkb_variant=nodeadkeys\nkb_switch=caps\n")
    dest = locked(tmp_path)
    try:
        r = run_with(dest, home, hyprland=False)
        assert r.returncode == 0, r.stderr
        lines = [l for l in (dest / CONF).read_text().splitlines() if not l.startswith("#")]
        assert lines == ["kb_layout=de", "kb_variant=nodeadkeys", "kb_options=grp:caps_toggle"]
    finally:
        os.chmod(dest, 0o755)


@pytest.mark.skipif(LUA is None, reason="lua is not installed")
def test_a_tampered_file_falls_back_to_defaults(tmp_path):
    conf = tmp_path / "kuwai-greeter.conf"
    conf.write_text('kb_layout=us\nmonitor=1920x1080@60;0;0;1;0;8;;x"]]..os.execute("id")..[["\n')
    assert greeter_reads(conf) == ["monitor |preferred|auto|1|||", "keyboard us||"]
    assert greeter_reads(tmp_path / "missing.conf") == ["monitor |preferred|auto|1|||", "keyboard us||"]


def test_install_shows_its_plan_and_copies_only_committed_code():
    text = (REPO / "greeter" / "install").read_text()
    assert "--noconfirm" not in text, "pacman shows the packages and asks"
    assert "Go ahead? [y/N]" in text and "Nothing changed." in text
    assert "git -C \"$KUWAI\" archive HEAD shell greeter" in text
    assert "--no-links" in text and "rsync -a" not in text
    assert "uncommitted changes" in text
