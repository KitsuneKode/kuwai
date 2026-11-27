import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALL = ROOT / "system/plymouth/install"
THEME = ROOT / "system/plymouth/kuwai"
FILES = ("kuwai.plymouth", "kuwai.script", "ring.png", "pill.png", "dot.png")


def fake_root(tmp_path, *, hooks="base udev plymouth autodetect modconf block filesystems", theme="bgrt"):
    fake = tmp_path / "root"
    (fake / "etc/plymouth").mkdir(parents=True)
    (fake / "etc/plymouth/plymouthd.conf").write_text(f"[Daemon]\nTheme={theme}\nShowDelay=0\n")
    (fake / "etc/mkinitcpio.conf").write_text(f"MODULES=()\nHOOKS=({hooks})\n")
    stub_dir = tmp_path / "stub"
    stub_dir.mkdir()
    log = tmp_path / "setter.log"
    stub = stub_dir / "plymouth-set-default-theme"
    stub.write_text(f'#!/bin/sh\necho "$@" >> {log}\n')
    stub.chmod(0o755)
    return fake, stub, log


def run(fake, *args, stub=None, extra_env=None):
    env = {"PATH": os.environ["PATH"], "HOME": str(fake.parent)}
    if stub:
        env["PLYMOUTH_SET_DEFAULT_THEME"] = str(stub)
    env.update(extra_env or {})
    return subprocess.run([str(INSTALL), "--dirty", "--root", str(fake), *args], env=env, capture_output=True, text=True, timeout=60)


def test_the_theme_is_complete_and_its_script_points_at_what_the_plymouth_file_names():
    for name in FILES:
        assert (THEME / name).is_file() and (THEME / name).stat().st_size > 0, name
    ini = (THEME / "kuwai.plymouth").read_text()
    assert re.search(r"^ModuleName=script$", ini, re.M)
    assert "ImageDir=/usr/share/plymouth/themes/kuwai" in ini
    assert "ScriptFile=/usr/share/plymouth/themes/kuwai/kuwai.script" in ini
    script = (THEME / "kuwai.script").read_text()
    for image in re.findall(r'Image\("([^"]+)"\)', script):
        assert (THEME / image).is_file(), image
    for hook in ("SetRefreshFunction", "SetDisplayPasswordFunction", "SetDisplayNormalFunction", "SetDisplayQuestionFunction"):
        assert f"Plymouth.{hook}(" in script, hook
    assert script.count("{") == script.count("}") and script.count("(") == script.count(")")
    assert "SetBackgroundTopColor(0, 0, 0)" in script and "SetBackgroundBottomColor(0, 0, 0)" in script


def test_installs_into_the_fake_root_and_sets_kuwai_as_the_default_theme(tmp_path):
    fake, stub, log = fake_root(tmp_path)
    done = run(fake, stub=stub)
    assert done.returncode == 0, done.stderr + done.stdout
    dest = fake / "usr/share/plymouth/themes/kuwai"
    for name in FILES:
        assert (dest / name).read_bytes() == (THEME / name).read_bytes(), name
        assert oct((dest / name).stat().st_mode & 0o777) == "0o644"
    assert oct(dest.stat().st_mode & 0o777) == "0o755"
    assert log.read_text().split() == ["-R", "kuwai"], "plymouth-set-default-theme would be called with kuwai, rebuilding the initramfs"
    assert (fake / "var/lib/kuwai/plymouth/previous-theme").read_text().strip() == "bgrt"
    assert not list(tmp_path.glob("**/.kuwai-*")), "nothing is left behind"


def test_without_the_plymouth_hook_it_says_so_and_does_not_rebuild(tmp_path):
    fake, stub, log = fake_root(tmp_path, hooks="base udev autodetect modconf block encrypt filesystems")
    done = run(fake, stub=stub)
    assert done.returncode == 0
    assert log.read_text().split() == ["kuwai"], "no -R: an initramfs without the hook would show nothing new"
    assert "no\n`plymouth` hook" in done.stdout or "no `plymouth` hook" in done.stdout.replace("\n", " ")
    assert "docs/manual/boot.md" in done.stdout


def test_no_initramfs_leaves_it_alone(tmp_path):
    fake, stub, log = fake_root(tmp_path)
    assert run(fake, "--no-initramfs", stub=stub).returncode == 0
    assert log.read_text().split() == ["kuwai"]


def test_a_dry_run_changes_nothing_and_says_what_it_would_call(tmp_path):
    fake, stub, log = fake_root(tmp_path)
    before = sorted(p.relative_to(fake).as_posix() for p in fake.rglob("*"))
    done = run(fake, "--dry-run", stub=stub)
    assert done.returncode == 0
    assert sorted(p.relative_to(fake).as_posix() for p in fake.rglob("*")) == before
    assert not log.exists()
    assert f"would: {stub} -R kuwai" in done.stdout
    assert "would: install -m 0644" in done.stdout


