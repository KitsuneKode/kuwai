"""Palette extraction from images (matugen primary, ImageMagick fallback, cached by SHA-256)."""
import colorsys
import hashlib
import json
import os
import re
import shutil
import subprocess

HEX_RE = re.compile(r"#([0-9a-fA-F]{6})\b")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hex(r, g, b):
    return "#{:02x}{:02x}{:02x}".format(
        max(0, min(255, round(r * 255))),
        max(0, min(255, round(g * 255))),
        max(0, min(255, round(b * 255))),
    )


def _extract_matugen(path, mode):
    exe = shutil.which("matugen")
    if not exe:
        return None
    m = "light" if mode == "light" else "dark"
    r = subprocess.run(
        [exe, "image", "--json", "hex", "--mode", m, path],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
    )
    if r.returncode != 0 or not r.stdout.strip():
        return None
    try:
        data = json.loads(r.stdout)
    except ValueError:
        return None
    colors = data.get("colors") or {}
    bucket = colors.get(m) or colors.get("dark") or colors
    if not isinstance(bucket, dict):
        return None

    def pick(*keys):
        for k in keys:
            v = bucket.get(k)
            if isinstance(v, dict):
                v = v.get(m) or v.get("default")
            if isinstance(v, str) and HEX_RE.fullmatch(v.strip()):
                return v.strip().lower()
        return None

    primary = pick("primary")
    surface = pick("background", "surface", "surface_dim")
    if not primary:
        return None
    swatches = [c for c in (
        pick("background", "surface"),
        pick("surface_container", "surface_variant"),
        primary,
        pick("secondary"),
        pick("tertiary"),
        pick("outline"),
    ) if c]
    return {
        "extractor": "matugen",
        "bg": surface,
        "surface": pick("surface_container", "surface_container_low", "surface"),
        "fg": pick("on_background", "on_surface"),
        "accent": primary,
        "secondary": pick("secondary"),
        "tertiary": pick("tertiary"),
        "swatches": swatches,
    }


def _extract_magick(path):
    exe = shutil.which("magick") or shutil.which("convert")
    if not exe:
        return None
    r = subprocess.run(
        [exe, path + "[0]", "-resize", "96x96!", "-colors", "10", "-unique-colors", "txt:-"],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15,
    )
    if r.returncode != 0:
        return None
    found = []
    for line in r.stdout.splitlines():
        m = HEX_RE.search(line)
        if m:
            hx = "#" + m.group(1).lower()
            if hx not in found:
                found.append(hx)
    if not found:
        return None
    scored = []
    for hx in found:
        rgb = hex_to_rgb(hx)
        h, l, s = colorsys.rgb_to_hls(*rgb)
        scored.append((hx, h, l, s))
    by_sat = sorted(scored, key=lambda x: (x[3] * (1.0 - abs(x[2] - 0.55)), x[3]), reverse=True)
    by_luma = sorted(scored, key=lambda x: x[2])
    accent = by_sat[0][0]
    secondary = by_sat[1][0] if len(by_sat) > 1 else accent
    tertiary = by_sat[2][0] if len(by_sat) > 2 else secondary
    darkest = by_luma[0][0]
    return {
        "extractor": "magick",
        "bg": darkest,
        "surface": by_luma[min(1, len(by_luma) - 1)][0],
        "fg": None,
        "accent": accent,
        "secondary": secondary,
        "tertiary": tertiary,
        "swatches": [x[0] for x in scored[:6]],
    }


def top_strip_luma(path):
    """Measure mean luminance (0..1) of the top 5% strip of an image for lock/notch ink."""
    exe = shutil.which("magick") or shutil.which("convert")
    if not exe or not path or not os.path.isfile(path):
        return None
    r = subprocess.run(
        [exe, path + "[0]", "-gravity", "North", "-crop", "100%x5%+0+0", "+repage",
         "-colorspace", "Gray", "-resize", "1x1!", "-format", "%[fx:mean]", "info:"],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10,
    )
    if r.returncode != 0:
        return None
    try:
        v = float(r.stdout.strip())
        return max(0.0, min(1.0, round(v, 4)))
    except ValueError:
        return None


def extract_image(path, mode="dark", cache_dir=None):
    """Extract raw palette candidates from an image file, cached by SHA-256."""
    real = os.path.realpath(path)
    digest = sha256_file(real)
    cache_path = None
    if cache_dir:
        os.makedirs(cache_dir, exist_ok=True)
        cache_path = os.path.join(cache_dir, f"{digest}-{mode}.json")
        if os.path.isfile(cache_path):
            try:
                with open(cache_path, encoding="utf-8") as f:
                    return json.load(f)
            except (OSError, ValueError):
                pass
    raw = _extract_matugen(real, mode) or _extract_magick(real) or {
        "extractor": "fallback",
        "bg": "#111114",
        "surface": "#18181d",
        "fg": "#f4f4f6",
        "accent": "#66c7ff",
        "secondary": "#86e0b4",
        "tertiary": "#ff7a98",
        "swatches": ["#111114", "#18181d", "#66c7ff", "#86e0b4", "#ff7a98", "#f4f4f6"],
    }
    raw["sha256"] = digest
    luma = top_strip_luma(real)
    if luma is not None:
        raw["topLuma"] = luma
    if cache_path:
        tmp = cache_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(raw, f, indent=2)
        os.replace(tmp, cache_path)
    return raw
