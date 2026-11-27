"""The fresh-install test's scripts: they parse, say what they are, refuse to run
where they would do harm, and never reach into the owner's home.

The test itself needs docker or qemu and a long run (tests/fresh/README.md);
this is the part that runs everywhere.
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = ["run.sh", "inside.sh", "vm.sh"]


def run(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=30, **kw)


@pytest.mark.parametrize("name", SCRIPTS)
def test_bash_syntax(name):
    r = run("bash", "-n", os.path.join(HERE, name))
    assert r.returncode == 0, r.stderr


@pytest.mark.parametrize("name", SCRIPTS)
def test_help_exits_zero(name):
    r = run("bash", os.path.join(HERE, name), "--help")
    assert r.returncode == 0, r.stderr
    assert name in r.stdout


def test_inside_refuses_a_normal_machine():
    if os.geteuid() == 0 or os.path.exists("/.dockerenv"):
        pytest.skip("only meaningful as an ordinary user outside a container")
    r = run("bash", os.path.join(HERE, "inside.sh"), "/nonexistent")
    assert r.returncode == 2
    assert "run as root" in r.stderr


@pytest.mark.parametrize("name", SCRIPTS)
def test_host_scripts_never_name_the_owners_state(name):
    if name == "inside.sh":
        pytest.skip("runs in the container, where HOME is the test user's")
    text = open(os.path.join(HERE, name)).read()
    code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
    for bad in ("~/.config", "~/.local/share/kuwai", "$HOME/.config", "$HOME/.local", "/run/user/$(id -u)"):
        assert bad not in code, f"{name} reaches into {bad}"


def _code(name):
    text = open(os.path.join(HERE, name)).read()
    return re.sub(r"<<'KUWAI_USAGE'.*?\nKUWAI_USAGE\n", "", text, flags=re.S)


@pytest.mark.parametrize("name,allowed", [
    ("run.sh", ("$VOL:", "/var/cache/pacman/pkg:/hostcache:ro")),
    ("vm.sh", ("kuwai-fresh-pkgcache:", "/var/cache/pacman/pkg:/hostcache:ro", "$CACHE:/w")),
])
def test_docker_gets_only_the_package_cache(name, allowed):
    text = _code(name)
    for m in re.findall(r'(?<!command)\s(?:-v|--volume)\s+"?([^\s"]+)', text):
        assert m.startswith(allowed), f"{name}: unexpected mount {m}"
    assert "--privileged" not in text


HOST_SCRIPTS = ["run.sh", "vm.sh"]


def _host_code(name):
    """The script as the host runs it: usage text and the heredocs that only the guest runs are left out."""
    text = _code(name)
    return re.sub(r"<<\s*'(\w+)'.*?\n\1\n", "", text, flags=re.S)


@pytest.mark.skipif(not shutil.which("shellcheck"), reason="shellcheck isn't installed")
@pytest.mark.parametrize("name", SCRIPTS)
def test_shellcheck_clean(name):
    r = run("shellcheck", "-e", "SC2329", "-S", "style", os.path.join(HERE, name))
    assert r.returncode == 0, r.stdout


@pytest.mark.parametrize("name", SCRIPTS)
def test_every_script_stops_on_unset_and_pipe_failures(name):
    assert "set -uo pipefail" in open(os.path.join(HERE, name)).read()


def test_run_cleans_up_on_every_way_out():
    text = _host_code("run.sh")
    assert re.search(r"^trap cleanup EXIT$", text, re.M)
    assert re.search(r"^trap 'exit \d+' INT$", text, re.M) and re.search(r"^trap 'exit \d+' TERM", text, re.M)
    body = text[text.index("cleanup() {"):text.index("\n}\n", text.index("cleanup() {"))]
    assert 'rm -rf "$stage"' in body
    assert 'docker rm -f "$NAME"' in body
    assert text.index("trap cleanup EXIT") < text.index("docker run"), "the trap is set before the container exists"
    assert text.index("trap cleanup EXIT") > text.index("stage=$(mktemp -d)")


def test_vm_cleans_up_on_every_way_out():
    text = _host_code("vm.sh")
    traps = re.findall(r"^\s*trap '([^']*)' (EXIT|INT|TERM[^\n]*)$", text, re.M)
    on_exit = [body for body, sig in traps if sig == "EXIT"]
    assert any("kill $qemu_pid" in b and 'rm -rf "$w"' in b for b in on_exit)
    assert any('docker rm -f "kuwai-fresh-build-$$"' in b for b in on_exit)
    assert [sig for _, sig in traps].count("INT") >= 2
    assert text.index("trap 'kill $qemu_pid") < text.index('qemu-system-x86_64 "${ACCEL[@]}"')
    assert 'docker run --rm --name "kuwai-fresh-build-$$"' in text


@pytest.mark.parametrize("name", HOST_SCRIPTS)
def test_docker_is_only_ever_asked_about_its_own_containers(name):
    text = "\n".join(l for l in _host_code(name).splitlines() if not re.match(r"\s*(echo|printf)\b|.*\becho \"", l))
    for m in re.finditer(r"docker\s+(rm|kill|stop|restart|pause|prune|system|network|image\s+rm|rmi|volume\s+(?:rm|prune))\b([^\n]*)", text):
        verb, rest = m.group(1), m.group(2)
        assert verb in ("rm", "volume rm"), f"{name}: docker {verb}"
        assert re.search(r'"\$NAME"|"kuwai-fresh-build-\$\$"|"\$VOL"|kuwai-fresh-pkgcache', rest), f"{name}: docker {verb}{rest}"
    for bad in ("--privileged", "--net=host", "--network host", "--network=host", "--pid=host", "--pid host", "--ipc=host",
                "--cap-add", "--userns=host", "docker.sock", "-v /:", "-v /home", "-v /etc", "-v /run", "-v /var/run", "-v $HOME", "-v ~"):
        assert bad not in text, f"{name}: {bad}"
    for dev in re.findall(r"--device\s+([^\s)]+)", text):
        assert dev == "/dev/dri/renderD128", f"{name}: --device {dev}"


@pytest.mark.parametrize("name", HOST_SCRIPTS)
def test_the_host_scripts_write_only_to_their_own_folders(name):
    text = _host_code(name)
    sinks = re.findall(r"(?<![<\d&])\d?>>?\s*(\"[^\"]+\"|[^\s;|&)\"]+)", text)
    for target in sinks:
        assert target.strip('"').startswith(("$OUT", "$stage", "$w", "$CACHE", "/dev/null", "&")), f"{name}: writes to {target}"
    local = "\n".join(l for l in text.splitlines() if "docker " not in l)
    for m in re.finditer(r"\b(?:rm|mkdir|touch|mv|ln|tee)\s+(?:-\S+\s+)*(\"[^\"]+\"|[^\s;|&)<>]+)", local):
        arg = m.group(1).strip('"')
        assert arg.startswith(("$OUT", "$stage", "$w", "$CACHE", "$tmp", "$qemu", "-")), f"{name}: {m.group(0)}"
    on_host = "\n".join(l for l in text.splitlines() if "docker exec" not in l and not re.match(r"\s*(echo|printf)\b", l))
    for word in ("sudo", "pkexec", "doas", "systemctl", "loginctl", "hyprctl", "useradd", "chpasswd", "pacman -"):
        assert not re.search(rf"\b{word}", on_host), f"{name} runs {word} on the host"


def test_inside_refuses_before_it_changes_anything():
    text = _code("inside.sh")
    guards = [text.index(g) for g in ('[ "$(id -u)" = 0 ]', "/etc/arch-release", "/.dockerenv")]
    first_change = min(text.index(c) for c in ("pacman -", "useradd", "mkdir -p", "/etc/sudoers.d", "chpasswd"))
    assert max(guards) < first_change


def test_inside_has_no_way_to_name_the_hosts_session():
    text = _code("inside.sh")
    for bad in ("/home/kitsunekode", "git push", "kuwai promote", "~/Projects/rice"):
        assert bad not in text


def _stub_docker(tmp_path):
    stub = tmp_path / "bin" / "docker"
    stub.parent.mkdir(exist_ok=True)
    stub.write_text(f"""#!{sys.executable}
