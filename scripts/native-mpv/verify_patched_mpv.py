#!/usr/bin/env python3
"""Fail packaging unless Runner embeds the rebuilt mpv and matching symbols."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_uuid(value: str) -> str:
    return str(uuid.UUID(value)).upper()


def parse_uuids(output: str) -> dict[str, str]:
    result = {}
    for value, arch in re.findall(r"^UUID:\s+([0-9A-Fa-f-]+)\s+\(([^)]+)\)", output, re.M):
        if arch in result:
            raise ValueError(f"Duplicate architecture in dwarfdump output: {arch}")
        result[arch] = normalized_uuid(value)
    if not result:
        raise ValueError("dwarfdump returned no Mach-O UUIDs")
    return result


def read_uuids(path: Path) -> dict[str, str]:
    result = subprocess.run(
        ["xcrun", "dwarfdump", "--uuid", str(path)],
        check=True, text=True, capture_output=True,
    )
    return parse_uuids(result.stdout)


def verify_identity(manifest: dict, embedded: dict, symbols: dict) -> str:
    expected = normalized_uuid(manifest["binary_uuid_arm64"])
    symbol_expected = normalized_uuid(manifest["dsym_uuid_arm64"])
    if expected != symbol_expected:
        raise ValueError("Manifest binary and dSYM UUIDs do not match")
    # This build is for physical iPads only; reject simulator or stale fat slices.
    if embedded != {"arm64": expected}:
        raise ValueError(f"Runner contains unexpected mpv UUID/architecture: {embedded}; expected arm64 {expected}")
    if symbols != {"arm64": expected}:
        raise ValueError(f"dSYM does not match embedded mpv: {symbols}; expected arm64 {expected}")
    original = manifest.get("original_uuid_arm64")
    if original and normalized_uuid(original) == expected:
        raise ValueError("Rebuilt mpv still has the original UUID")
    return expected


def require_hash(path: Path, expected: str) -> str:
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
        raise ValueError(f"Invalid expected SHA-256 for {path}")
    actual = sha256(path)
    if actual != expected.lower():
        raise ValueError(f"SHA-256 mismatch for {path}: {actual} != {expected}")
    return actual


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-dir", type=Path, required=True, help="Flutter app directory")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--dsym", type=Path, required=True, help="Rebuilt Mpv.framework.dSYM")
    parser.add_argument("--patch", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    binary = args.app_dir / "build/ios/iphoneos/Runner.app/Frameworks/Mpv.framework/Mpv"
    symbols = args.dsym / "Contents/Resources/DWARF/Mpv"
    if not binary.is_file() or not symbols.is_file():
        raise ValueError(f"Missing packaged mpv or dSYM: {binary}, {symbols}")
    patch_hash = require_hash(args.patch, manifest["patch_sha256"])
    identifier = verify_identity(manifest, read_uuids(binary), read_uuids(symbols))
    # Codesigning or stripping may change the file hash while preserving LC_UUID.
    # Record the packaged bytes separately from the builder's binary_sha256.
    report = {
        "verified": True,
        "binary_uuid_arm64": identifier,
        "dsym_uuid_arm64": identifier,
        "embedded_binary_sha256": sha256(binary),
        "dsym_sha256": sha256(symbols),
        "manifest_sha256": sha256(args.manifest),
        "patch_sha256": patch_hash,
        "embedded_binary": str(binary.resolve()),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Verified patched iPad mpv and dSYM: arm64 {identifier}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"mpv provenance verification failed: {error}", file=sys.stderr)
        sys.exit(1)
