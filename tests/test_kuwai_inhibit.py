"""bin/kuwai-inhibit: apps can hold the screen on through org.freedesktop.ScreenSaver."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[1] / "bin" / "kuwai-inhibit"

pytestmark = pytest.mark.skipif(not shutil.which("dbus-run-session"), reason="needs dbus-run-session")

DRIVER = r'''
import json, subprocess, sys, time
from gi.repository import Gio, GLib
bridge = subprocess.Popen([sys.argv[1]], stdout=subprocess.PIPE, text=True)
lines = []
def read():
    lines.append(json.loads(bridge.stdout.readline()))
read()
def client():
    return Gio.DBusConnection.new_for_address_sync(Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None),
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
def call(c, path, method, args, sig):
    return c.call_sync("org.freedesktop.ScreenSaver", path, "org.freedesktop.ScreenSaver", method,
                       GLib.Variant(sig, args) if sig else None, None, Gio.DBusCallFlags.NONE, 2000, None).unpack()
one, two = client(), client()
(a,) = call(one, "/org/freedesktop/ScreenSaver", "Inhibit", ("Zen", "Playing video"), "(ss)"); read()
call(two, "/ScreenSaver", "Inhibit", ("Discord", "call\nin progress"), "(ss)"); read()
call(two, "/ScreenSaver", "UnInhibit", (a,), "(u)")
call(one, "/ScreenSaver", "UnInhibit", (a,), "(u)"); read()
active = call(one, "/ScreenSaver", "GetActive", None, None)
two.close_sync(None); read()
second = subprocess.run([sys.argv[1]], timeout=10).returncode
bridge.kill()
print(json.dumps({"lines": lines, "active": active, "second": second}))
'''


def test_holds_come_and_go_with_their_app_and_a_second_owner_steps_aside():
    env = {k: v for k, v in os.environ.items() if k != "DBUS_SESSION_BUS_ADDRESS"}
    r = subprocess.run(["dbus-run-session", "--", sys.executable, "-c", DRIVER, str(BIN)], env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    got = json.loads(r.stdout.strip().splitlines()[-1])
    assert got["lines"] == [
        [],
        [{"app": "Zen", "reason": "Playing video"}],
        [{"app": "Discord", "reason": "call in progress"}, {"app": "Zen", "reason": "Playing video"}],
        [{"app": "Discord", "reason": "call in progress"}],
        [],
    ]
    assert got["active"] == [False]
    assert got["second"] == 3
