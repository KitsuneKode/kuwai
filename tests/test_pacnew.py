"""rice-pacnew's advice: three-way, with what you removed counting as a change (review 2026-11-10, finding 13)."""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("rice_pacnew", str(ROOT / "bin" / "rice-pacnew"))
spec = importlib.util.spec_from_loader("rice_pacnew", loader)
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


if __name__ == "__main__":
    unittest.main()
