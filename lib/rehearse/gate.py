"""The rehearsal's rules: what makes a staged frame wrong, measured.

A frame is what tests/ui/rehearse.qml wrote down about one panel in one state
(every text with its box, size and colour; every click target; every scrolling
area) and, when there is one, its picture. `judge` returns the faults a person
would see on it. Two kinds:

  fail   wrong whoever looks: text cut off or on top of other text, text that
         can't be read, a target too small to hit, a panel taller than the
         island can show, the program's insides shown as words.
  look   worth a person's eye on the contact sheet, never a verdict alone: a
         large empty band, a little too many type sizes, lopsided insets.

Nothing here knows a panel by name. A rule that needs an exception gets it from
what the frame says about itself (a scene of worst-case data may elide; a
scrolling area may hold more than it shows), not from a list of files.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

MIN_TYPE = 10          # px at text scale 1; docs/DESIGN.md's smallest label
MIN_TARGET = 24        # px; WCAG 2.2 "Target Size (Minimum)"
READABLE = 4.5         # WCAG 2.2 contrast for text
READABLE_LARGE = 3.0   # the same for large text (24 px, or 18.66 px bold)
FAINT = 3.0            # under this even a hint or a disabled label is lost
ISLAND = (1080, 600)   # the most the island gives a panel on a 1080p screen

# Words that are the program talking to itself: a helper's name, an exit
# status, a value that never got filled in.
INSIDES = re.compile(r"\bkuwai-[a-z]{3,}\b|\bexit(?:ed)?(?: with| code| status)? \d+\b|\(exit \d+\)|\bundefined\b|\bNaN\b|\[object |\bqs ipc\b")
GAVE_UP = re.compile(r"\b(?:didn'?t|couldn'?t|can'?t|failed|unable)\b", re.I)
MONO_FONT = re.compile(r"mono|courier|consol", re.I)
GLYPH_FONT = re.compile(r"symbols|nerd|icon|material|glyph", re.I)


@dataclass(frozen=True)
class Fault:
    scene: str
    rule: str
    level: str            # "fail" | "look"
    what: str             # one line a person can act on
    box: tuple | None     # where on the frame, for the contact sheet

    @property
    def key(self) -> str:
        """How the known list names it. Figures in the remark are written 0:
        "57 min ago" is "58 min ago" a moment later, and a fault is the same
        fault whatever the clock says."""
        return f"{self.scene} | {self.rule} | {re.sub(r'[0-9]+', '0', self.what)}"


def _inter(a, b):
    x, y = max(a[0], b[0]), max(a[1], b[1])
    return (x, y, max(0.0, min(a[0] + a[2], b[0] + b[2]) - x), max(0.0, min(a[1] + a[3], b[1] + b[3]) - y))


def _outside(box, frame, slack=1.5):
    """How far `box` runs out of `frame` on each side: (left, top, right, bottom)."""
    return (max(0.0, frame[0] - box[0] - slack), max(0.0, frame[1] - box[1] - slack),
            max(0.0, box[0] + box[2] - frame[0] - frame[2] - slack), max(0.0, box[1] + box[3] - frame[1] - frame[3] - slack))


def is_glyph(text) -> bool:
    """An icon set as text: an icon font, or nothing but private-use characters."""
    s = text.get("t", "")
    if GLYPH_FONT.search(text.get("family", "")):
        return True
    return bool(s) and all(0xE000 <= ord(c) <= 0xF8FF or ord(c) >= 0xF0000 or c.isspace() for c in s)


def rgba(colour: str):
    """Qt's "#rrggbb" / "#aarrggbb" as (r, g, b, a) in 0–1."""
    c = colour.lstrip("#")
    if len(c) == 8:
        a, c = int(c[:2], 16) / 255, c[2:]
    else:
        a = 1.0
    return (int(c[0:2], 16) / 255, int(c[2:4], 16) / 255, int(c[4:6], 16) / 255, a)


def _lum(rgb):
    def lin(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])


def contrast(fg, bg) -> float:
    """WCAG contrast ratio of two opaque colours (r, g, b in 0–1)."""
    a, b = _lum(fg), _lum(bg)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def ground(image, box):
    """The colour a text sits on: the commonest colour in a thin ring just
    outside its box (its own strokes are inside; a neighbour is rarely the
    majority). (r, g, b) in 0–1, or None when the box is off the picture."""
    w, h = image.size
    x0, y0 = int(box[0]) - 3, int(box[1]) - 3
    x1, y1 = int(box[0] + box[2]) + 3, int(box[1] + box[3]) + 3
    px = image.load()
    seen = {}
    for y in range(max(0, y0), min(h, y1 + 1)):
        for x in range(max(0, x0), min(w, x1 + 1)):
            if x0 + 2 < x < x1 - 2 and y0 + 2 < y < y1 - 2:
                continue
            p = px[x, y][:3]
            q = (p[0] >> 2, p[1] >> 2, p[2] >> 2)
            n, sr, sg, sb = seen.get(q, (0, 0, 0, 0))
            seen[q] = (n + 1, sr + p[0], sg + p[1], sb + p[2])
    if not seen:
        return None
    n, r, g, b = max(seen.values())
    return (r / n / 255, g / n / 255, b / n / 255)


