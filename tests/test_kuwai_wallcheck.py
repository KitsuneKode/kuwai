"""bin/kuwai-wallcheck: the gate a wallpaper passes before kuwai offers it (docs/design/LOOKS.md).

Each rule is driven by a picture made to break it, and a calm dark picture passes them all."""
import importlib.machinery
import importlib.util
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("kuwai_wallcheck", str(ROOT / "bin/kuwai-wallcheck"))
spec = importlib.util.spec_from_loader("kuwai_wallcheck", loader)
wc = importlib.util.module_from_spec(spec)
loader.exec_module(wc)


def night(path, size=(2560, 1440), seed=1):
    """A calm night: a dark gradient sky, a darker ridge, a few stars."""
    w, h = size
    im = Image.new("RGB", size)
    d = ImageDraw.Draw(im)
    for y in range(h):
        v = int(40 + 50 * y / h)
        d.line([(0, y), (w, y)], fill=(v * 2 // 3, v * 2 // 3, v))
    rnd = random.Random(seed)
    d.polygon([(0, h)] + [(x, int(h * 0.7 + rnd.uniform(-60, 60))) for x in range(0, w + 1, w // 12)] + [(w, h)], fill=(14, 16, 22))
    for _ in range(80):
        x, y = rnd.randrange(w), rnd.randrange(h // 2)
        d.point((x, y), fill=(200, 200, 220))
    im.save(path)
    return path


def test_a_calm_night_passes(tmp_path):
    r = wc.check(night(tmp_path / "n.png"))
    assert r["verdict"] == "ok", r["why"]


def test_letterbox_bars_fail_but_a_black_ridge_does_not(tmp_path):
    im = Image.open(night(tmp_path / "n.png")).copy()
    ImageDraw.Draw(im).rectangle((0, 0, 2559, 160), fill=(0, 0, 0))
    im.save(tmp_path / "bars.png")
    assert wc.check(tmp_path / "bars.png")["verdict"] == "fail"
    assert wc.check(tmp_path / "n.png")["bars"] == [0.0, 0.0]


def test_a_bright_busy_top_fails(tmp_path):
    im = Image.open(night(tmp_path / "n.png")).copy()
    d = ImageDraw.Draw(im)
    for x in range(0, 2560, 40):
        d.rectangle((x, 0, x + 19, 59), fill=(250, 250, 250))
    im.save(tmp_path / "busy.png")
    r = wc.check(tmp_path / "busy.png")
    assert r["verdict"] == "fail" and any("under the island" in w for w in r["why"])


def test_a_small_picture_is_not_stretched(tmp_path):
    r = wc.check(night(tmp_path / "small.png", size=(1280, 720)))
    assert r["verdict"] == "fail" and "upscaled" in r["why"][0]
    assert wc.check(tmp_path / "small.png", skip=("size",))["verdict"] == "ok"


def test_loud_colour_is_flagged(tmp_path):
    im = Image.new("RGB", (2560, 1440), (10, 10, 14))
    ImageDraw.Draw(im).rectangle((0, 300, 2559, 1439), fill=(255, 20, 160))
    im.save(tmp_path / "loud.png")
    assert any("saturated" in w for w in wc.check(tmp_path / "loud.png")["why"])


def test_near_duplicates_fail(tmp_path):
    a = night(tmp_path / "a.png")
    Image.open(a).filter(ImageFilter.GaussianBlur(2)).resize((3000, 1688)).save(tmp_path / "b.png")
    rs = [wc.check(tmp_path / "a.png"), wc.check(tmp_path / "b.png")]
    wc.twins(rs)
    assert rs[1]["verdict"] == "fail" and "near-duplicate" in rs[1]["why"][-1]


def test_a_kuwai_theme_row_must_be_pinned_licensed_and_credited(tmp_path):
    t = tmp_path / "t"
    t.mkdir()
    (t / "theme.toml").write_text('name = "T"\ncollection = "kuwai"\naccent = "#5eead4"\n')
    (t / "wallpapers.tsv").write_text(
        "01-ok\thttps://x/a.jpg\tsha1:" + "a" * 40 + "\tCC-BY-4.0\tSomeone\thttps://p\n"
        "02-nopin\thttps://x/b.jpg\t\tCC-BY-4.0\tSomeone\thttps://p\n"
        "03-nc\thttps://x/c.jpg\tsha1:" + "b" * 40 + "\tCC-BY-NC-4.0\tSomeone\thttps://p\n"
        "04-anon\thttps://x/d.jpg\tsha1:" + "c" * 40 + "\tPD\t\thttps://p\n")
    problems = wc.check_tsv(t)
    assert len(problems) == 3
    assert "02-nopin" in problems[0] and "03-nc" in problems[1] and "04-anon" in problems[2]
