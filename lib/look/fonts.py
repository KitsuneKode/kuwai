import json
import os
import re
import shutil
import subprocess
from pathlib import Path

MONO_CANDIDATES = {
    "sf-mono": ("SF Mono",),
    "geist-mono": ("Geist Mono", "GeistMono Nerd Font"),
    "monolisa": ("MonoLisa", "MonoLisa Nerd Font"),
    "dank-mono": ("Dank Mono", "DankMono Nerd Font", "DankMono Nerd Font Mono"),
    "maple": ("Maple Mono", "Maple Mono NF", "Maple Mono Nerd Font"),
    "jetbrains": ("JetBrains Mono", "JetBrainsMono Nerd Font", "JetBrainsMono NF"),
    "iosevka": ("Iosevka", "Iosevka Nerd Font", "IosevkaTerm Nerd Font"),
}

UI_CANDIDATES = {
    "sf-rounded": ("SF Pro Text", "Geist", "Inter"),
    "sf": ("SF Pro Text", "Geist", "Inter"),
    "auto": ("SF Pro Text", "Geist", "Inter"),
    "geist": ("Geist", "Inter"),
    "inter": ("Inter", "Geist"),
}


def installed_font_families():
    if not shutil.which("fc-list"):
        return set()
    res = subprocess.run(
        ["fc-list", ":", "family"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if res.returncode != 0:
        return set()
    out = set()
    for line in res.stdout.splitlines():
        for part in line.split(","):
            name = part.strip()
            if name:
                out.add(name)
    return out


def first_installed(names, installed):
    for name in names:
        if name in installed:
            return name
    return ""


def resolve_desktop_fonts(settings, installed):
    profile = str((settings or {}).get("fontProfile") or "auto").lower()
    mono_pref = str((settings or {}).get("monoFont") or "auto").lower()
    scale = float((settings or {}).get("textScale") or 1.0)
    scale = max(1.0, min(2.0, scale))

    if profile == "system":
        ui = ""
    else:
        ui = first_installed(UI_CANDIDATES.get(profile, UI_CANDIDATES["auto"]), installed)

    sf_profile = profile in ("auto", "sf", "sf-rounded") and "SF Pro Text" in installed
    if mono_pref in MONO_CANDIDATES:
        mono = first_installed(MONO_CANDIDATES[mono_pref], installed)
    else:
        order = (
            ("SF Mono", "Geist Mono", "MonoLisa", "Maple Mono", "Dank Mono", "JetBrains Mono")
            if sf_profile
            else ("Geist Mono", "SF Mono", "MonoLisa", "Maple Mono", "Dank Mono", "JetBrains Mono")
        )
        mono = first_installed(order, installed)
    if not mono:
        mono = first_installed(("Geist Mono", "JetBrains Mono", "monospace"), installed) or "monospace"

    pt = max(10, min(22, int(round(12 * scale))))
    mono_pt = max(9, min(20, int(round(11 * scale))))
    return {
        "profile": profile,
        "uiFamily": ui,
        "uiSpec": f"{ui} {pt}" if ui else "",
        "monoFamily": mono,
        "monoSpec": f"{mono} {mono_pt}",
        "pt": pt,
        "monoPt": mono_pt,
    }


def upsert_gtk_ini(path, font_spec):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    text = target.read_text(encoding="utf-8") if target.is_file() else ""
    lines = text.splitlines()
    out = []
    in_settings = False
    found_section = False
    written = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_settings and not written:
                out.append(f"gtk-font-name={font_spec}")
                written = True
            in_settings = stripped == "[Settings]"
            if in_settings:
                found_section = True
            out.append(line)
            continue
        if in_settings and re.match(r"^\s*gtk-font-name\s*=", line):
            if not written:
                out.append(f"gtk-font-name={font_spec}")
                written = True
            continue
        out.append(line)
    if not found_section:
        if out and out[-1] != "":
            out.append("")
        out.append("[Settings]")
        out.append(f"gtk-font-name={font_spec}")
    elif in_settings and not written:
        out.append(f"gtk-font-name={font_spec}")
    tmp = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    tmp.write_text("\n".join(out) + "\n", encoding="utf-8")
    os.replace(tmp, target)


def render_kitty_fonts(mono_family):
    safe = str(mono_family).replace("\n", " ").strip()
    return "\n".join([
        f"font_family {safe}",
        "bold_font auto",
        "italic_font auto",
        "bold_italic_font auto",
        "",
    ])


def read_kuwai_settings(config_home):
    path = Path(config_home) / "kuwai" / "settings.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def sync_desktop_fonts(config_home, state_home, apply_live=True, dry_run=False, installed=None):
    settings = read_kuwai_settings(config_home)
    families = installed if installed is not None else installed_font_families()
    plan = resolve_desktop_fonts(settings, families)
    written = []
    if not dry_run:
        if plan["uiSpec"]:
            for ver in ("gtk-3.0", "gtk-4.0"):
                ini = Path(config_home) / ver / "settings.ini"
                upsert_gtk_ini(ini, plan["uiSpec"])
                written.append(str(ini))
        look_dir = Path(state_home) / "kuwai" / "look"
        look_dir.mkdir(parents=True, exist_ok=True)
        kitty_path = look_dir / "fonts-kitty.conf"
        tmp = kitty_path.with_name(f".{kitty_path.name}.{os.getpid()}.tmp")
        tmp.write_text(render_kitty_fonts(plan["monoFamily"]), encoding="utf-8")
        os.replace(tmp, kitty_path)
        written.append(str(kitty_path))
        if apply_live:
            if shutil.which("gsettings") and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
                if plan["uiSpec"]:
                    subprocess.run(
                        ["gsettings", "set", "org.gnome.desktop.interface", "font-name", plan["uiSpec"]],
                        stdin=subprocess.DEVNULL, capture_output=True, timeout=5,
                    )
                if plan["monoSpec"]:
                    subprocess.run(
                        ["gsettings", "set", "org.gnome.desktop.interface", "monospace-font-name", plan["monoSpec"]],
                        stdin=subprocess.DEVNULL, capture_output=True, timeout=5,
                    )
            if shutil.which("pkill"):
                subprocess.run(["pkill", "-USR1", "-x", "kitty"], stdin=subprocess.DEVNULL, capture_output=True)
    return {
        "ok": True,
        "dryRun": bool(dry_run),
        "plan": plan,
        "written": written,
    }