def _shown(text):
    """The part of a text's drawn box that its clip lets through."""
    return _inter(text["box"], text["clip"]) if text.get("clip") else tuple(text["box"])


def _label(text) -> str:
    s = " ".join(text["t"].split())
    return '"' + (s[:40] + "…" if len(s) > 40 else s) + '"'


def judge(frame: dict, image=None) -> list[Fault]:
    scene, scale = frame["id"], float(frame.get("scale", 1) or 1)
    panel = (0.0, 0.0, float(frame["w"]), float(frame["h"]))
    worst = frame.get("kind") == "worst"
    out: list[Fault] = []

    def add(rule, level, what, box=None):
        out.append(Fault(scene, rule, level, what, tuple(box) if box else None))

    wants = frame.get("wants") or [frame["w"], frame["h"]]
    if wants[1] > ISLAND[1] + 0.5 or wants[0] > ISLAND[0] + 0.5:
        add("too-big", "fail", f"wants {wants[0]:.0f} x {wants[1]:.0f}, the island gives at most {ISLAND[0]} x {ISLAND[1]}")

    texts = [t for t in frame.get("texts", []) if t["box"][2] > 0.5 and t["box"][3] > 0.5 and t.get("op", 1) >= 0.05]
    seen = []
    for t in texts:
        box, glyph = t["box"], is_glyph(t)
        frame_of = t["clip"] or panel
        if t.get("scroll") and t.get("clip"):
            shown = _inter(box, t["clip"])
            if shown[2] <= 0.5 or shown[3] <= 0.5:
                continue                              # scrolled away: not on the frame
            left, _, right, _ = _outside(box, t["clip"])
            if left or right:
                add("cut-off", "fail", f"{_label(t)} is cut at the side of its scrolling area by {max(left, right):.0f} px", shown)
        else:
            over = _outside(box, frame_of)
            if any(over):
                side = ["left", "top", "right", "bottom"][max(range(4), key=lambda i: over[i])]
                add("cut-off", "fail", f"{_label(t)} runs {max(over):.0f} px past the {side} of {'its clip' if t['clip'] else 'the panel'}", _inter(box, panel))
        if t.get("cut") and not worst and not glyph:
            add("shortened", "fail", f"{_label(t)} is shortened with an ellipsis though its content is ordinary", _shown(t))
        if not t.get("cut") and not t.get("elides") and not t.get("wraps") and t["own"][2] > 0.5 and box[2] > t["own"][2] + 1.5:
            add("spills", "fail", f"{_label(t)} is {box[2] - t['own'][2]:.0f} px wider than the room it was given and neither wraps nor shortens", _shown(t))
        if not glyph and t["size"] < MIN_TYPE * scale - 0.01:
            add("small-type", "fail", f"{_label(t)} is set at {t['size']:g} px (the smallest is {MIN_TYPE * scale:g})", _shown(t))
        if glyph and t.get("drawn") and t["drawn"] != t.get("family"):
            add("missing-font", "fail", f"an icon asks for the font {t['family']} and was drawn in {t['drawn']}: it shows as stray letters or a box", _shown(t))
        # Text set in the code face is shown as code on purpose (a command to
        # copy, a log): the frame says so itself. The rule is for prose.
        if not glyph and not MONO_FONT.search(t.get("family", "")) and INSIDES.search(t["t"]):
            add("insides", "fail", f"{_label(t)} shows the program's insides (a helper's name, an exit status, an empty value)", _shown(t))
        if t.get("op", 1) >= 0.9:
            mine = _shown(t)
            for other, theirs in seen:
                hit = _inter(mine, theirs)
                if hit[2] > 2 and hit[3] > 2:
                    add("on-top", "fail", f"{_label(t)} is drawn over {_label(other)}", hit)
            seen.append((t, mine))
        if image is not None and not glyph:
            bg = ground(image, _shown(t))
            if bg is not None:
                r, g, b, a = rgba(t["color"])
                a *= t.get("op", 1)
                fg = (r * a + bg[0] * (1 - a), g * a + bg[1] * (1 - a), b * a + bg[2] * (1 - a))
                ratio = contrast(fg, bg)
                large = t["size"] >= 24 * scale or (t["size"] >= 18.66 * scale and t.get("weight", 400) >= 600)
                need = READABLE_LARGE if large else READABLE
                if ratio < FAINT:
                    add("unreadable", "fail", f"{_label(t)} has {ratio:.1f}:1 against what is under it", _shown(t))
                elif ratio < need and t.get("on", True):
                    add("faint", "look", f"{_label(t)} has {ratio:.1f}:1 against what is under it (text wants {need:g}:1)", _shown(t))

    for g in frame.get("targets", []):
        box = _inter(g["box"], g["clip"]) if g.get("clip") else tuple(g["box"])
        if box[2] <= 0.5 or box[3] <= 0.5:
            continue
        if g.get("scroll") and box[2] * box[3] < g["box"][2] * g["box"][3] - 1:
            continue                                  # partly scrolled out: it is whole when scrolled to
        if min(box[2], box[3]) < MIN_TARGET - 0.5:
            add("small-target", "fail", f"a click target is {box[2]:.0f} x {box[3]:.0f} px (the smallest is {MIN_TARGET})", box)

    words = [t for t in texts if not is_glyph(t)]
    said = sum(len(t["t"].split()) for t in words)
    if said < 3:
        add("says-nothing", "fail", "the panel has %s on it: an empty state says what is missing and what to do" % ("no words" if not said else f"{said} word{'s' if said > 1 else ''}"))
    if frame.get("waiting") and any(GAVE_UP.search(t["t"]) for t in words):
        add("waits-forever", "fail", "loading placeholders are still shown beside a message that the loading failed")

    sizes = sorted({t["size"] for t in texts if not is_glyph(t)})
    if len(sizes) > 6:
        add("many-sizes", "look", "type is set in %d sizes (%s px)" % (len(sizes), ", ".join(f"{s:g}" for s in sizes)))

    if image is not None:
        out.extend(_cut_rows(frame, texts, image))
        out.extend(_look_at(frame, image))
    return out


