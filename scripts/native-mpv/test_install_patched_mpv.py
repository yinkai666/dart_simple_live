import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from verify_patched_mpv import install_verified_binary

NEW = "11111111-1111-1111-1111-111111111111"
OLD = "22222222-2222-2222-2222-222222222222"


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "build-Mpv"
        self.binary = Path(self.temp.name) / "embedded-Mpv"
        self.source.write_bytes(b"patched-build")
        self.binary.write_bytes(b"old-build")
        self.manifest = {"binary_uuid_arm64": NEW, "original_uuid_arm64": OLD,
                         "binary_sha256": hashlib.sha256(b"patched-build").hexdigest()}

    def test_installs_only_the_verified_build_product(self):
        with patch("verify_patched_mpv.read_uuids", side_effect=[{"arm64": NEW}, {"arm64": OLD}]):
            install_verified_binary(self.manifest, self.source, self.binary)
        self.assertEqual(self.binary.read_bytes(), b"patched-build")

    def test_rejects_tampering_before_changing_app(self):
        self.source.write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            install_verified_binary(self.manifest, self.source, self.binary)
        self.assertEqual(self.binary.read_bytes(), b"old-build")

    def test_rejects_unknown_native_dependency(self):
        with patch("verify_patched_mpv.read_uuids", side_effect=[{"arm64": NEW}, {"arm64": NEW.replace("1", "3")}]):
            with self.assertRaises(ValueError):
                install_verified_binary(self.manifest, self.source, self.binary)
        self.assertEqual(self.binary.read_bytes(), b"old-build")


if __name__ == "__main__":
    unittest.main()
