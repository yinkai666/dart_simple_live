import unittest
from pathlib import PurePosixPath
from build_patched_mpv import native_overrides


class OverrideTests(unittest.TestCase):
    def test_preserves_other_forks_and_replaces_only_ios_native_package(self):
        source = {"dependency_overrides": {
            "get": {"git": {"url": "https://github.com/SlotSun/get.git", "ref": "master"}},
            "media_kit_libs_ios_video": {"git": {"ref": "original"}},
            "media_kit_libs_windows_video": {"git": {"ref": "unchanged"}},
        }}
        result = native_overrides(source, PurePosixPath("/isolated/native"))["dependency_overrides"]
        self.assertEqual(result["get"], source["dependency_overrides"]["get"])
        self.assertEqual(result["media_kit_libs_windows_video"], source["dependency_overrides"]["media_kit_libs_windows_video"])
        self.assertEqual(result["media_kit_libs_ios_video"], {"path": "/isolated/native"})
        self.assertIn("git", source["dependency_overrides"]["media_kit_libs_ios_video"])


if __name__ == "__main__":
    unittest.main()