def _cut_rows(frame, texts, image) -> list[Fault]:
    """A scrolling list that ends on a line of text cut through its middle,
    still at full strength: it reads as broken. A list with more below fades
    into its panel (components/ScrollFade), so the cut line is nearly gone
    where it meets the edge. One fault per list edge."""
    w, h = image.size
    px = image.load()
    base = px[w // 2, 2][:3]
    ground = tuple(v / 255 for v in base)
    seen, out = set(), []
    for t in texts:
        clip = t.get("clip")
        if not (t.get("scroll") and clip) or is_glyph(t):
            continue
        box = t["box"]
        top, foot = max(box[1], clip[1]), min(box[1] + box[3], clip[1] + clip[3])
        shown = foot - top
        if shown < 3 or shown > box[3] * 0.8:
            continue                                   # scrolled away, or (nearly) whole
        at_foot = box[1] + box[3] > clip[1] + clip[3]
        edge = (round(clip[0]), round(clip[1] + (clip[3] if at_foot else 0)))
        if edge in seen:
            continue
        x0, x1 = max(0, int(max(box[0], clip[0]))), min(w, int(min(box[0] + box[2], clip[0] + clip[2])))
        y0, y1 = max(0, int(top)), min(h, int(foot))
        strongest = 1.0
        for y in range(y0, y1):
            for x in range(x0, x1):
                strongest = max(strongest, contrast(tuple(v / 255 for v in px[x, y][:3]), ground))
        if strongest >= FAINT:
            seen.add(edge)
            out.append(Fault(frame["id"], "cut-row", "fail",
                             f"{_label(t)} is cut through at the {'foot' if at_foot else 'top'} of its list at full strength: a list with more that way fades into the panel",
                             (x0, y0, x1 - x0, y1 - y0)))
    return out


def _look_at(frame, image) -> list[Fault]:
    """What only the picture shows: a large band of nothing, lopsided insets."""
    scene, w, h = frame["id"], image.size[0], image.size[1]
    px = image.load()
    base = px[w // 2, 2][:3]              # the island's own ground, just under its top edge

    def bare(p):
        return abs(p[0] - base[0]) + abs(p[1] - base[1]) + abs(p[2] - base[2]) < 12

    rows = [all(bare(px[x, y]) for x in range(12, w - 12, 3)) for y in range(h)]
    out, best, start = [], (0, 0), None
    for y, empty in enumerate(rows + [False]):
        if empty and start is None:
            start = y
        elif not empty and start is not None:
            if y - start > best[0]:
                best = (y - start, start)
            start = None
    drawn = [y for y, empty in enumerate(rows) if not empty]
    if drawn and best[0] >= 96 and best[0] > 0.3 * h and drawn[0] < best[1] < drawn[-1]:
        out.append(Fault(scene, "empty-band", "look", f"{best[0]} px of nothing between what is drawn above and below", (12, best[1], w - 24, best[0])))
    elif drawn and best[0] >= 96 and best[0] > 0.3 * h:
        out.append(Fault(scene, "empty-band", "look", f"{best[0]} px of nothing at the {'top' if best[1] < drawn[0] else 'foot'} of the panel", (12, best[1], w - 24, best[0])))
    cols = [x for x in range(w) if not all(bare(px[x, y]) for y in range(12, h - 12, 3))]
    if cols:
        left, right = cols[0], w - 1 - cols[-1]
        if abs(left - right) > 6 and min(left, right) < 48:
            out.append(Fault(scene, "lopsided", "look", f"content starts {left} px from the left edge and ends {right} px from the right", None))
    return out
