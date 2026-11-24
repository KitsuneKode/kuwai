"""kuwai's shell runs as kuwai-shell.service, and only that keeps it running.

2026-11-21: a crash left the shell to Quickshell's own handler, which came
back as ~/.config/quickshell (an old prototype) with the old run's helpers
still attached; a `killall qs` left no shell at all and the password prompt
gave up for good. These pin the unit, the client that starts it, and the rule
that what the shell opens for you lives outside the shell's cgroup.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def unit(name):
    keys = {}
    for line in (REPO / "systemd" / name).read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            keys.setdefault(k.strip(), []).append(v.strip())
    return keys


def test_the_unit_restarts_the_shell_and_owns_everything_it_started():
    u = unit("kuwai-shell.service")
    assert u["Restart"] == ["always"] and u["RestartSec"] == ["1"]
    assert u["KillMode"] == ["control-group"] and u["KillSignal"] == ["SIGKILL"]
    assert u["SuccessExitStatus"] == ["SIGKILL"], "a restart's own SIGKILL must not fire OnFailure (the fallback cancels the start)"
    assert "QS_DISABLE_CRASH_HANDLER=1" in u["Environment"]
    assert "KUWAI_SHELL_UNIT=1" in u["Environment"]
    assert u["OnFailure"] == ["kuwai-shell-broken.service"]
    assert u["EnvironmentFile"] == ["-%t/kuwai/shell.env"]
    assert all(cmd.endswith("--run'") for cmd in u["ExecStart"])
    assert "WantedBy" not in u, "started by kuwai-shell after Hyprland's environment is in, never on its own"


def test_the_fallback_gives_way_to_the_shell():
    u = unit("kuwai-shell-broken.service")
    assert u["Conflicts"] == ["kuwai-shell.service"]
    assert all(cmd.endswith("--broken'") for cmd in u["ExecStart"])


def test_the_password_prompt_never_gives_up_for_good():
    u = unit("kuwai-auth.service")
    assert u["StartLimitIntervalSec"] == ["0"]
    assert u["RestartMaxDelaySec"] == ["30"]


def test_install_and_migration_link_both_units():
    units = re.search(r"^UNITS=\((.*)\)$", (REPO / "install.sh").read_text(), re.M).group(1).split()
    assert "kuwai-shell.service" in units and "kuwai-shell-broken.service" in units
    mig = (REPO / "migrations/0003-shell-as-a-service.sh").read_text()
    assert "kuwai-shell.service kuwai-shell-broken.service" in mig and "daemon-reload" in mig


def test_the_shell_runs_in_the_foreground_under_the_unit():
    src = (REPO / "bin/kuwai-shell").read_text()
    run = re.search(r"^run\(\) \{(.*?)^\}", src, re.S | re.M).group(1)
    assert 'exec qs -p "$SHELL_DIR"\n' in run
    assert " -d" not in run


def test_a_restart_asked_from_inside_the_shell_outlives_it():
    src = (REPO / "bin/kuwai-shell").read_text()
    body = re.search(r"^start_unit\(\) \{(.*?)^\}", src, re.S | re.M).group(1)
    assert body.index("inside_unit") < body.index("systemctl --user restart")
    assert "exec systemd-run --user" in body


OPENS_APP = re.compile(r"""execDetached\(\[\s*"xdg-open"|openUrlExternally\(|\b(?:entry|found|modelData)\.execute\(\)""")


def test_what_the_shell_opens_for_you_goes_through_apps():
    found = []
    for f in sorted((REPO / "shell").rglob("*.qml")):
        if f.name == "Apps.qml":
            continue
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if OPENS_APP.search(line):
                found.append(f"{f.relative_to(REPO)}:{i}: {line.strip()[:100]}")
    assert not found, "opened inside the shell's cgroup (a restart would close it); use Apps.open/run/launch:\n" + "\n".join(found)


def test_apps_never_writes_what_it_opens_into_the_journal():
    src = (REPO / "shell/services/Apps.qml").read_text()
    assert '"--description=kuwai: opened from the shell"' in src
    assert '"--slice=app.slice"' in src
    assert '"--property=StandardOutput=null", "--property=StandardError=null"' in src, "an app's own output (URLs, tokens) stays out of the journal"


def env_line(value):
    script = REPO / "bin/kuwai-shell"
    fn = re.search(r"^env_value\(\) \{.*?^\}", script.read_text(), re.S | re.M).group(0)
    return subprocess.run(["bash", "-c", fn + '\nenv_value K "$1"', "x", value], capture_output=True, text=True).stdout


def test_the_environment_file_quotes_what_it_writes():
    assert env_line('/a b/"c"\\d') == 'K="/a b/\\"c\\"\\\\d"\n'
    assert env_line("two\nlines") == ""


def stub(path, body):
    path.write_text("#!/bin/bash\n" + body + "\n")
    path.chmod(0o755)


def test_the_client_imports_hyprland_and_restarts_the_unit(tmp_path):
    root = tmp_path / "kuwai"
    (root / "bin").mkdir(parents=True)
    (root / "lib").mkdir()
    (root / "shell").mkdir()
    shutil.copy(REPO / "bin/kuwai-shell", root / "bin/kuwai-shell")
    shutil.copy(REPO / "lib/hyde.sh", root / "lib/hyde.sh")
    stub(root / "bin/kuwai-migrate", "exit 0")
    stub(root / "bin/kuwai", "exit 0")
    rt = tmp_path / "run"
    (rt / "kuwai").mkdir(parents=True)
    (rt / "hypr/live").mkdir(parents=True)
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(rt / "hypr/live/.socket.sock"))
    stray = subprocess.Popen(["sleep", "60"])
    calls = tmp_path / "calls"
    fake = tmp_path / "fakebin"
    fake.mkdir()
    log_dir = rt / "quickshell/by-id/new"
    stub(fake / "systemctl", f"""echo "systemctl $*" >>{calls}
case "$*" in
  "--user cat kuwai-shell.service") exit 0 ;;
  "--user show -p MainPID --value kuwai-shell.service") echo 4242 ;;
  "--user show-environment") echo HYPRLAND_INSTANCE_SIGNATURE=old; cat {tmp_path}/manager-env 2>/dev/null ;;
  "--user restart kuwai-shell.service")
    mkdir -p {log_dir}
    printf 'Launching config: "%s/shell/shell.qml"\\nConfiguration Loaded\\n' {root} >{log_dir}/log.qslog ;;
