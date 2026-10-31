import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from importlib.machinery import SourceFileLoader
detect = SourceFileLoader("detect", str(Path(__file__).resolve().parents[1] / "detect-release.py")).load_module()
def item(version, moniker="stable", iseol=False):
    return {"version": version, "moniker": moniker, "iseol": iseol}
class ReleaseTests(unittest.TestCase):
    def test_patch(self):
        self.assertEqual(detect.select({"releases": [item("7.3.2"),item("7.3.10")]}), "7.3.10")
    def test_minor(self):
        self.assertEqual(detect.select({"releases": [item("7.3.99"),item("7.4", "mainline")]}), "7.4")
    def test_rc_filtered(self):
        self.assertEqual(detect.select({"releases": [item("7.4-rc1","mainline"),item("7.3.2")]}), "7.3.2")
    def test_requested_historical_final(self):
        # Users can rebuild 7.3.1 even if only newer releases remain in the JSON.
        self.assertEqual(detect.select({"releases": [item("7.3.10")]}, "7.3.1"), "7.3.1")

    def test_requested_invalid(self):
        for version in ("7.4-rc1", "7.2.1", "foobar"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                detect.select({"releases": [item("7.3.10")]}, version)
if __name__ == "__main__":
    unittest.main()
