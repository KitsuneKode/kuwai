"""Per-monitor wallpaper storage (keyed by output description) and awww helpers."""
import json
import os
import re
import shutil
import subprocess
import time


def output_identity(monitor):
    """Stable identity for an output: EDID description without a trailing connector suffix."""
    if not isinstance(monitor, dict):
        return ""
    name = str(monitor.get("name") or "").strip()
    desc = str(monitor.get("description") or "").strip()
    if desc and name:
        suffix = f" ({name})"
        if desc.endswith(suffix):
            desc = desc[: -len(suffix)].strip()
    return desc


def query_monitors():
    """Return connected monitors from `hyprctl monitors -j`, or [] when unavailable."""
    exe = shutil.which("hyprctl")
    if not exe:
        return []
    try:
        r = subprocess.run(
            [exe, "monitors", "-j"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode != 0:
            return []
        data = json.loads(r.stdout)
        return data if isinstance(data, list) else []
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []


def primary_monitor(monitors):
    """Focused monitor first, else monitor id 0, else the first connected monitor."""
    if not monitors:
        return None
    for m in monitors:
        if isinstance(m, dict) and m.get("focused") is True:
            return m
    for m in monitors:
        if isinstance(m, dict) and m.get("id") == 0:
            return m
    return monitors[0] if isinstance(monitors[0], dict) else None


def resolve_output(target, monitors):
    """Resolve connector name or description into (connector, identity, monitor_dict)."""
    want = str(target or "").strip()
    if not want:
        return "", "", None
    for m in monitors or []:
        if not isinstance(m, dict):
            continue
        if str(m.get("name") or "").strip() == want:
            return want, output_identity(m), m
    for m in monitors or []:
        if not isinstance(m, dict):
            continue
        ident = output_identity(m)
        if ident and ident == want:
            return str(m.get("name") or want).strip(), ident, m
    return "", "", None


def state_path(state_home):
    return os.path.join(state_home, "kuwai", "wallpapers.json")


def load_screen_walls(state_home):
    path = state_path(state_home)
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, ValueError):
        raw = {}
    if not isinstance(raw, dict):
        raw = {}
    default_wall = raw.get("default") if isinstance(raw.get("default"), str) else ""
    screens_raw = raw.get("screens") if isinstance(raw.get("screens"), dict) else {}
    screens = {
        str(k): str(v)
        for k, v in screens_raw.items()
        if isinstance(k, str) and k.strip() and isinstance(v, str) and v.strip()
    }
    boundary = raw.get("sunBoundary") if isinstance(raw.get("sunBoundary"), str) else ""
    mode = raw.get("colorMode")
    return {"schema": 1, "default": default_wall, "screens": screens, "sunBoundary": boundary,
            "colorMode": mode if mode in ("theme", "auto", "dark", "light") else ""}


def save_screen_walls(state_home, data):
    path = state_path(state_home)
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    payload = {
        "schema": 1,
        "default": str(data.get("default") or ""),
        "screens": dict(data.get("screens") or {}),
        "sunBoundary": data.get("sunBoundary") or "",
        "colorMode": data.get("colorMode") or "",
    }
    tmp = os.path.join(parent, f".wallpapers-{os.getpid()}-{time.time_ns()}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    return payload


def set_global_wall(state_home, image_path):
    real = os.path.realpath(image_path) if image_path else ""
    data = load_screen_walls(state_home)
    data.update(default=real, screens={}, colorMode="")
    return save_screen_walls(state_home, data)


def set_screen_wall(state_home, output_id, image_path, fallback_wall="", mode=""):
    data = load_screen_walls(state_home)
    real = os.path.realpath(image_path)
    ident = str(output_id or "").strip()
    if not data["default"] and fallback_wall:
        data["default"] = fallback_wall
    if ident:
        data["screens"][ident] = real
    data["colorMode"] = mode
    return save_screen_walls(state_home, data)


def wall_for_monitor(data, monitor, fallback_wall=""):
    ident = output_identity(monitor)
    screens = (data or {}).get("screens") or {}
    cand = screens.get(ident) or ""
    if cand and os.path.isfile(cand):
        return os.path.realpath(cand)
    default_wall = (data or {}).get("default") or ""
    if default_wall and os.path.isfile(default_wall):
        return os.path.realpath(default_wall)
    if fallback_wall and os.path.isfile(fallback_wall):
        return os.path.realpath(fallback_wall)
    return ""


def connected_screen_walls(state_home, fallback_wall="", monitors=None):
    mons = query_monitors() if monitors is None else monitors
    data = load_screen_walls(state_home)
    info = []
    by_connector = {}
    for m in mons:
        if not isinstance(m, dict):
            continue
        name = str(m.get("name") or "").strip()
        if not name:
            continue
        ident = output_identity(m)
        wall = wall_for_monitor(data, m, fallback_wall)
        by_connector[name] = wall
        info.append({
            "name": name,
            "description": str(m.get("description") or "").strip(),
            "identity": ident,
            "focused": bool(m.get("focused")),
            "wallpaper": wall,
            "custom": ident in data["screens"],
        })
    return info, by_connector


def ensure_awww_daemon(exe):
    if subprocess.run([exe, "query"], stdin=subprocess.DEVNULL, capture_output=True).returncode == 0:
        return True
    if shutil.which("awww-daemon"):
        subprocess.Popen(
            ["awww-daemon", "--format", "xrgb"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        for _ in range(40):
            if subprocess.run([exe, "query"], stdin=subprocess.DEVNULL, capture_output=True).returncode == 0:
                return True
            time.sleep(0.05)
    return False


def apply_awww_output(image, output=None, transition=None):
    exe = shutil.which("awww")
    if not exe or not image or not os.path.isfile(image):
        return False
    if not ensure_awww_daemon(exe):
        return False
    kind = transition if transition is not None else (os.environ.get("WALLPAPER_AWWW_TRANSITION_DEFAULT") or "fade")
    how = ["--transition-type", "none"] if kind == "none" else ["--transition-type", "fade", "--transition-duration", "0.6"]
    cmd = [exe, "img"]
    if output:
        cmd.extend(["-o", str(output)])
    cmd.append(image)
    cmd.extend(how)
    r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode == 0


def restore_screens(state_home, fallback_wall="", target_output=None, transition="none", apply_live=True):
    monitors = query_monitors()
    data = load_screen_walls(state_home)
    restored = []
    prim = primary_monitor(monitors)
    primary_wall = wall_for_monitor(data, prim, fallback_wall) if prim else (
        os.path.realpath(data["default"]) if data.get("default") and os.path.isfile(data["default"])
        else (os.path.realpath(fallback_wall) if fallback_wall and os.path.isfile(fallback_wall) else "")
    )
    if monitors:
        want = [m for m in monitors if isinstance(m, dict) and (not target_output or m.get("name") == target_output or output_identity(m) == target_output)]
        for m in want:
            name = str(m.get("name") or "").strip()
            ident = output_identity(m)
            img = wall_for_monitor(data, m, fallback_wall)
            if not name or not img:
                continue
            ok = apply_awww_output(img, output=name, transition=transition) if apply_live else True
            restored.append({"output": name, "identity": ident, "wallpaper": img, "ok": ok})
    elif not target_output and primary_wall:
        ok = apply_awww_output(primary_wall, output=None, transition=transition) if apply_live else True
        restored.append({"output": "", "identity": "", "wallpaper": primary_wall, "ok": ok})
    return {
        "restored": restored,
        "primary": primary_wall,
        "primaryOutput": str(prim.get("name") or "") if prim else "",
    }