import json, os, sys, time
args = sys.argv[1:]
with open(os.environ["STUB_LOG"], "a") as f:
    f.write(json.dumps(args) + "\\n")
if args[:1] == ["info"] and os.environ.get("STUB_NO_DAEMON"):
    sys.exit(1)
if args[:1] == ["exec"] and "systemctl" in args:
    print("running")
if args[:1] == ["exec"] and "/in/inside.sh" in args:
    print("== a phase")
    print("PASS  a check")
    sys.stdout.flush()
    if os.environ.get("STUB_HANG"):
        open(os.environ["STUB_HANG"], "w").close()
        time.sleep(60)
    if os.environ.get("STUB_INSIDE_RC") == "1":
        print("FAIL  a check")
    sys.exit(int(os.environ.get("STUB_INSIDE_RC", "0")))
""")
    stub.chmod(0o755)
    return stub.parent


def _harness(tmp_path, *args, **extra):
    bin_dir = _stub_docker(tmp_path)
    home = tmp_path / "home"
    work = tmp_path / "tmp"
    home.mkdir(exist_ok=True)
    work.mkdir(exist_ok=True)
    log = tmp_path / "docker.log"
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", HOME=str(home), TMPDIR=str(work),
               XDG_CACHE_HOME=str(home / ".cache"), STUB_LOG=str(log), **extra)
    return env, home, work, log


def _calls(log):
    import json
    return [json.loads(l) for l in log.read_text().splitlines()] if log.exists() else []


def test_run_passes_the_guests_verdict_on_and_removes_its_container(tmp_path):
    for rc in ("0", "1"):
        env, home, work, log = _harness(tmp_path, STUB_INSIDE_RC=rc)
        log.unlink(missing_ok=True)
        out = tmp_path / f"out{rc}"
        r = subprocess.run(["bash", os.path.join(HERE, "run.sh"), "--out", str(out), "--no-hostcache"],
                           env=env, capture_output=True, text=True, timeout=120)
        assert r.returncode == int(rc), r.stdout + r.stderr
        calls = _calls(log)
        runs = [c for c in calls if c[0] == "run"]
        assert len(runs) == 1
        name = runs[0][runs[0].index("--name") + 1]
        assert name.startswith("kuwai-fresh-")
        assert ["rm", "-f", name] in calls
        assert [c for c in calls if c[0] in ("rm", "kill", "stop")] == [["rm", "-f", name]]
        assert list(home.iterdir()) == [], "the host's home was touched"
        assert list(work.iterdir()) == [], "the staging folder was left behind"
        assert "PASS  a check" in r.stdout


def test_run_mounts_only_the_package_cache_and_no_privileges(tmp_path):
    env, home, work, log = _harness(tmp_path)
    r = subprocess.run(["bash", os.path.join(HERE, "run.sh"), "--out", str(tmp_path / "o"), "--no-hostcache"],
                       env=env, capture_output=True, text=True, timeout=120)
    assert r.returncode == 0, r.stdout + r.stderr
    run_call = next(c for c in _calls(log) if c[0] == "run")
    mounts = [run_call[i + 1] for i, a in enumerate(run_call) if a in ("-v", "--volume")]
    assert mounts == ["kuwai-fresh-pkgcache:/var/cache/pacman/pkg"]
    assert not any(a.startswith(("--privileged", "--net", "--pid", "--cap-add", "--device")) for a in run_call)


def test_run_keep_leaves_the_container_and_says_how_to_remove_it(tmp_path):
    env, home, work, log = _harness(tmp_path)
    r = subprocess.run(["bash", os.path.join(HERE, "run.sh"), "--out", str(tmp_path / "o"), "--keep"],
                       env=env, capture_output=True, text=True, timeout=120)
    assert r.returncode == 0
    assert not [c for c in _calls(log) if c[0] == "rm"]
    assert "docker rm -f kuwai-fresh-" in r.stdout


def test_run_exits_two_without_a_docker_daemon(tmp_path):
    env, home, work, log = _harness(tmp_path, STUB_NO_DAEMON="1")
    r = subprocess.run(["bash", os.path.join(HERE, "run.sh"), "--out", str(tmp_path / "o")],
                       env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 2
    assert not [c for c in _calls(log) if c[0] == "run"]


def test_run_removes_its_container_when_interrupted(tmp_path):
    marker = tmp_path / "hanging"
    env, home, work, log = _harness(tmp_path, STUB_HANG=str(marker))
    p = subprocess.Popen(["bash", os.path.join(HERE, "run.sh"), "--out", str(tmp_path / "o"), "--no-hostcache"],
                         env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        for _ in range(200):
            if marker.exists():
                break
            time.sleep(0.1)
        assert marker.exists(), "the stub guest never started"
        os.killpg(p.pid, signal.SIGTERM)
        p.wait(timeout=30)
    finally:
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGKILL)
    calls = _calls(log)
    name = next(c for c in calls if c[0] == "run")
    name = name[name.index("--name") + 1]
    assert ["rm", "-f", name] in calls
    assert list(work.iterdir()) == []


def test_every_fresh_script_is_listed_here_and_executable():
    present = sorted(f for f in os.listdir(HERE) if f.endswith(".sh"))
    assert present == sorted(SCRIPTS)
    for f in present:
        assert os.access(os.path.join(HERE, f), os.X_OK), f


def test_the_pam_fixture_reads_the_password_from_the_environment_only():
    text = open(os.path.join(HERE, "pamcheck", "shell.qml")).read()
    assert 'Quickshell.env("KUWAI_PAM_PASSWORD")' in text and 'config: "login"' in text
    assert "kuwai-fresh" not in text
