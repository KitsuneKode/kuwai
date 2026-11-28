"""Start a user command outside the shell unit, with a literal argv.

A transient service rather than a scope: systemd-run --scope is synchronous
and stays the command's parent, while these callers return before a deletion,
scan or terminal review ends. Type=exec makes systemd-run report a command it
could not even start; --expand-environment=no keeps '$' in a path or label
literal instead of letting the service manager rewrite the argv.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

KEPT_ENV = (
    "HOME",
    "PATH",
    "XDG_CACHE_HOME",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_RUNTIME_DIR",
    "XAUTHORITY",
    "XDG_STATE_HOME",
    "DBUS_SESSION_BUS_ADDRESS",
    "DISPLAY",
    "HYPRLAND_INSTANCE_SIGNATURE",
    "WAYLAND_DISPLAY",
    "XDG_CURRENT_DESKTOP",
    "XDG_SESSION_DESKTOP",
    "XDG_SESSION_TYPE",
    "KUWAI_TERMINAL",
    "SWEEP_COLD",
    "SWEEP_CONFIG_DIR",
    "SWEEP_ENGINE_PATH",
    "SWEEP_REDUCED_MOTION",
    "LANG",
    "LC_ALL",
    "LC_MESSAGES",
)


def systemd_run(env=None):
    env = os.environ if env is None else env
    if env.get("KUWAI_SHELL_UNIT") != "1":
        return None
    return shutil.which("systemd-run", path=env.get("PATH") or os.defpath)


def service_argv(exe, unit, description, cmd, env=None, cwd=None, keep_env=KEPT_ENV):
    env = os.environ if env is None else env
    argv = [
        exe,
        "--user",
        "--collect",
        "--quiet",
        "--expand-environment=no",
        f"--unit={unit}",
        "--slice=app.slice",
        f"--description={description}",
        "--property=Type=exec",
        "--property=StandardOutput=null",
        "--property=StandardError=null",
        f"--working-directory={cwd or Path.home()}",
    ]
    for name in keep_env:
        value = env.get(name)
        if value:
            argv.append(f"--setenv={name}={value}")
    return [*argv, "--", *[str(arg) for arg in cmd]]


def detached(cmd, cwd=None):
    return subprocess.Popen(
        [str(arg) for arg in cmd],
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def log(prefix, text):
    print(f"{prefix}: {text}", file=sys.stderr)


def launch(unit, description, cmd, cwd=None, env=None, keep_env=KEPT_ENV, log_prefix="kuwai", timeout=10):
    env = os.environ if env is None else env
    exe = systemd_run(env)
    if exe:
        argv = service_argv(exe, unit, description, cmd, env=env, cwd=cwd, keep_env=keep_env)
        try:
            done = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=timeout, check=False)
        except subprocess.TimeoutExpired:
            log(log_prefix, f"systemd-run did not answer for {unit}; not starting another copy")
            return "failed"
        except OSError:
            done = None
        if done is not None and done.returncode == 0:
            return "unit"
        log(log_prefix, f"systemd-run could not start {unit}; using one detached process instead (a shell restart can stop it)")
    elif env.get("KUWAI_SHELL_UNIT") == "1":
        log(log_prefix, f"systemd-run is unavailable for {unit}; using one detached process instead (a shell restart can stop it)")
    try:
        detached(cmd, cwd=cwd)
    except OSError:
        log(log_prefix, f"couldn't start {unit}")
        return "failed"
    return "detached"
