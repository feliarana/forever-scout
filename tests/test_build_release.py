"""Tests for tools/build_release.py: the zip CurseForge and players receive.

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import build_release  # noqa: E402


class ReleaseZipTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = build_release.build(cls.tmp.name)
        with zipfile.ZipFile(cls.path) as archive:
            cls.files = {name: archive.read(name) for name in archive.namelist()}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_one_addon_folder_at_the_root_with_the_expected_files(self):
        self.assertEqual(sorted(self.files), sorted([
            "TrailScout/TrailScout.lua", "TrailScout/TrailScout.toc", "TrailScout/LICENSE",
            "TrailScout/README.md", "TrailScout/Route.lua"]))

    def test_the_zip_is_named_after_the_toc_version(self):
        version = build_release.addon_version()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        self.assertEqual(self.path.name, f"TrailScout-{version}.zip")
        self.assertIn(f"## Version: {version}".encode(), self.files["TrailScout/TrailScout.toc"])

    def test_the_route_ships_empty_whatever_is_loaded_locally(self):
        route = self.files["TrailScout/Route.lua"].decode("utf-8")
        self.assertTrue(route.rstrip().endswith("TrailScoutRoute = nil"))
        self.assertNotIn("points", route)

    def test_every_file_the_toc_lists_is_in_the_zip(self):
        toc = self.files["TrailScout/TrailScout.toc"].decode("utf-8")
        listed = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
        self.assertEqual(listed, ["Route.lua", "TrailScout.lua"])
        for name in listed:
            self.assertIn(f"TrailScout/{name}", self.files)

    def test_the_addon_code_is_the_one_in_the_repo_and_the_license_is_mit(self):
        self.assertEqual(self.files["TrailScout/TrailScout.lua"],
                         (REPO / "addon" / "TrailScout" / "TrailScout.lua").read_bytes())
        self.assertTrue(self.files["TrailScout/LICENSE"].startswith(b"MIT License"))

    def test_building_twice_gives_the_same_bytes(self):
        with tempfile.TemporaryDirectory() as other:
            self.assertEqual(build_release.build(other).read_bytes(), self.path.read_bytes())


if __name__ == "__main__":
    unittest.main()
