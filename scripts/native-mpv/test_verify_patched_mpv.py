import unittest

from verify_patched_mpv import parse_uuids, verify_identity


UUID = "12345678-1234-5678-9ABC-123456789ABC"
STALE_UUID = "12345678-1234-5678-9ABC-123456789ABD"


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.manifest = {"binary_uuid_arm64": UUID, "dsym_uuid_arm64": UUID}

    def test_macho_output_accepts_lowercase_uuid_and_path_with_spaces(self):
        output = f"UUID: {UUID.lower()} (arm64) /a path/Mpv.framework/Mpv\n"
        self.assertEqual(parse_uuids(output), {"arm64": UUID})

    def test_no_uuid_is_a_failure(self):
        with self.assertRaises(ValueError):
            parse_uuids("not a Mach-O file")

    def test_matching_binary_and_symbols_pass(self):
        self.assertEqual(verify_identity(self.manifest, {"arm64": UUID}, {"arm64": UUID}), UUID)

    def test_stale_pod_binary_is_rejected(self):
        with self.assertRaises(ValueError):
            verify_identity(self.manifest, {"arm64": STALE_UUID}, {"arm64": UUID})

    def test_wrong_symbols_are_rejected(self):
        with self.assertRaises(ValueError):
            verify_identity(self.manifest, {"arm64": UUID}, {"arm64": STALE_UUID})

    def test_simulator_slice_is_rejected(self):
        with self.assertRaises(ValueError):
            verify_identity(self.manifest, {"arm64": UUID, "x86_64": UUID}, {"arm64": UUID})

    def test_original_binary_identity_is_rejected(self):
        self.manifest["original_uuid_arm64"] = UUID
        with self.assertRaises(ValueError):
            verify_identity(self.manifest, {"arm64": UUID}, {"arm64": UUID})


if __name__ == "__main__":
    unittest.main()
