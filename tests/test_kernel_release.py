import importlib.util
import unittest

spec = importlib.util.spec_from_file_location("kernel_release", "scripts/kernel-release.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class KernelReleaseTests(unittest.TestCase):
    def test_numeric_sort_not_lexicographic(self):
        data = {"releases": [
            {"version": "7.3.9", "moniker": "stable"},
            {"version": "7.3.10", "moniker": "stable"},
            {"version": "7.4-rc1", "moniker": "mainline"},
            {"version": "7.5.1", "moniker": "longterm", "iseol": True},
        ]}
        self.assertEqual(module.newest_release(data), "7.3.10")

    def test_minor_update_is_selected(self):
        data = {"releases": [{"version": "7.4", "moniker": "mainline"}]}
        self.assertEqual(module.newest_release(data), "7.4")

    def test_ignore_rc_and_eol(self):
        data = {"releases": [
            {"version": "7.4-rc3", "moniker": "mainline"},
            {"version": "7.3.2", "moniker": "stable", "iseol": True},
            {"version": "7.3.1", "moniker": "stable"},
        ]}
        self.assertEqual(module.newest_release(data), "7.3.1")

    def test_reject_invalid_manual_version(self):
        for value in ("7.4-rc1", "../etc/passwd", "7.3.1;true"):
            with self.assertRaises(ValueError):
                module.version_tuple(value)

    def test_reject_older_versions(self):
        with self.assertRaises(ValueError):
            module.newest_release({"releases": [{"version": "7.2.99", "moniker": "stable"}]})

if __name__ == "__main__":
    unittest.main()
