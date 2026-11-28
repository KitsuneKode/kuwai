"""The bring-back key goes through shuush when it's installed, voxtype otherwise, and says so when there's nothing."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_bring_back_prefers_shuush_then_voxtype_then_says_nothing_to_bring_back():
    lua = (ROOT / "hypr/kuwai/voxtype.lua").read_text()
    line = next(l for l in lua.splitlines() if "record recover" in l)
    assert line.index("shuush recover") < line.index("voxtype record recover")
    assert "command -v shuush" in line
    assert line.index("record recover") < line.index("Nothing to bring back")
