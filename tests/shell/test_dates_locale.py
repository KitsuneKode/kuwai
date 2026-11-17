"""shell/config/dates.mjs in Qt's own engine, under real locales.

The pure logic is tested by bun (tests/shell/dates.test.mjs); this runs it
the way the shell does: Qt.locale() from LC_ALL, names and first day of the
week from Qt's CLDR data (not glibc's, so the locales needn't be generated),
offscreen. Skips where Qt's qml runner isn't installed.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
QML = shutil.which("qml6") or next((p for p in ("/usr/lib/qt6/bin/qml",) if os.access(p, os.X_OK)), None)


def run(locale: str) -> dict:
    env = {"PATH": "/usr/bin:/bin", "HOME": os.environ.get("HOME", "/tmp"), "LC_ALL": locale, "LANG": locale,
           "QT_QPA_PLATFORM": "offscreen", "QT_FORCE_STDERR_LOGGING": "1", "TZ": "UTC"}
    out = subprocess.run([QML, str(ROOT / "tests/ui/dates-locale.qml")], env=env, capture_output=True, text=True, timeout=30)
    for line in (out.stdout + out.stderr).splitlines():
        if "DATES_RESULT " in line:
            return json.loads(line.split("DATES_RESULT ", 1)[1])
    raise AssertionError(f"no result from {locale}:\n{out.stdout}\n{out.stderr}")


pytestmark = pytest.mark.skipif(QML is None, reason="Qt's qml runner is not installed")


def test_us_english():
    r = run("en_US.UTF-8")
    assert r["locale"] == "en_US"
    h24, h12 = r["h24"], r["h12"]
    assert h24["long"] == "Tuesday, November 17"
    assert h24["short"] == "Tue, Nov 17"
    assert h24["dayMonthYear"] == "Nov 17, 2026"
    assert h24["monthYear"] == "November 2026"
    assert h24["clock"] == "21:05" and h24["time"] == "21:05"
    assert h12["clock"] == "9:05" and h12["clockSeconds"] == "9:05:09"
    assert h12["time"].replace(" ", " ") == "9:05 PM"
    assert h24["firstDay"] == 0 and h24["weekdayNames"][0] == "Sun" and h24["lead"] == 0


def test_german():
    r = run("de_DE.UTF-8")
    h24 = r["h24"]
    assert r["locale"] == "de_DE"
    assert h24["long"] == "Dienstag, 17. November"
    assert h24["short"] == "Di., 17. Nov."
    assert h24["dayMonth"] == "17. Nov."
    assert h24["firstDay"] == 1
    assert h24["weekdayNames"] == ["Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa.", "So."]
    assert h24["lead"] == 6          # 1 November 2026 is a Sunday: the last column
    assert r["h12"]["clock"] == "9:05"


def test_british_and_japanese_order():
    gb = run("en_GB.UTF-8")["h24"]
    assert gb["long"] == "Tuesday, 17 November" and gb["firstDay"] == 1
    ja = run("ja_JP.UTF-8")["h24"]
    assert ja["monthYear"] == "2026年11月"
    assert [p["year"] for p in ja["monthYearParts"]] == [True, False]


def test_russian_month_on_its_own():
    ru = run("ru_RU.UTF-8")["h24"]
    assert ru["long"] == "вторник, 17 ноября"
    assert ru["monthYearParts"][0]["text"] == "ноябрь"