esac
exit 0""")
    stub(fake / "qs", f"echo '{json.dumps([{'pid': 4242}, {'pid': stray.pid}])}'")
    stub(fake / "busctl", "echo 'u 4242'")
    stub(fake / "dbus-update-activation-environment",
         f'echo "import $*" >>{calls}; echo "KUWAI_ENV_STAMP=$KUWAI_ENV_STAMP" >{tmp_path}/manager-env')
    stub(fake / "hyprctl", f'''echo "hyprctl $*" >>{calls}
cmd=${{2#*\\[==\\[}}; cmd=${{cmd%\\]==\\]*}}
eval "$cmd"''')
    shutil.copy(REPO / "bin/kuwai-session-env", root / "bin/kuwai-session-env")
    env = {**os.environ, "PATH": f"{fake}:{os.environ['PATH']}", "XDG_RUNTIME_DIR": str(rt),
           "HOME": str(tmp_path), "XDG_STATE_HOME": str(tmp_path / "state"), "XDG_CACHE_HOME": str(tmp_path / "cache"),
           "XDG_CONFIG_HOME": str(tmp_path / "config"), "HYPRLAND_INSTANCE_SIGNATURE": "live",
           "KUWAI_SHELL_ENV": "QV4_MM_STATS=1", "SHAZAM_DUP_WINDOW": "0"}
    env.pop("KUWAI_SHELL_LEGACY", None)
    try:
        r = subprocess.run([root / "bin/kuwai-shell"], env=env, capture_output=True, text=True, timeout=30)
        assert r.returncode == 0, r.stderr
        lines = calls.read_text().splitlines()
        imported = next(i for i, line in enumerate(lines) if line.startswith("import "))
        restarted = lines.index("systemctl --user restart kuwai-shell.service")
        assert imported < restarted, "Hyprland's environment goes in before the shell starts"
        assert any(line.startswith("hyprctl dispatch hl.dsp.exec_cmd(") for line in lines[:imported]), "through Hyprland"
        assert "HYPRLAND_INSTANCE_SIGNATURE" in lines[imported].split() and "SHAZAM_DUP_WINDOW" in lines[imported].split()
        assert lines.index("systemctl --user reset-failed kuwai-shell.service kuwai-shell-broken.service") < restarted
        written = (rt / "kuwai/shell.env").read_text()
        assert f'KUWAI_SHELL_ROOT="{root}"' in written and 'KUWAI_SHELL_ENV="QV4_MM_STATS=1"' in written
        stray.wait(timeout=5)
        assert stray.returncode == -9, "a shell started outside the unit is stopped"
    finally:
        stray.kill()
        sock.close()


def test_the_session_environment_goes_over_whole_but_for_a_few(tmp_path):
    fake = tmp_path / "fakebin"
    fake.mkdir()
    out = tmp_path / "args"
    stub(fake / "dbus-update-activation-environment", f'printf "%s\\n" "$@" >{out}; echo "$KUWAI_ENV_STAMP" >>{out}')
    env = {"PATH": f"{fake}:/usr/bin:/bin", "HOME": str(tmp_path), "LIBVA_DRIVER_NAME": "nvidia",
           "HYPRLAND_CONFIG": "/x/hyprland.lua", "MULTI": "a\nb", "WAYLAND_DISPLAY": "wayland-1"}
    subprocess.run([REPO / "bin/kuwai-session-env", "12;rm"], env=env, check=True)
    got = out.read_text().split()
    assert "--systemd" in got and "LIBVA_DRIVER_NAME" in got and "WAYLAND_DISPLAY" in got
    assert "HYPRLAND_CONFIG" not in got, "Hyprland 0.57 reads it as its config: never hand it to other programs"
    assert "MULTI" not in got and "PWD" not in got
    assert got[-1] == "0", "a stamp that isn't digits becomes 0"


def test_startup_exports_through_the_same_helper():
    src = (REPO / "hypr/kuwai/startup.lua").read_text()
    assert 'K.bin .. "/kuwai-session-env"' in src
    assert src.index("kuwai-session-env") < src.index("kuwai-shell")
