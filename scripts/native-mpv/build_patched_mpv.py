"""Rebuild only iOS arm64 libmpv, retaining the pinned 0.6.8 dependency ABI.

Runs on macOS CI. Source archives are hash-checked; no assert is disabled.
The resulting binary replaces the prepared Pod framework and has a matching
dSYM/provenance manifest. Final app embedding is checked by a separate gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request

SOURCES = {
    "mpv": ("https://github.com/mpv-player/mpv/archive/refs/tags/v0.36.0.tar.gz", "29abc44f8ebee013bb2f9fe14d80b30db19b534c679056e4851ceadf5a5e8bf6"),
    "ffmpeg": ("https://ffmpeg.org/releases/ffmpeg-6.0.tar.xz", "57be87c22d9b49c112b6d24bc67d42508660e6b718b3db89c44e47e289137082"),
    "libass": ("https://github.com/libass/libass/releases/download/0.17.1/libass-0.17.1.tar.xz", "f0da0bbfba476c16ae3e1cfd862256d30915911f7abaa1b16ce62ee653192784"),
    "uchardet": ("https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz", "e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0"),
}
BASE_SHA256 = "d428641cc6c100de8234eae04e229966e46949eb73fcabd526a008a02e9bf968"
PATCH_NAME = "0001-mpv-0.36-preserve-eof-seek-state.patch"


def run(args, *, cwd=None, env=None):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fetch_source(name, work):
    url, expected = SOURCES[name]
    archive = work / (name + ".tar")
    print("Downloading", name, flush=True)
    with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as dest:
        shutil.copyfileobj(response, dest)
    if sha(archive) != expected:
        raise RuntimeError(f"Source checksum mismatch: {name}")
    dest = work / name
    dest.mkdir()
    with tarfile.open(archive) as source:
        for member in source.getmembers():
            resolved = (dest / member.name).resolve()
            if not resolved.is_relative_to(dest.resolve()) or member.issym() or member.islnk():
                raise RuntimeError(f"Unsafe source member: {member.name}")
        source.extractall(dest)
    roots = [p for p in dest.iterdir() if p.is_dir()]
    if len(roots) != 1:
        raise RuntimeError(f"Unexpected archive layout: {name}")
    return roots[0]


def plugin_path(app):
    config = app / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text())["packages"]
    item = next(p for p in packages if p["name"] == "media_kit_libs_ios_video")
    uri = urllib.parse.urlparse(item["rootUri"])
    return Path(urllib.parse.unquote(uri.path)) if uri.scheme == "file" else (config.parent / item["rootUri"]).resolve()


def uuid_arm64(path):
    result = output("xcrun", "dwarfdump", "--uuid", str(path))
    matches = re.findall(r"UUID: ([\da-fA-F-]+) \(arm64\)", result)
    if len(matches) != 1:
        raise RuntimeError(f"Expected one arm64 UUID: {result}")
    return matches[0].lower()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("Native iPad rebuild requires macOS and Xcode.")
    app = args.app_dir.resolve()
    scripts = Path(__file__).resolve().parent
    artifacts = app / "build/native-mpv"
    artifacts.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="slive-mpv-", dir=os.getenv("RUNNER_TEMP")))
    ios = plugin_path(app) / "ios"
    makefile = (ios / "Makefile").read_text()
    if "MPV_XCFRAMEWORKS_VERSION=0.6.8" not in makefile or BASE_SHA256 not in makefile:
        raise RuntimeError("Unexpected native dependency. Re-audit source/header ABI before rebuilding.")
    run(["make"], cwd=ios)
    framework_root = work / "frameworks"
    framework_root.mkdir()
    for xcframework in (ios / "Frameworks").glob("*.xcframework"):
        for framework in (xcframework / "ios-arm64").glob("*.framework"):
            shutil.copytree(framework, framework_root / framework.name)
    destination = ios / "Frameworks/Mpv.xcframework/ios-arm64/Mpv.framework/Mpv"
    original_uuid = uuid_arm64(destination)
    sources = {name: fetch_source(name, work) for name in SOURCES}
    mpv = sources["mpv"]
    patch = scripts / "patches" / PATCH_NAME
    for path in (patch, scripts / "patches/0002-enable-objc.patch"):
        run(["git", "apply", "--check", path], cwd=mpv)
        run(["git", "apply", path], cwd=mpv)
    playloop = (mpv / "player/playloop.c").read_text()
    queue_seek = playloop.split("void queue_seek(", 1)[1].split("switch (type)", 1)[0]
    if "KEEP_PLAYING" in queue_seek or "assert(mpctx->stop_play)" not in (mpv / "player/loadfile.c").read_text():
        raise RuntimeError("EOF fix verification failed or assertion was removed")

    include = work / "include"
    include.mkdir()
    pc = work / "pkgconfig"
    pc.mkdir()
    for name in ("libavcodec", "libavformat", "libavutil", "libavfilter", "libswresample", "libswscale"):
        source = sources["ffmpeg"] / name
        shutil.copytree(source, include / name)
        headers = (source / "version.h").read_text()
        major = source / "version_major.h"
        if major.exists():
            headers += major.read_text()
        macro = name.upper()
        parts = [re.search(rf"#define\s+{macro}_VERSION_{component}\s+(\d+)", headers).group(1) for component in ("MAJOR", "MINOR", "MICRO")]
        version = ".".join(parts)
        framework = name[3:].capitalize()
        write_pc(pc, name, version, framework, include, framework_root)
    # These two generated public FFmpeg ABI macros are fixed for arm64 iOS.
    (include / "libavutil/avconfig.h").write_text("#ifndef AVUTIL_AVCONFIG_H\n#define AVUTIL_AVCONFIG_H\n#define AV_HAVE_BIGENDIAN 0\n#define AV_HAVE_FAST_UNALIGNED 1\n#endif\n")
    shutil.copytree(sources["libass"] / "libass", include / "ass")
    shutil.copytree(sources["uchardet"] / "src", include / "uchardet")
    write_pc(pc, "libass", "0.17.1", "Ass", include, framework_root)
    write_pc(pc, "uchardet", "0.0.8", "Uchardet", include, framework_root)
    sdk = output("xcrun", "--sdk", "iphoneos", "--show-sdk-path")
    clang = output("xcrun", "--sdk", "iphoneos", "--find", "clang")
    clangpp = output("xcrun", "--sdk", "iphoneos", "--find", "clang++")
    flags = ["-arch", "arm64", "-isysroot", sdk, "-miphoneos-version-min=15.0"]
    link_flags = flags + ["-Wl,-headerpad_max_install_names", "-framework", "OpenGLES", "-framework", "CoreVideo", "-framework", "CoreFoundation", "-framework", "AVFoundation"]
    cross = work / "ios-arm64.ini"
    cross.write_text("\n".join([
        "[host_machine]", "system = 'darwin'", "cpu_family = 'aarch64'", "cpu = 'arm64'", "endian = 'little'",
        "[binaries]", f"c = {clang!r}", f"cpp = {clangpp!r}", f"objc = {clang!r}", f"objcpp = {clangpp!r}",
        f"ar = {output('xcrun', '--find', 'ar')!r}", f"strip = {output('xcrun', '--find', 'strip')!r}", "pkg-config = 'pkg-config'",
        "[properties]", "needs_exe_wrapper = true", f"pkg_config_libdir = {str(pc)!r}",
        "[built-in options]", f"c_args = {flags!r}", f"cpp_args = {flags!r}", f"objc_args = {flags!r}",
        f"c_link_args = {link_flags!r}", f"objc_link_args = {link_flags!r}",
    ]) + "\n")
    env = dict(os.environ, PKG_CONFIG_PATH="", PKG_CONFIG_LIBDIR=str(pc))
    build = work / "build"
    options = ["-Dauto_features=disabled", "-Dlibmpv=true", "-Dcplayer=false", "-Dgpl=false", "-Dbuild-date=false", "-Dtests=false", "-Db_ndebug=false", "-Db_lundef=true", "-Diconv=enabled", "-Duchardet=enabled", "-Dzlib=enabled", "-Dgl=enabled", "-Dplain-gl=enabled", "-Daudiounit=enabled", "-Dios-gl=enabled"]
    try:
        run(["meson", "setup", build, mpv, "--cross-file", cross, "--buildtype=debugoptimized", *options], env=env)
        run(["meson", "compile", "-C", build, "-j", str(min(os.cpu_count() or 4, 8))], env=env)
    finally:
        log = build / "meson-logs/meson-log.txt"
        if log.exists():
            shutil.copyfile(log, artifacts / "meson-log.txt")
        shutil.copyfile(cross, artifacts / "ios-arm64.ini")
    libraries = [p for p in build.glob("libmpv*.dylib") if not p.is_symlink()]
    if len(libraries) != 1:
        raise RuntimeError(f"Unexpected libmpv outputs: {libraries}")
    binary = libraries[0]
    run(["xcrun", "install_name_tool", "-id", "@rpath/Mpv.framework/Mpv", binary])
    links = output("xcrun", "otool", "-L", str(binary))
    (artifacts / "linked-libraries.txt").write_text(links)
    for line in links.splitlines()[1:]:
        dependency = line.strip().split(" (", 1)[0]
        if not dependency.startswith(("@rpath/", "/System/Library/", "/usr/lib/")):
            raise RuntimeError(f"Host library leaked into iPad build: {dependency}")
    dsym = artifacts / "Mpv.framework.dSYM"
    run(["xcrun", "dsymutil", binary, "-o", dsym])
    dwarf_files = list((dsym / "Contents/Resources/DWARF").iterdir())
    if len(dwarf_files) != 1 or not dwarf_files[0].is_file():
        raise RuntimeError("Expected one native DWARF image")
    dwarf_files[0].rename(dsym / "Contents/Resources/DWARF/Mpv")
    binary_uuid = uuid_arm64(binary)
    dsym_uuid = uuid_arm64(dsym)
    if binary_uuid == original_uuid or binary_uuid != dsym_uuid:
        raise RuntimeError("Rebuilt binary/symbol UUID verification failed")
    shutil.copyfile(binary, destination)
    # CocoaPods invokes make again. Sources/frameworks have already been prepared
    # and verified in this isolated job; prevent a later extraction undoing it.
    podspec = ios / "media_kit_libs_ios_video.podspec"
    podspec.write_text(podspec.read_text().replace('system("make")', '# Native frameworks prepared by Slive patched-mpv build'))
    manifest = {
        "binary_uuid_arm64": binary_uuid, "dsym_uuid_arm64": dsym_uuid,
        "original_uuid_arm64": original_uuid, "binary_sha256": sha(binary), "patch_sha256": sha(patch),
        "source_version": "mpv 0.36.0", "upstream_fix_commit": "d59f4fd3ec141693da4f7f6677aa729e1bb92f4d",
        "native_dependency_version": "0.6.8", "native_dependency_sha256": BASE_SHA256,
        "target": "arm64-apple-ios15.0", "sources": SOURCES, "toolchain": output("xcodebuild", "-version"),
    }
    (artifacts / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copyfile(patch, artifacts / PATCH_NAME)
    print("Prepared patched iPad MPV", binary_uuid, flush=True)


def write_pc(pc, name, version, framework, include, frameworks):
    if not (frameworks / (framework + ".framework") / framework).exists():
        raise RuntimeError(f"Missing pinned iOS dependency framework: {framework}")
    extra_include = f" -I{include / 'uchardet'}" if name == "uchardet" else ""
    (pc / (name + ".pc")).write_text(
        f"Name: {name}\nDescription: Pinned iOS dependency\nVersion: {version}\n"
        f"Cflags: -I{include}{extra_include}\nLibs: -F{frameworks} -framework {framework}\n"
    )


if __name__ == "__main__":
    main()
