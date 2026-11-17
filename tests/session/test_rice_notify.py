"""rice-notify against a stand-in notification server on a private session bus.

Until 2026-11-17 every call without -A sent '[]' as a quoted string where
D-Bus wants an array (as), and every -H hint went in without its variant
brackets (a{sv}): gdbus refused both, and `2>/dev/null || exit 1` hid it, so
plain notifications and every crash alert (rice-crash-alert passes -H) failed
silently. The stand-in owns org.freedesktop.Notifications first, so nothing
real is activated or shown.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTIFY = ROOT / "bin" / "rice-notify"

SERVER = textwrap.dedent('''
    from gi.repository import Gio, GLib
    XML = """<node><interface name="org.freedesktop.Notifications">
    <method name="Notify"><arg type="s"/><arg type="u"/><arg type="s"/><arg type="s"/><arg type="s"/>
    <arg type="as"/><arg type="a{sv}"/><arg type="i"/><arg type="u" direction="out"/></method>
    </interface></node>"""
    iface = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
    def call(conn, sender, path, name, method, params, inv):
        a = params.unpack()
        print("GOT", a[3], a[5], sorted(a[6].items()), flush=True)
        inv.return_value(GLib.Variant("(u)", (7,)))
    def acquired(conn, name):
        conn.register_object("/org/freedesktop/Notifications", iface, call, None, None)
    def owned(conn, name):
        print("READY", flush=True)
    loop = GLib.MainLoop()
    Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.Notifications", 0, acquired, owned, lambda *a: loop.quit())
    GLib.timeout_add(8000, loop.quit)
    loop.run()
''')

RUN = textwrap.dedent('''
    python3 -I "$1" > "$2" &
    for _ in $(seq 50); do grep -q READY "$2" 2>/dev/null && break; sleep 0.1; done
    shift 2
    "$@"; echo "exit=$?"
    kill %1 2>/dev/null; wait
''')


def have_gi():
    try:
        r = subprocess.run([sys.executable, "-I", "-c", "from gi.repository import Gio"], capture_output=True)
        return r.returncode == 0
    except OSError:
        return False


@unittest.skipUnless(shutil.which("dbus-run-session") and shutil.which("gdbus") and have_gi(),
                     "needs dbus-run-session, gdbus and PyGObject")
class NotifyTests(unittest.TestCase):
    def notify(self, *args):
        with tempfile.TemporaryDirectory() as d:
            server, log = Path(d, "server.py"), Path(d, "log")
            server.write_text(SERVER)
            env = {k: v for k, v in os.environ.items() if k != "DBUS_SESSION_BUS_ADDRESS"}
            r = subprocess.run(["dbus-run-session", "--", "bash", "-c", RUN, "run", str(server), str(log), str(NOTIFY), *args],
                               capture_output=True, text=True, env=env, timeout=30)
            return r.stdout, r.stderr, log.read_text()

    def test_a_plain_notification_is_delivered(self):
        out, err, got = self.notify("Title", "Body")
        self.assertIn("exit=0", out, err)
        self.assertIn("GOT Title [] [('urgency', 1)]", got)

    def test_actions_and_rice_hints_are_delivered(self):
        out, err, got = self.notify("-A", "default=Diagnose", "-H", 'x-rice-crash=a "quoted" é', "Crash", "brief")
        self.assertIn("exit=0", out, err)
        self.assertIn("GOT Crash ['default', 'Diagnose']", got)
        self.assertIn("('x-rice-crash', 'a \"quoted\" é')", got)

    def test_a_failed_call_says_what_failed(self):
        env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/bus")
        r = subprocess.run([str(NOTIFY), "Title", "Body"], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(r.returncode, 1)
        lines = r.stderr.strip().splitlines()
        self.assertEqual(len(lines), 1, r.stderr)
        self.assertTrue(lines[0].startswith('rice-notify: the notification server did not take "Title": '), lines[0])


if __name__ == "__main__":
    unittest.main()
