"""Semantic role derivation, WCAG contrast enforcement, and ANSI 16 palette synthesis."""
import colorsys
import re

HEX_RE = re.compile(r"^#?[0-9a-fA-F]{6}$")

DEFAULT_ROLES = {
    "bg": "#111114",
    "surface": "#18181d",
    "fg": "#f4f4f6",
    "fgDim": "#a1a1aa",
    "accent": "#66c7ff",
    "accentSoft": "#3898d4",
    "onAccent": "#000000",
    "border": "#3f3f46",
    "selection": "#264f78",
}


def norm_hex(value, fallback="#000000"):
    if not isinstance(value, str):
        return fallback
    v = value.strip()
    if not HEX_RE.fullmatch(v):
        return fallback
    return ("#" + v.lstrip("#")).lower()


def hex_to_rgb(h):
    h = norm_hex(h).lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hex(r, g, b):
    return "#{:02x}{:02x}{:02x}".format(
        max(0, min(255, round(r * 255))),
        max(0, min(255, round(g * 255))),
        max(0, min(255, round(b * 255))),
    )


def relative_luminance(hx):
    def lin(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = hex_to_rgb(hx)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast_ratio(a, b):
    la = relative_luminance(a)
    lb = relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def best_ink(bg):
    return "#000000" if contrast_ratio("#000000", bg) >= contrast_ratio("#ffffff", bg) else "#ffffff"


def mix(a, b, t):
    ar, ag, ab = hex_to_rgb(a)
    br, bg_, bb = hex_to_rgb(b)
    return rgb_to_hex(ar + (br - ar) * t, ag + (bg_ - ag) * t, ab + (bb - ab) * t)


def vivid_accent(hx, dark=True):
    r, g, b = hex_to_rgb(hx)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if s < 0.12:
        nl = max(0.62, min(0.80, l)) if dark else max(0.24, min(0.42, l))
        return rgb_to_hex(*colorsys.hls_to_rgb(0.0, nl, 0.0))
    ns = max(0.58, min(0.92, s))
    nl = max(0.60, min(0.74, l)) if dark else max(0.32, min(0.46, l))
    return rgb_to_hex(*colorsys.hls_to_rgb(h, nl, ns))


def ensure_contrast(fg, bg, target, dark=True):
    """Adjust lightness of fg along its hue until contrast_ratio(fg, bg) >= target."""
    if contrast_ratio(fg, bg) >= target:
        return norm_hex(fg)
    r, g, b = hex_to_rgb(fg)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    lo, hi = (l, 0.98) if dark else (0.02, l)
    best = "#ffffff" if dark else "#000000"
    for _ in range(18):
        mid = (lo + hi) / 2.0
        cand = rgb_to_hex(*colorsys.hls_to_rgb(h, mid, s))
        if contrast_ratio(cand, bg) >= target:
            best = cand
            if dark:
                hi = mid
            else:
                lo = mid
        else:
            if dark:
                lo = mid
            else:
                hi = mid
    if contrast_ratio(best, bg) < target:
        return "#ffffff" if dark else "#000000"
    return best


def clamp_ground(hx, dark=True):
    """Keep desktop surfaces calm and low-chroma while preserving hue tint."""
    r, g, b = hex_to_rgb(hx)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if dark:
        return rgb_to_hex(*colorsys.hls_to_rgb(h, max(0.05, min(0.11, l)), min(s, 0.22)))
    return rgb_to_hex(*colorsys.hls_to_rgb(h, max(0.92, min(0.97, l)), min(s, 0.14)))


def build_ansi(bg, fg, accent, secondary=None, tertiary=None, dark=True):
    """Synthesize a readable 16-color ANSI palette harmonised with bg/fg/accent."""
    sec = vivid_accent(secondary or "#86e0b4", dark=dark)
    ter = vivid_accent(tertiary or "#ff7a98", dark=dark)
    base = [
        mix(bg, fg, 0.08),
        ensure_contrast("#f38ba8" if dark else "#c93b5b", bg, 4.5, dark=dark),
        ensure_contrast(sec, bg, 4.5, dark=dark),
        ensure_contrast("#f9e2af" if dark else "#9a6700", bg, 4.5, dark=dark),
        ensure_contrast(accent, bg, 4.5, dark=dark),
        ensure_contrast(ter, bg, 4.5, dark=dark),
        ensure_contrast("#74c7ec" if dark else "#0969da", bg, 4.5, dark=dark),
        mix(bg, fg, 0.82),
    ]
    bright = [
        mix(bg, fg, 0.34),
        mix(base[1], fg, 0.18),
        mix(base[2], fg, 0.18),
        mix(base[3], fg, 0.18),
        mix(base[4], fg, 0.18),
        mix(base[5], fg, 0.18),
        mix(base[6], fg, 0.18),
        fg,
    ]
    return base + bright


def build_palette(raw, source, generation, mode="dark"):
    """Build a schema-1 kuwai palette dict from extracted or theme colors."""
    effective_mode = mode
    if mode == "auto":
        luma = raw.get("topLuma")
        if luma is None and raw.get("bg"):
            luma = relative_luminance(raw["bg"])
        effective_mode = "light" if (luma is not None and luma > 0.62) else "dark"
    dark = effective_mode != "light"

    raw_bg = norm_hex(raw.get("bg"), "#111114" if dark else "#f4f4f7")
    bg = raw_bg if source.get("kind") == "theme" and raw.get("exactBg") else clamp_ground(raw_bg, dark=dark)
    surface = mix(bg, "#ffffff" if dark else "#000000", 0.06)
    fg = ensure_contrast(norm_hex(raw.get("fg"), "#f4f4f6" if dark else "#111114"), bg, 7.0, dark=dark)
    fg_dim = ensure_contrast(mix(bg, fg, 0.68), bg, 4.5, dark=dark)
    accent = ensure_contrast(vivid_accent(norm_hex(raw.get("accent"), "#66c7ff"), dark=dark), bg, 3.5, dark=dark)
    accent_soft = mix(bg, accent, 0.55)
    on_accent = best_ink(accent)
    border = mix(bg, fg, 0.22)
    selection = mix(bg, accent, 0.30)

    roles = {
        "bg": bg,
        "surface": surface,
        "fg": fg,
        "fgDim": fg_dim,
        "accent": accent,
        "accentSoft": accent_soft,
        "onAccent": on_accent,
        "border": border,
        "selection": selection,
    }
    swatches = []
    for c in [bg, surface, accent, raw.get("secondary"), raw.get("tertiary"), fg]:
        if c and HEX_RE.fullmatch(str(c).strip()):
            hx = norm_hex(c)
            if hx not in swatches:
                swatches.append(hx)
    ansi = raw.get("ansi") if isinstance(raw.get("ansi"), list) and len(raw.get("ansi")) == 16 else build_ansi(
        bg, fg, accent, raw.get("secondary"), raw.get("tertiary"), dark=dark
    )
    top_luma = raw.get("topLuma")
    if top_luma is None:
        top_luma = round(relative_luminance(bg), 4)
    wall_ink = "#000000" if top_luma > 0.52 else "#ffffff"

    return {
        "schema": 1,
        "generation": generation,
        "mode": effective_mode,
        "source": source,
        "role": roles,
        "swatches": swatches,
        "ansi": [norm_hex(c) for c in ansi],
        "wall": {"topLuma": top_luma, "ink": wall_ink},
    }
