"""Render schema-1 palette into consumer files and atomically swap look/current."""
import json
import os
import re
import shutil
import time

TPL_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}")


def flatten(data, prefix=""):
    out = {}
    if isinstance(data, dict):
        for k, v in data.items():
            key = f"{prefix}.{k}" if prefix else str(k)
            if isinstance(v, (dict, list)):
                out.update(flatten(v, key))
            else:
                out[key] = str(v)
                if isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v):
                    out[key + ".strip"] = v[1:]
    elif isinstance(data, list):
        for i, v in enumerate(data):
            key = f"{prefix}.{i}"
            out[key] = str(v)
            if isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v):
                out[key + ".strip"] = v[1:]
    return out


def render_template(text, tokens):
    def repl(m):
        key = m.group(1)
        if key not in tokens:
            raise KeyError(f"unknown palette template key: {key}")
        return tokens[key]

    return TPL_RE.sub(repl, text)


def render_lua(palette):
    r = palette["role"]
    src = palette.get("source") or {}
    name = (src.get("name") or src.get("kind") or "kuwai").replace("\\", "\\\\").replace('"', '\\"')
    lines = [
        "return {",
        f'    schema = 1,',
        f'    generation = "{palette["generation"]}",',
        f'    mode = "{palette["mode"]}",',
        f'    name = "{name}",',
        "    role = {",
    ]
    for k in ("bg", "surface", "fg", "fgDim", "accent", "accentSoft", "onAccent", "border", "selection"):
        hx = r[k].lstrip("#")
        lines.append(f'        {k} = "{hx}",')
    lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_kitty(palette):
    r = palette["role"]
    ansi = palette["ansi"]
    lines = [
        f"background {r['bg']}",
        f"foreground {r['fg']}",
        f"cursor {r['accent']}",
        f"cursor_text_color {r['onAccent']}",
        f"selection_background {r['selection']}",
        f"selection_foreground {r['fg']}",
        f"url_color {r['accent']}",
        f"active_border_color {r['accent']}",
        f"inactive_border_color {r['border']}",
        f"active_tab_background {r['accent']}",
        f"active_tab_foreground {r['onAccent']}",
        f"inactive_tab_background {r['surface']}",
        f"inactive_tab_foreground {r['fgDim']}",
    ]
    for i, c in enumerate(ansi):
        lines.append(f"color{i} {c}")
    return "\n".join(lines) + "\n"


def render_gtk_css(palette):
    r = palette["role"]
    return "\n".join([
        f"@define-color accent_bg_color {r['accent']};",
        f"@define-color accent_fg_color {r['onAccent']};",
        f"@define-color accent_color {r['accent']};",
        f"@define-color window_bg_color {r['bg']};",
        f"@define-color window_fg_color {r['fg']};",
        f"@define-color view_bg_color {r['surface']};",
        f"@define-color view_fg_color {r['fg']};",
        f"@define-color headerbar_bg_color {r['surface']};",
        f"@define-color headerbar_fg_color {r['fg']};",
        f"@define-color card_bg_color {r['surface']};",
        f"@define-color card_fg_color {r['fg']};",
        f"@define-color popover_bg_color {r['surface']};",
        f"@define-color popover_fg_color {r['fg']};",
        "",
    ])


def render_qtct(palette):
    r = palette["role"]
    fg = "#ff" + r["fg"].lstrip("#")
    bg = "#ff" + r["bg"].lstrip("#")
    surf = "#ff" + r["surface"].lstrip("#")
    dim = "#ff" + r["fgDim"].lstrip("#")
    acc = "#ff" + r["accent"].lstrip("#")
    on_acc = "#ff" + r["onAccent"].lstrip("#")
    bord = "#ff" + r["border"].lstrip("#")
    active = ", ".join([
        fg, surf, bord, bord, bg, bord, fg, fg, fg, surf, bg, bg, acc, on_acc, acc, acc, bg, fg, surf, fg, dim,
    ])
    disabled = ", ".join([
        dim, surf, bord, bord, bg, bord, dim, fg, dim, surf, bg, bg, surf, dim, acc, acc, bg, fg, surf, fg, dim,
    ])
    return f"[ColorScheme]\nactive_colors={active}\ndisabled_colors={disabled}\ninactive_colors={active}\n"


def write_generation(look_dir, palette, custom_templates_dir=None, keep=3):
    """Write a complete generation directory, swap look/current atomically, and prune old generations."""
    os.makedirs(look_dir, exist_ok=True)
    gen_name = f"gen-{palette['generation']}"
    gen_dir = os.path.join(look_dir, gen_name)
    os.makedirs(gen_dir, exist_ok=True)

    outputs = {
        "palette.json": json.dumps(palette, indent=2) + "\n",
        "palette.lua": render_lua(palette),
        "kitty.conf": render_kitty(palette),
        "gtk.css": render_gtk_css(palette),
        "qtct.conf": render_qtct(palette),
    }

    if custom_templates_dir and os.path.isdir(custom_templates_dir):
        tokens = flatten(palette)
        for name in sorted(os.listdir(custom_templates_dir)):
            if not name.endswith(".tpl"):
                continue
            src = os.path.join(custom_templates_dir, name)
            if not os.path.isfile(src) or os.path.islink(src):
                continue
            target = name[:-4]
            if not target or "/" in target or target.startswith("."):
                continue
            outputs[target] = render_template(open(src, encoding="utf-8").read(), tokens)

    for fname, content in outputs.items():
        with open(os.path.join(gen_dir, fname), "w", encoding="utf-8") as f:
            f.write(content)

    current_link = os.path.join(look_dir, "current")
    prev_target = os.readlink(current_link) if os.path.islink(current_link) else None
    tmp_link = os.path.join(look_dir, f".current-{os.getpid()}-{time.time_ns()}")
    os.symlink(gen_name, tmp_link)
    os.replace(tmp_link, current_link)

    state = {
        "schema": 1,
        "generation": palette["generation"],
        "previous": prev_target if prev_target and prev_target != gen_name else None,
        "mode": palette["mode"],
        "theme": (palette.get("source") or {}).get("name") or "",
        "wallpaper": (palette.get("source") or {}).get("wallpaper") or "",
        "at": int(time.time()),
    }
    tmp_state = os.path.join(look_dir, ".state.json.tmp")
    with open(tmp_state, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
        f.write("\n")
    os.replace(tmp_state, os.path.join(look_dir, "state.json"))

    gens = sorted(
        (d for d in os.listdir(look_dir) if d.startswith("gen-") and os.path.isdir(os.path.join(look_dir, d))),
        key=lambda d: os.path.getmtime(os.path.join(look_dir, d)),
    )
    protected = {gen_name, prev_target}
    for old in gens[:-keep]:
        if old not in protected:
            shutil.rmtree(os.path.join(look_dir, old), ignore_errors=True)
    return gen_dir, state
