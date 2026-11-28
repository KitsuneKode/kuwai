import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVG_NS = "{http://www.w3.org/2000/svg}"


def brand_svgs():
    files = sorted((ROOT / "docs/brandkit").glob("*.svg"))
    files += sorted((ROOT / "docs/brandkit/assets").glob("*.svg"))
    files += sorted((ROOT / "system/icons/hicolor/scalable/apps").glob("kuwai*.svg"))
    return files


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def test_generated_brand_assets_are_current():
    r = subprocess.run([str(ROOT / "bin/kuwai-brand"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_every_brand_svg_is_accessible_vector_xml_without_text():
    files = brand_svgs()
    assert files
    for path in files:
        root = ET.parse(path).getroot()
        assert local_name(root.tag) == "svg", path
        assert root.attrib.get("role") == "img", path
        titles = [node for node in root.iter() if local_name(node.tag) == "title" and (node.text or "").strip()]
        assert titles, path
        assert not [node for node in root.iter() if local_name(node.tag) == "text"], path


def test_monochrome_mark_is_evenodd_current_color():
    root = ET.parse(ROOT / "docs/brandkit/kuwai-mark-mono.svg").getroot()
    paths = [node for node in root.iter() if local_name(node.tag) == "path"]
    assert any(node.attrib.get("fill") == "currentColor" and node.attrib.get("fill-rule") == "evenodd" for node in paths)


def test_small_marks_use_one_dot_and_no_pill():
    for size in (16, 32):
        root = ET.parse(ROOT / "docs/brandkit" / f"kuwai-mark-{size}.svg").getroot()
        circles = [node for node in root.iter() if local_name(node.tag) == "circle"]
        rects = [node for node in root.iter() if local_name(node.tag) == "rect"]
        assert len(circles) == 1
        assert rects == []


def test_colour_marks_use_the_accent_dot():
    for name in ("kuwai-mark-on-dark.svg", "kuwai-mark-on-light.svg", "kuwai-mark-tile.svg", "kuwai-mark-16.svg", "kuwai-mark-32.svg"):
        assert 'fill="#ff9f0a"' in (ROOT / "docs/brandkit" / name).read_text()
