"""Calendar times in another zone are read at the right moment (bin/kuwai-ics-utc)."""
import subprocess
from pathlib import Path

BIN = Path(__file__).resolve().parents[1] / "bin/kuwai-ics-utc"


def run(text):
    return subprocess.run(["python3", "-I", str(BIN)], input=text, capture_output=True, text=True, check=True).stdout


def test_a_zoned_time_becomes_utc():
    out = run("DTSTART;TZID=America/New_York:20261127T090000\r\n")
    assert "DTSTART:20261127T140000Z" in out


def test_outlook_zone_names_and_lists():
    out = run('DTEND;TZID="Eastern Standard Time":20260701T090000\nEXDATE;TZID=Europe/Paris:20261201T090000,20260701T090000\n')
    assert "DTEND:20260701T130000Z" in out, "summer time in New York is UTC-4"
    assert "EXDATE:20261201T080000Z,20260701T070000Z" in out


def test_all_day_and_unknown_zones_stay():
    out = run("DTSTART;VALUE=DATE:20261128\nDTSTART;TZID=Mars/Olympus:20261127T090000\n")
    assert "DTSTART;VALUE=DATE:20261128" in out
    assert "DTSTART;TZID=Mars/Olympus:20261127T090000" in out
