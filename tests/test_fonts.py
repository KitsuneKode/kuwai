import json
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = {
    "Geist-Regular.ttf": "Kuwai Geist 400",
    "Geist-Medium.ttf": "Kuwai Geist 500",
    "Geist-SemiBold.ttf": "Kuwai Geist 600",
    "Geist-Bold.ttf": "Kuwai Geist 700",
    "GeistMono-Regular.ttf": "Kuwai Geist Mono 400",
    "GeistMono-Medium.ttf": "Kuwai Geist Mono 500",
}


def family(path):
    font = TTFont(path)
    for record in font["name"].names:
        if record.nameID == 16:
            return record.toUnicode()
    for record in font["name"].names:
        if record.nameID == 1:
            return record.toUnicode()
    return ""


def test_bundled_geist_weights_are_family_separated():
    directory = ROOT / "shell/assets/fonts"
    assert sorted(EXPECTED) == sorted(p.name for p in directory.glob("*.ttf"))
    for file, want in EXPECTED.items():
        assert family(directory / file) == want


def test_geist_license_and_notice_are_present():
    license_text = (ROOT / "shell/assets/fonts/OFL.txt").read_text(errors="replace")
    assert "SIL OPEN FONT LICENSE" in license_text.upper()
    assert "Geist" in (ROOT / "NOTICE.md").read_text()


def test_typography_settings_have_live_defaults_and_enums():
    schema = json.loads((ROOT / "shell/config/settings-schema.json").read_text())
    entries = {entry["key"]: entry for entry in schema["settings"]}
    assert entries["fontProfile"]["default"] == "auto"
    assert entries["fontProfile"]["enum"] == ["auto", "sf-rounded", "sf", "geist", "inter", "system"]
    assert entries["clockFont"]["enum"] == ["auto", "sf-rounded", "geist", "sf-display"]
    assert entries["monoFont"]["enum"] == ["auto", "sf-mono", "geist-mono", "monolisa", "dank-mono", "jetbrains", "maple", "iosevka"]
    assert all(entries[key]["restartScope"] == "live" for key in ("fontProfile", "clockFont", "monoFont"))
