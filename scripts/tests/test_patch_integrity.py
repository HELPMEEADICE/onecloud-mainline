"""Catch malformed unified-diff hunk counts before downloading toolchains."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


class PatchIntegrity(unittest.TestCase):
    def test_all_kernel_patch_hunk_counts(self):
        paths = sorted((ROOT / "patches").glob("*.patch"))
        self.assertTrue(paths, "no kernel patches found")
        for path in paths:
            with self.subTest(patch=path.name):
                old_expected = new_expected = old_actual = new_actual = None

                def check_hunk():
                    if old_expected is not None:
                        self.assertEqual(
                            (old_actual, new_actual),
                            (old_expected, new_expected),
                            f"{path.name}: malformed unified-diff hunk",
                        )

                for line in path.read_text(encoding="utf-8").splitlines():
                    match = HEADER.match(line)
                    if match:
                        check_hunk()
                        old_expected = int(match.group(2) or 1)
                        new_expected = int(match.group(4) or 1)
                        old_actual = new_actual = 0
                    elif old_expected is not None:
                        if line.startswith(("--- ", "diff --git ")):
                            check_hunk()
                            old_expected = new_expected = old_actual = new_actual = None
                        elif line.startswith("+"):
                            new_actual += 1
                        elif line.startswith("-"):
                            old_actual += 1
                        elif line.startswith(" "):
                            old_actual += 1
                            new_actual += 1
                        elif line.startswith("\\ No newline"):
                            pass
                        elif line:
                            self.fail(f"{path.name}: unexpected line within patch hunk: {line[:90]}")
                check_hunk()


if __name__ == "__main__":
    unittest.main()
