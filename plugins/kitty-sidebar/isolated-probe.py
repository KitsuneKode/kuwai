#!/usr/bin/env python3
"""Start only our compositor, with no parent Wayland, D-Bus, or session environment.
No command can address an existing compositor. All writes stay below this spike.
No fallback to a live display; no plugin IPC, no kitty, no Quickshell.
"""
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import tempfile

BASE = Path(__file__).resolve().parent
RUNS = BASE / ".runs"
RUNS.mkdir(exist_ok=True)
run = Path(tempfile.mkdtemp(prefix="headless-", dir=RUNS))
for name in ("home", "runtime", "state", "cache", "config", "data", "kittymux"):
    (run / name).mkdir(mode=0o700)
(run / "runtime/kitty-sidebar-isolated").write_text("isolated\n")
(run / "kittymux/agents.json").write_text(json.dumps({"version": 1, "agents": []}))
config = run / "hyprland.lua"
config.write_text("""-- Entirely private; no source, autostart, or plugin entries.
hl.monitor({ output = "", mode = "1280x800@60", position = "0x0", scale = 1 })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
    debug = { disable_logs = false, enable_stdout_logs = true },
})
""")
env = {
    "PATH": "/usr/bin:/bin", "HOME": str(Path("/mnt") / "home"), "USER": "sidebar-spike",
    "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(Path("/mnt") / "runtime"),
    "XDG_STATE_HOME": str(Path("/mnt") / "state"), "XDG_CACHE_HOME": str(Path("/mnt") / "cache"),
    "XDG_CONFIG_HOME": str(Path("/mnt") / "config"), "XDG_DATA_HOME": str(Path("/mnt") / "data"),
    "KITTY_SIDEBAR_SPIKE": "isolated", "KITTYMUX_STATE": str(Path("/mnt") / "kittymux"),
    "KITTYMUX_SOCKET_DIRS": str(Path("/mnt") / "runtime"), "DO_NOT_TRACK": "1",
    "LIBGL_ALWAYS_SOFTWARE": "1", "__EGL_VENDOR_LIBRARY_FILENAMES": "/usr/share/glvnd/egl_vendor.d/50_mesa.json",
    "AQ_DRM_DEVICES": str(Path("/mnt") / "no-drm-device"),
    "HYPRLAND_NO_SD_NOTIFY": "1", "HYPRLAND_NO_SD_VARS": "1",
    "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(Path("/mnt") / "no-dbus"),
}
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
log = BASE / "evidence/headless.log"
with log.open("w") as output:
    # Mask DRM cards, ttys, D-Bus, live runtime sockets and sysfs. /mnt maps ONLY our run directory.
    command = ["/usr/bin/bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
               "--tmpfs", "/run", "--tmpfs", "/sys", "--tmpfs", "/tmp", "--bind", str(run), "/mnt",
               "--unshare-all", "--die-with-parent", "--new-session", "--chdir", "/mnt",
               "/usr/bin/Hyprland", "--config", "/mnt/hyprland.lua"]
    process = subprocess.Popen(command, env=env,
                               cwd=run, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    timed_out = False
    try:
        code = process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            code = process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            code = process.wait(timeout=3)
result = {"probe": "private baseline compositor, no plugin loaded", "returncode": code,
          "timed_out": timed_out, "dri_available": Path("/dev/dri").exists(),
          "parent_display_inherited": False, "log": "evidence/headless.log",
          "isolated_runtime": str(run.relative_to(BASE) / "runtime"),
          "devices_hidden": True, "namespace_launcher": "bubblewrap", "config": "private Lua, no autostart or plugin"}
(BASE / "evidence/headless-result.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
print("--- relevant compositor output ---")
for line in log.read_text(errors="replace").splitlines():
    if any(x in line.lower() for x in ("backend", "drm", "fail", "error", "gpu", "critical")):
        print(line)
