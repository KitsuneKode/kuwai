"""kuwai-pacnew's advice: three-way, with what you removed counting as a change (review 2026-11-10, finding 13)."""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("kuwai_pacnew", str(ROOT / "bin" / "kuwai-pacnew"))
spec = importlib.util.spec_from_loader("kuwai_pacnew", loader)
P = importlib.util.module_from_spec(spec)
loader.exec_module(P)

OLD = "# stock\nParallelDownloads = 5\nColor\nVerbosePkgLists\n"


class AdviceTests(unittest.TestCase):
    def case(self, yours, new, orig):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "pacman.conf")
            Path(path).write_text(yours)
            Path(path + ".pacnew").write_text(new)
            with mock.patch.object(P, "original", return_value=orig):
                return P.describe(path)

    def test_a_setting_you_commented_out_is_not_taken_back(self):
        yours = OLD.replace("Color\n", "#Color\n")
        item = self.case(yours, OLD + "DownloadUser = alpm\n", OLD)
        self.assertEqual(item["rec"], "keep", item)
        self.assertIn("turned these off", item["why"])

    def test_a_setting_you_deleted_is_not_taken_back(self):
        yours = OLD.replace("VerbosePkgLists\n", "")
        self.assertEqual(self.case(yours, OLD, OLD)["rec"], "keep")

    def test_untouched_is_taken(self):
        item = self.case(OLD, OLD + "DownloadUser = alpm\n", OLD)
        self.assertEqual(item["rec"], "take")
        self.assertIn("never changed", item["why"])

    def test_a_removal_the_new_default_also_drops_is_fine(self):
        yours = OLD.replace("Color\n", "")
        item = self.case(yours, OLD.replace("Color\n", "") + "DownloadUser = alpm\n", OLD)
        self.assertEqual(item["rec"], "take", item)
        self.assertNotIn("never changed", item["why"])

    def test_without_the_old_default_it_never_claims_untouched(self):
        item = self.case(OLD.replace("Color\n", ""), OLD + "DownloadUser = alpm\n", None)
        self.assertEqual(item["rec"], "review", item)
        self.assertNotIn("never changed", item["why"])

    def test_reordered_settings_are_never_just_comments(self):
        yours = "# mine\nVerbosePkgLists\nColor\nParallelDownloads = 5\n"
        item = self.case(yours, OLD, OLD.replace("# stock\n", "# stock, older\n"))
        self.assertEqual(item["rec"], "review", item)

    def test_repeated_lines_are_not_a_subset(self):
        yours = OLD + "Color\n"
        item = self.case(yours, OLD + "DownloadUser = alpm\n", OLD)
        self.assertEqual(item["rec"], "review", item)


class BaselineTests(unittest.TestCase):
    def test_the_baseline_is_the_newest_version_older_than_installed(self):
        files = ["pacman-7.0.0-1-x86_64.pkg.tar.zst", "pacman-7.1.0-1-x86_64.pkg.tar.zst",
                 "pacman-6.9.0-3-x86_64.pkg.tar.zst", "pacman-7.0.0-10-x86_64.pkg.tar.zst",
                 "pacman-7.2.0-1-x86_64.pkg.tar.zst"]
        seen = []

        def run(cmd, **kw):
            out = ""
            if cmd[:2] == ["pacman", "-Qoq"]:
                out = "pacman\n"
            elif cmd[:2] == ["pacman", "-Q"]:
                out = "pacman 7.1.0-1\n"
            elif cmd[0] == "vercmp":
                a, b = cmd[1], cmd[2]
                key = lambda v: [int(x) for x in v.replace("-", ".").split(".")]
                out = str((key(a) > key(b)) - (key(a) < key(b)))
            elif cmd[0] == "bsdtar":
                seen.append(os.path.basename(cmd[2]))
                return mock.Mock(returncode=0, stdout=b"old default")
            return mock.Mock(returncode=0, stdout=out)
        with mock.patch.object(P.os, "listdir", return_value=files), mock.patch.object(P.subprocess, "run", side_effect=run):
            self.assertEqual(P.original("/etc/pacman.conf"), "old default")
        self.assertEqual(seen, ["pacman-7.0.0-10-x86_64.pkg.tar.zst"], "never the newer 7.2.0, never 7.0.0-1 over -10")


if __name__ == "__main__":
    unittest.main()
