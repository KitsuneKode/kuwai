"""Can the lock screen's clock be read over this wallpaper?

The island and its panels bring their own ground (94 % black), so a wallpaper
cannot make their text unreadable (lib/rehearse/gate.py measures that ground
at its lightest). The lock screen's date and clock have no ground of their
own: they sit on the wallpaper as the lock shows it. This models that layer
from shell/modules/lock/LockView.qml and measures the text against it:

    the wallpaper, cover-cropped to the screen, blurred (MultiEffect blur 1,
    blurMax 48), under a 22 % black scrim;
    the date (26 px semibold) and clock (150 px bold) centred, from 11 % of the
    screen's height, in white at 90 % tinted 35 % toward the accent.

Both are large text: 3:1 is the line (WCAG 2.2). The figure reported is the
contrast that 95 % of the area behind the text meets or beats, so a small
bright spot does not fail a wallpaper and a bright band does.

    from rehearse import wall
    wall.lock_clock(path)  ->  {"bare": 1.4, "shade": 0.44, "clock": 3.6, "calm": False, "ok": True}

`bare` is what the lock gave before shell/modules/lock/ClockGround.qml: that
component reads the wallpaper behind the clock and darkens the top of the
screen only as much as it takes. This file models the same rule, so a
wallpaper can be judged without a lock screen (bin/kuwai-rehearse --wall).
"""
from __future__ import annotations

from . import gate

SCRIM = 0.22
TEXT_ALPHA = 0.9
ACCENT_SHARE = 0.35
LINE = gate.READABLE_LARGE
DATE = (0.40, 0.105, 0.60, 0.14)
CLOCK = (0.33, 0.14, 0.67, 0.295)
SIZE = (480, 270)


def lock_layer(path):
    """The wallpaper as the lock screen shows it behind its clock."""
    from PIL import Image, ImageFilter
    img = Image.open(path).convert("RGB")
    w, h = img.size
    want = SIZE[0] / SIZE[1]
    if w / h > want:
        cut = round((w - h * want) / 2)
        img = img.crop((cut, 0, w - cut, h))
    else:
        cut = round((h - w / want) / 2)
        img = img.crop((0, cut, w, h - cut))
    img = img.resize(SIZE, Image.LANCZOS).filter(ImageFilter.GaussianBlur(48 * SIZE[1] / 1080))
    return img.point(lambda v: round(v * (1 - SCRIM)))


def _ink(accent):
    a = gate.rgba(accent)
    return tuple(1 * (1 - ACCENT_SHARE) + a[i] * ACCENT_SHARE for i in range(3))


def _met_by_most(layer, area, ink):
    """The contrast 95 % of `area` meets or beats."""
    w, h = layer.size
    px = layer.load()
    ratios = []
    for y in range(round(area[1] * h), max(round(area[1] * h) + 1, round(area[3] * h))):
        for x in range(round(area[0] * w), round(area[2] * w)):
            bg = tuple(v / 255 for v in px[x, y])
            fg = tuple(ink[i] * TEXT_ALPHA + bg[i] * (1 - TEXT_ALPHA) for i in range(3))
            ratios.append(gate.contrast(fg, bg))
    ratios.sort()
    return ratios[len(ratios) // 20]


WANT, MOST = 3.5, 0.62
ZONE = (0.33, 0.10, 0.67, 0.30)


def shade_for(bright, ink):
    """ClockGround's rule: the least total darkening (the scrim included) that
    brings ink over a ground this bright to WANT, capped at MOST."""
    s = SCRIM
    while s <= MOST + 0.001:
        v = bright * (1 - s)
        if gate.contrast(ink, (v, v, v)) >= WANT:
            return s
        s += 0.02
    return MOST


def lock_clock(path, accent="#0a84ff"):
    """`bare`: the contrast with the scrim alone (what the lock had). `shade`:
    how much ClockGround darkens the top for it (0 over a dark picture).
    `clock`: the contrast with that shade. A wallpaper that needs a deep
    shade is a poor default even when it passes: `calm` is shade under 35 %."""
    from PIL import Image
    ink = _ink(accent)
    layer = lock_layer(path)
    bare = min(_met_by_most(layer, CLOCK, ink), _met_by_most(layer, DATE, ink))
    small = Image.open(path).convert("RGB").resize((32, 18), Image.BILINEAR)
    px = small.load()
    tones = sorted(max(px[x, y]) / 255 for y in range(int(ZONE[1] * 18), max(int(ZONE[1] * 18) + 1, -(-int(ZONE[3] * 18 * 100) // 100)))
                   for x in range(int(ZONE[0] * 32), int(ZONE[2] * 32) + 1))
    bright = tones[min(len(tones) - 1, int(len(tones) * 0.95))]
    total = shade_for(bright, ink)
    v = bright * (1 - total)
    after = gate.contrast(tuple(ink[i] * TEXT_ALPHA + v * (1 - TEXT_ALPHA) for i in range(3)), (v, v, v))
    shade = max(0.0, 1 - (1 - total) / (1 - SCRIM))
    return {"bare": round(bare, 2), "clock": round(after, 2), "shade": round(shade, 2),
            "calm": shade < 0.35, "ok": after >= LINE}