def test_a_fake_root_never_runs_the_real_tool(tmp_path):
    fake, _stub, log = fake_root(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    real = bin_dir / "plymouth-set-default-theme"
    real.write_text(f'#!/bin/sh\necho REAL >> {log}\n')
    real.chmod(0o755)
    done = run(fake, extra_env={"PATH": f"{bin_dir}:{os.environ['PATH']}"})
    assert done.returncode == 0
    assert not log.exists(), "only a named stand-in is ever run inside a fake root"
    assert "would run: plymouth-set-default-theme -R kuwai" in done.stdout


def test_undo_restores_the_earlier_theme_and_removes_kuwai(tmp_path):
    fake, stub, log = fake_root(tmp_path)
    assert run(fake, stub=stub).returncode == 0
    (fake / "etc/plymouth/plymouthd.conf").write_text("[Daemon]\nTheme=kuwai\n")
    log.unlink()
    done = run(fake, "--undo", stub=stub)
    assert done.returncode == 0, done.stderr
    assert log.read_text().split() == ["-R", "bgrt"]
    assert not (fake / "usr/share/plymouth/themes/kuwai").exists()
    assert not (fake / "var/lib/kuwai/plymouth/previous-theme").exists()


def test_undo_with_nothing_recorded_resets_to_the_distro_default(tmp_path):
    fake, stub, log = fake_root(tmp_path, theme="kuwai")
    assert run(fake, "--undo", stub=stub).returncode == 0
    assert log.read_text().split() == ["-R", "--reset"]


def test_undo_leaves_another_default_theme_alone(tmp_path):
    fake, stub, log = fake_root(tmp_path, theme="spinner")
    assert run(fake, "--undo", stub=stub).returncode == 0
    assert not log.exists()


def test_a_second_install_keeps_the_first_earlier_theme(tmp_path):
    fake, stub, log = fake_root(tmp_path)
    assert run(fake, stub=stub).returncode == 0
    (fake / "etc/plymouth/plymouthd.conf").write_text("[Daemon]\nTheme=kuwai\n")
    assert run(fake, stub=stub).returncode == 0
    assert (fake / "var/lib/kuwai/plymouth/previous-theme").read_text().strip() == "bgrt"


def test_links_in_the_theme_are_refused(tmp_path):
    copy = tmp_path / "repo"
    shutil.copytree(ROOT / "system/plymouth", copy / "system/plymouth")
    (copy / "system/plymouth/kuwai/ring.png").unlink()
    (copy / "system/plymouth/kuwai/ring.png").symlink_to("/etc/passwd")
    fake, stub, log = fake_root(tmp_path)
    done = subprocess.run([str(copy / "system/plymouth/install"), "--dirty", "--root", str(fake)], env={"PATH": os.environ["PATH"], "PLYMOUTH_SET_DEFAULT_THEME": str(stub)}, capture_output=True, text=True, timeout=60)
    assert done.returncode == 1 and "links or special files" in done.stderr
    assert not (fake / "usr").exists() and not log.exists()


def test_without_sudo_and_without_a_fake_root_it_refuses():
    if os.getuid() == 0:
        return
    done = subprocess.run([str(INSTALL)], env={"PATH": os.environ["PATH"]}, capture_output=True, text=True, timeout=30)
    assert done.returncode == 1 and "run with sudo" in done.stderr


def test_unknown_options_print_usage():
    done = subprocess.run([str(INSTALL), "--wat"], env={"PATH": os.environ["PATH"]}, capture_output=True, text=True, timeout=30)
    assert done.returncode == 2 and "usage:" in done.stderr


def committed_copy(tmp_path):
    copy = tmp_path / "repo"
    shutil.copytree(ROOT / "system/plymouth", copy / "system/plymouth")
    git = ["git", "-C", str(copy), "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
    subprocess.run(["git", "-C", str(copy), "init", "-q"], check=True)
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-qm", "x"], check=True)
    return copy


def test_by_default_it_installs_what_is_committed_and_refuses_what_is_not(tmp_path):
    copy = committed_copy(tmp_path)
    fake, stub, log = fake_root(tmp_path)
    env = {"PATH": os.environ["PATH"], "PLYMOUTH_SET_DEFAULT_THEME": str(stub)}
    tool = str(copy / "system/plymouth/install")
    (copy / "system/plymouth/kuwai/kuwai.script").write_text("Window.SetBackgroundTopColor(1, 1, 1);\n")
    done = subprocess.run([tool, "--root", str(fake)], env=env, capture_output=True, text=True, timeout=60)
    assert done.returncode == 1 and "uncommitted changes" in done.stderr
    assert not (fake / "usr").exists()
    subprocess.run(["git", "-C", str(copy), "checkout", "-q", "--", "."], check=True)
    done = subprocess.run([tool, "--root", str(fake)], env=env, capture_output=True, text=True, timeout=60)
    assert done.returncode == 0, done.stderr
    assert (fake / "usr/share/plymouth/themes/kuwai/kuwai.script").read_bytes() == (THEME / "kuwai.script").read_bytes()
