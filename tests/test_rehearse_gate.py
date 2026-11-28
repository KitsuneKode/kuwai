"""The rehearsal's rules (lib/rehearse/gate.py), each with a frame it must
fault and the same frame put right. If a rule stops catching its fault, the
contact sheet goes quiet for the wrong reason; these keep it honest.

The staging itself (bwrap, Xvfb, the real panels) is bin/kuwai-rehearse --gate:
a minute long and not run by pytest.
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))
from rehearse import gate  # noqa: E402


def text(t, box, **kw):
    d = dict(t=t, box=list(box), own=list(box), size=13, weight=400, family="SF Pro Text", drawn="SF Pro Text",
             color="#f5ffffff", op=1, on=True, cut=False, elides=False, wraps=False, lines=1, clip=None, scroll=False, path="Panel>Label")
    d.update(kw)
    return d


def frame(texts=(), targets=(), **kw):
    filler = [text("Software Update", (20, 16, 120, 18)), text("Checked ten minutes ago", (20, 40, 150, 14))]
    d = dict(id="demo/typical @x1", panel="DemoPanel", kind="typical", scale=1, w=440, h=300, wants=[440, 300],
             texts=filler + list(texts), targets=list(targets), scrolls=[], waiting=0)
    d.update(kw)
    return d


def rules(f, image=None):
    return sorted({x.rule for x in gate.judge(f, image) if x.level == "fail"})


def test_a_sound_frame_has_no_faults():
    assert gate.judge(frame()) == []


@pytest.mark.parametrize("rule,bad,good", [
    ("cut-off", text("Wednesday, 18 November", (300, 80, 180, 16)), text("Wednesday, 18 November", (240, 80, 180, 16))),
    ("cut-off", text("clipped by its card", (20, 80, 200, 16), clip=[20, 70, 150, 40]), text("clipped by its card", (20, 80, 120, 16), clip=[20, 70, 150, 40])),
    ("shortened", text("An ordinary name", (20, 80, 100, 16), cut=True, elides=True), text("An ordinary name", (20, 80, 100, 16), elides=True)),
    ("spills", text("62% left", (20, 80, 59, 16), own=[20, 80, 56, 16]), text("62% left", (20, 80, 59, 16), own=[20, 80, 60, 16])),
    ("small-type", text("fine print", (20, 80, 60, 10), size=9), text("fine print", (20, 80, 60, 12), size=10)),
    ("insides", text("kuwai-usage isn't running", (20, 80, 160, 16)), text("Usage can't be read right now", (20, 80, 180, 16))),
    ("insides", text("Finished · NaN h ago", (20, 80, 160, 16)), text("Finished · 2 h ago", (20, 80, 160, 16))),
    ("insides", text("The helper failed (exit 99)", (20, 80, 160, 16)), text("Couldn't check for updates", (20, 80, 160, 16))),
    ("on-top", text("7.3.4.zen2-2", (20, 90, 80, 14)), text("7.3.4.zen2-2", (20, 100, 80, 14))),
    ("missing-font", text("", (20, 80, 16, 16), family="Phosphor", drawn="DejaVu Sans"), text("", (20, 80, 16, 16), family="Phosphor", drawn="Phosphor")),
])
def test_each_rule_catches_its_fault_and_passes_its_fix(rule, bad, good):
    other = text("linux-zen", (20, 80, 70, 16)) if rule == "on-top" else None
    extra = [other] if other else []
    assert rule in rules(frame(extra + [bad])), f"{rule} did not fault the bad frame"
    assert rule not in rules(frame(extra + [good])), f"{rule} faulted the good frame"


def test_a_command_shown_as_code_is_content_not_insides():
    command = text("kuwai-theme install --all --live", (20, 80, 240, 16), family="SF Mono", drawn="SF Mono")
    assert "insides" not in rules(frame([command]))
    assert "insides" in rules(frame([dict(command, family="SF Pro Text", drawn="SF Pro Text")]))   # the same words as a message


def test_worst_case_data_may_be_shortened_but_not_cut():
    long = text("A thread whose title was written as a whole sentence", (20, 80, 380, 16), cut=True, elides=True)
    assert "shortened" not in rules(frame([long], kind="worst"))
    assert "cut-off" in rules(frame([text("x" * 30, (20, 80, 600, 16))], kind="worst"))


def test_what_is_scrolled_away_is_not_a_fault_but_a_side_cut_is():
    clip = [20, 60, 400, 100]
    below = text("row twelve of a long list", (30, 400, 200, 16), clip=clip, scroll=True)
    assert rules(frame([below])) == []
    wide = text("a row wider than its list", (30, 80, 450, 16), clip=clip, scroll=True)
    assert "cut-off" in rules(frame([wide]))


def test_targets_and_panel_size():
    small = dict(box=[400, 20, 22, 22], how="tap", clip=None, scroll=False, path="X")
    assert "small-target" in rules(frame(targets=[small]))
    assert "small-target" not in rules(frame(targets=[dict(small, box=[392, 12, 38, 38])]))
    half_scrolled = dict(box=[20, 150, 400, 44], how="area", clip=[20, 60, 400, 100], scroll=True, path="Row")
    assert "small-target" not in rules(frame(targets=[half_scrolled]))
    assert "too-big" in rules(frame(wants=[440, 773]))


def test_a_panel_must_say_something_and_stop_waiting_when_it_failed():
    assert "says-nothing" in rules(dict(frame(), texts=[text("Open", (380, 20, 40, 16))]))
    assert "says-nothing" not in rules(dict(frame(), texts=[], wordless=True))
    waiting = frame([text("The check didn't finish", (20, 80, 160, 16))], waiting=3)
    assert "waits-forever" in rules(waiting)
    assert "waits-forever" not in rules(dict(waiting, waiting=0))
    assert "waits-forever" not in rules(frame(waiting=3))            # still loading, nothing failed: fine


def test_contrast_is_measured_against_the_picture():
    PIL = pytest.importorskip("PIL.Image")
    img = PIL.new("RGB", (440, 300), (15, 15, 15))
    faint = text("26", (40, 120, 16, 16), color="#40ffffff")          # white at 25 %
    found = {x.rule: x for x in gate.judge(frame([faint]), img)}
    assert "unreadable" in found and "2." in found["unreadable"].what
    dim = text("26", (40, 120, 16, 16), color="#61ffffff")            # white at 38 %: dim, readable
    kinds = {x.rule: x.level for x in gate.judge(frame([dim]), img)}
    assert "unreadable" not in kinds and kinds.get("faint") == "look"
    green = PIL.new("RGB", (440, 300), (41, 178, 75))                 # white on the solid green Allow button
    assert "unreadable" in {x.rule for x in gate.judge(frame([text("Allow", (40, 120, 40, 16))]), green)}
    assert gate.contrast((1, 1, 1), (0, 0, 0)) == pytest.approx(21)
    # In a scrolling list's fading edge (ScrollFade thins it on purpose) contrast isn't judged;
    # the same text in the middle of the list is.
    at_foot = text("Allow", (40, 280, 40, 16), scroll=True, clip=[0, 60, 440, 240])
    mid = text("Allow", (40, 160, 40, 16), scroll=True, clip=[0, 60, 440, 240])
    allow = lambda t: {x.rule for x in gate.judge(frame([t]), green) if '"Allow"' in x.what}
    assert "unreadable" not in allow(at_foot)
    assert "unreadable" in allow(mid)


def test_a_fault_is_named_the_same_whatever_the_clock_says():
    a = gate.Fault("t3/typical @x2", "shortened", "fail", '"Finished · 57 min ago" is shortened', None)
    b = gate.Fault("t3/typical @x2", "shortened", "fail", '"Finished · 58 min ago" is shortened', None)
    assert a.key == b.key and "@x2" in a.key


def test_every_island_panel_is_rehearsed():
    """A panel nobody stages is a panel nobody has looked at."""
    doc = json.loads((ROOT / "tests/ui/scenes.json").read_text())
    staged = {s["panel"] for s in doc["scenes"]}
    panels = {p.stem for p in (ROOT / "shell/modules/island").glob("*Panel.qml")}
    assert panels - staged == set(), f"no scene for: {sorted(panels - staged)} (tests/ui/scenes.json)"
    ids = [s["id"] for s in doc["scenes"]]
    assert len(ids) == len(set(ids))
    for s in doc["scenes"]:
        assert (ROOT / "shell/modules/island" / (s["panel"] + ".qml")).is_file(), s["id"]
        assert s.get("kind", "typical") in ("typical", "worst")


def test_a_scene_leaves_a_text_size_out_only_with_a_reason_and_only_for_the_clipboard_shelf():
    doc = json.loads((ROOT / "tests/ui/scenes.json").read_text())
    held = [s for s in doc["scenes"] if "scales" in s]
    assert all(s.get("why") for s in held)
    assert all(set(s["scales"]) <= {1, 1.2} for s in held)
    assert {s["id"].split("/")[0] for s in held} <= {"clipboard"}


def test_scenes_that_stage_a_window_name_a_file_that_exists():
    doc = json.loads((ROOT / "tests/ui/scenes.json").read_text())
    for s in doc["scenes"]:
        if s.get("window") or s["panel"].startswith("../"):
            assert (ROOT / "shell/modules/island" / (s["panel"] + ".qml")).resolve().is_file(), s["id"]


def test_the_known_list_is_only_debt_at_twice_the_text():
    """At 100 % and 120 % nothing is excused. What is listed is the 200 % debt."""
    known = [l for l in (ROOT / "tests/ui/rehearsal-known.txt").read_text().splitlines() if l and not l.startswith("#")]
    assert [l for l in known if not re.search(r" @x2 \| ", l)] == []
    # Empty since 2026-11-21 (it was 31 on Nov 18): a new fault is fixed, not listed.
    assert len(known) == 0, "the known list is empty: fix the fault instead of listing it"


def test_moments_in_scene_data():
    spec = importlib.util.spec_from_loader("kuwai_rehearse", importlib.machinery.SourceFileLoader("kuwai_rehearse", str(ROOT / "bin/kuwai-rehearse")))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    out = mod.at_now({"a": "@now-300s", "b": ["@now+5000ms", "plain"], "c": "@now-60iso"}, now=1_800_000_000)
    assert out == {"a": 1_799_999_700, "b": [1_800_000_005_000, "plain"], "c": "2027-01-15T07:59:00Z"}


def test_the_lock_clock_is_measured_against_the_wallpaper(tmp_path):
    PIL = pytest.importorskip("PIL.Image")
    from rehearse import wall
    def paint(name, colour, band=None):
        img = PIL.new("RGB", (1920, 1080), colour)
        if band:
            img.paste(band, (0, 100, 1920, 340))        # a band right behind the date and clock
        path = tmp_path / name
        img.save(path)
        return path
    night = wall.lock_clock(paint("night.png", (12, 16, 30)))
    assert night["ok"] and night["shade"] == 0 and night["calm"]            # a dark picture is left alone
    snow = wall.lock_clock(paint("snow.png", (245, 245, 245)))
    assert snow["bare"] < 2                                                   # what the lock gave: white on white
    assert snow["ok"] and snow["clock"] >= 3 and snow["shade"] > 0.35 and not snow["calm"]
    # A dark picture with a bright sky behind the clock needs the shade; the same sky at the foot does not.
    assert wall.lock_clock(paint("sky.png", (20, 20, 24), band=(235, 235, 240)))["shade"] > 0.3
    foot = PIL.new("RGB", (1920, 1080), (20, 20, 24)); foot.paste((235, 235, 240), (0, 760, 1920, 1080))
    foot.save(tmp_path / "foot.png")
    assert wall.lock_clock(tmp_path / "foot.png")["shade"] == 0
    assert wall.shade_for(1.0, (1, 1, 1)) <= wall.MOST and wall.shade_for(0.1, (1, 1, 1)) == wall.SCRIM
    # A portrait picture is cover-cropped like the screen does it, not squeezed.
    tall = PIL.new("RGB", (1080, 2400), (20, 20, 24)); tall.save(tmp_path / "tall.png")
    assert wall.lock_layer(tmp_path / "tall.png").size == wall.SIZE


def test_text_with_something_drawn_over_it_is_hidden():
    """UpdatesPanel's list under ScrollFade's mask: white text, a black picture,
    21:1 by the numbers and not a letter to see."""
    PIL = pytest.importorskip("PIL.Image")
    from PIL import ImageDraw
    def hidden(t, img):
        return any(x.rule == "hidden" and t["t"] in x.what for x in gate.judge(frame([t]), img))
    words = text("quickshell-git", (40, 120, 100, 16))
    covered = PIL.new("RGB", (440, 300), (0, 0, 0))
    assert hidden(words, covered)
    shown = PIL.new("RGB", (440, 300), (0, 0, 0))
    ImageDraw.Draw(shown).rectangle([50, 124, 60, 130], fill=(240, 240, 240))       # a stroke of it
    assert not hidden(words, shown)
    faint = text("26", (40, 120, 16, 16), color="#40ffffff")                         # unreadable says so instead
    assert not hidden(faint, covered)
    near_edge = text("Battery at 15 %", (40, 145, 120, 14), clip=[20, 60, 400, 100], scroll=True)
    assert not hidden(near_edge, covered)                                            # ScrollFade's to judge


def test_what_a_floating_menu_covers_is_not_judged_but_the_menu_is():
    under = text("linux-zen", (300, 100, 70, 16))
    item = text("Copy name", (290, 96, 120, 16), layer=1)
    menu = dict(box=[280, 80, 200, 120], layer=1)
    assert "on-top" in rules(frame([under, item]))                                   # nothing says the menu floats
    assert "on-top" not in rules(frame([under, item], covers=[menu]))
    tiny = text("x", (20, 250, 30, 9), size=8, layer=1)                               # the menu's own text is still judged
    assert "small-type" in rules(frame([tiny], covers=[dict(box=[10, 240, 60, 30], layer=1)]))


def test_a_list_must_not_end_on_a_row_cut_at_full_strength():
    PIL = pytest.importorskip("PIL.Image")
    from PIL import ImageDraw
    clip = [20, 60, 400, 100]                                   # the list shows y 60–160
    row = text("Battery at 15 %", (40, 152, 120, 16), clip=clip, scroll=True)   # half of it is below the edge
    def picture(strength):
        img = PIL.new("RGB", (440, 300), (15, 15, 15))
        ImageDraw.Draw(img).rectangle([40, 152, 160, 159], fill=(strength, strength, strength))
        return img
    assert "cut-row" in rules(frame([row]), picture(245))       # drawn at full strength up to the edge
    assert "cut-row" not in rules(frame([row]), picture(40))    # faded out where it meets the edge
    whole = text("Stand-up in 10 minutes", (40, 100, 150, 16), clip=clip, scroll=True)
    assert "cut-row" not in rules(frame([whole]), picture(245))
    # A wrapped text: only the line that crosses the edge is judged. Three lines from
    # y 112: the first two are whole and bright, the third crosses at 160 and is faded.
    para = text("Allow Bash: bun test tests/shell in ~/Projects/rice?", (40, 112, 300, 54), clip=clip, scroll=True, lines=3, wraps=True)
    def para_picture(last):
        img = PIL.new("RGB", (440, 300), (15, 15, 15))
        d = ImageDraw.Draw(img)
        d.rectangle([40, 114, 300, 145], fill=(245, 245, 245))      # lines 1–2, whole
        d.rectangle([40, 150, 300, 159], fill=(last, last, last))   # line 3, up to the edge
        return img
    assert "cut-row" not in rules(frame([para]), para_picture(40))
    assert "cut-row" in rules(frame([para]), para_picture(245))
