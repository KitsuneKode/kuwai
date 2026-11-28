"""Parse Omarchy colors.toml as validated hex data and map into kuwai palette.toml."""
import json
import os
import re

HEX_LINE = re.compile(
    r"^([A-Za-z0-9_]+)\s*=\s*[\"']?(#[0-9A-Fa-f]{6})[\"']?(?:\s*#.*)?$"
)
MODE_LINE = re.compile(
    r"^mode\s*=\s*[\"']?(dark|light)[\"']?(?:\s*#.*)?$", re.I
)
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")

OMARCHY_COLOR_KEYS = frozenset({
    "accent", "selection", "muted",
    "background", "dark_background", "darker_background", "lighter_background",
    "foreground", "dark_foreground", "light_foreground", "bright_foreground",
    "red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan",
    "bright_blue", "bright_magenta",
    "bg", "fg", "dark_bg", "darker_bg", "lighter_bg",
    "dark_fg", "light_fg", "bright_fg",
})


class OmarchyParseError(ValueError):
    pass


def resolve_colors_path(source):
    path = os.path.abspath(os.path.expanduser(source))
    if os.path.isfile(path):
        if os.path.basename(path) != "colors.toml":
            raise OmarchyParseError("expected a colors.toml file path")
        return path
    if os.path.isdir(path):
        cand = os.path.join(path, "colors.toml")
        if not os.path.isfile(cand):
            raise OmarchyParseError("no colors.toml in directory")
        return cand
    raise OmarchyParseError("path not found")


def parse_colors_toml(path):
    colors = {}
    mode = ""
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            if line.lower() in ("[colors]", "[theme]"):
                continue
            raise OmarchyParseError("nested tables are not supported")
        mm = MODE_LINE.match(line)
        if mm:
            mode = mm.group(1).lower()
            continue
        m = HEX_LINE.match(line)
        if not m:
            if "=" in line:
                key_name = line.split("=", 1)[0].strip()
                if key_name in OMARCHY_COLOR_KEYS or key_name.startswith("color"):
                    raise OmarchyParseError(f"invalid value in colors.toml: {key_name}")
            continue
        key, hx = m.group(1), m.group(2).lower()
        if key not in OMARCHY_COLOR_KEYS and not key.startswith("color"):
            continue
        if not re.fullmatch(r"#[0-9a-f]{6}", hx):
            raise OmarchyParseError(f"invalid hex for {key}")
        colors[key] = hx
    if not colors.get("background") and not colors.get("bg"):
        raise OmarchyParseError("colors.toml needs background or bg")
    if not colors.get("foreground") and not colors.get("fg"):
        raise OmarchyParseError("colors.toml needs foreground or fg")
    if not colors.get("accent"):
        raise OmarchyParseError("colors.toml needs accent")
    return colors, mode or "dark"


def pick(colors, *keys, default=None):
    for k in keys:
        v = colors.get(k)
        if v:
            return v
    return default


def omarchy_to_raw(colors, mode):
    bg = pick(colors, "background", "bg")
    fg = pick(colors, "foreground", "fg")
    accent = colors["accent"]
    secondary = pick(colors, "green", "color2", "cyan", "color6", "blue", "color4", default=accent)
    tertiary = pick(colors, "magenta", "color5", "red", "color1", default=secondary)
    ansi = [
        pick(colors, "color0", default=bg),
        pick(colors, "red", "color1"),
        pick(colors, "green", "color2"),
        pick(colors, "yellow", "color3"),
        pick(colors, "blue", "color4"),
        pick(colors, "magenta", "color5"),
        pick(colors, "cyan", "color6"),
        pick(colors, "color7", default=fg),
        pick(colors, "color8", "muted", "dark_foreground", "dark_fg", default=bg),
        pick(colors, "bright_red", "color9", default=pick(colors, "red", "color1")),
        pick(colors, "bright_green", "color10", default=pick(colors, "green", "color2")),
        pick(colors, "bright_yellow", "color11", default=pick(colors, "yellow", "color3")),
        pick(colors, "bright_blue", "color12", default=pick(colors, "blue", "color4")),
        pick(colors, "bright_magenta", "color13", default=pick(colors, "magenta", "color5")),
        pick(colors, "bright_cyan", "color14", default=pick(colors, "cyan", "color6")),
        pick(colors, "bright_foreground", "bright_fg", "color15", default=fg),
    ]
    if any(not c for c in ansi):
        ansi = None
    return {
        "bg": bg,
        "fg": fg,
        "accent": accent,
        "secondary": secondary,
        "tertiary": tertiary,
        "ansi": ansi,
        "exactBg": True,
        "mode": mode,
    }


def render_palette_toml(raw):
    lines = ["[colors]", f'bg = "{raw["bg"]}"', f'fg = "{raw["fg"]}"', f'accent = "{raw["accent"]}"']
    if raw.get("secondary"):
        lines.append(f'secondary = "{raw["secondary"]}"')
    if raw.get("tertiary"):
        lines.append(f'tertiary = "{raw["tertiary"]}"')
    ansi = raw.get("ansi")
    if isinstance(ansi, list) and len(ansi) == 16 and all(ansi):
        lines.append("")
        lines.append("[ansi]")
        for i, c in enumerate(ansi):
            lines.append(f'color{i} = "{c}"')
    return "\n".join(lines) + "\n"


def render_theme_toml(slug, name, mode, accent):
    title = name or slug.replace("-", " ").title()
    return "\n".join([
        "schema = 1",
        f"slug = {json.dumps(str(slug))}",
        f"name = {json.dumps(str(title))}",
        f"mode = {json.dumps(str(mode))}",
        f"accent = {json.dumps(str(accent))}",
        "",
    ])


def derive_slug(source, slug=None):
    if slug:
        cand = slug
    else:
        path = os.path.abspath(os.path.expanduser(source))
        base = os.path.basename(path.rstrip(os.sep))
        if base == "colors.toml":
            base = os.path.basename(os.path.dirname(path))
        cand = base
    cand = re.sub(r"[^a-z0-9._-]+", "-", cand.lower()).strip(".-")
    if not SLUG_RE.match(cand):
        raise OmarchyParseError(f"invalid theme slug: {cand!r}")
    return cand


def load_omarchy(path):
    colors_path = resolve_colors_path(path)
    colors, mode = parse_colors_toml(colors_path)
    if mode == "dark" and os.path.isfile(os.path.join(os.path.dirname(colors_path), "light.mode")):
        mode = "light"
    raw = omarchy_to_raw(colors, mode)
    return {
        "colorsPath": colors_path,
        "raw": raw,
        "paletteToml": render_palette_toml(raw),
        "mode": mode,
    }