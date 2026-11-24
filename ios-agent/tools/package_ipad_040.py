# SPDX-License-Identifier: Apache-2.0
"""Reproducible, source-only delta from the verified delivered console baseline.

Never reads enrollment/signing files or replaces an existing delivery. Run with
--verify after building to recheck the ZIP, baseline and current source tree.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

from package_mac import EXCLUDED, validate_project

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
BASE = DIST / "ipad-040-base"
NAME = "MeshCentral-iOS-0.4.0-ipad-assistance-update"
ARCHIVE = DIST / (NAME + ".zip")
MANIFEST = DIST / "ipad-040-delivery.json"
SNAPSHOT = DIST / "ipad-040-delivered"
PROJECT = "apple/App/MeshCentralIOS.xcodeproj/project.pbxproj"
MANUAL = {PROJECT: "Set app and extension Version (MARKETING_VERSION) to 0.4.0; increase their Build together on the Mac. See docs/ipad-040-update-fr.md."}
EXTENSIONS = {".rs", ".swift", ".h", ".modulemap", ".cjs", ".js", ".css", ".html", ".cs", ".ps1", ".py", ".sh", ".md", ".toml", ".lock", ".json", ".png", ".pbxproj", ".plist", ".entitlements", ".xcscheme", ".patch"}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sources():
    files = {}
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if set(relative.parts) & EXCLUDED or not path.is_file():
            continue
        assert not path.is_symlink(), relative
        if path.name not in {"LICENSE", ".gitignore"} and path.suffix not in EXTENSIONS:
            raise AssertionError("Unreviewed file in source tree: " + str(relative))
        data = path.read_bytes()
        if path.suffix != ".png":
            # Parser rejection tests contain the header alone. Reject actual
            # PEM-like bodies, including source literals with escaped newlines.
            assert not re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----(?:\s|\\n)+[A-Za-z0-9+/=\\\s]{64,}", data), relative
            assert not re.search(rb"[?&]c=[A-Za-z0-9@$%_=+/-]{80,}", data), relative
        files[relative.as_posix()] = data
    return dict(sorted(files.items()))


def baseline():
    base = json.loads((BASE / "baseline.json").read_text(encoding="utf-8"))
    delivery = json.loads((DIST / "assistance-console-delivery.json").read_text(encoding="utf-8"))
    assert base["base_archive"] == delivery["archive"]
    assert base["base_sha256"] == delivery["sha256"] == digest((DIST / delivery["archive"]).read_bytes())
    old = json.loads((DIST / "console-base/baseline.json").read_text(encoding="utf-8"))
    assert base["files"] == old | delivery["files"]
    with zipfile.ZipFile(DIST / delivery["archive"]) as archive:
        expected = set(delivery["files"])
        assert set(archive.namelist()) == expected
        for name, checksum in delivery["files"].items():
            assert digest(archive.read(name)) == checksum
    for name, checksum in base["files"].items():
        assert digest((BASE / name).read_bytes()) == checksum, name
    return base


def payload():
    base = baseline()
    files = sources()
    removed = sorted(set(base["files"]) - set(files))
    assert not removed, "Removals need deliberate instructions: " + str(removed)
    # Configured Xcode project never enters the delta. This specific local change
    # is represented by precise manual edits in the installation guide.
    old_project = (BASE / PROJECT).read_text(encoding="utf-8")
    assert files[PROJECT].decode().replace("\r\n", "\n") == old_project.replace("\r\n", "\n").replace('"MARKETING_VERSION" = "0.3.0"', '"MARKETING_VERSION" = "0.4.0"')
    changed = {n: data for n, data in files.items() if n not in MANUAL and digest(data) != base["files"].get(n)}
    assert not any(n.endswith((".pbxproj", ".entitlements", ".plist", ".p12", ".mobileprovision")) for n in changed)
    info = {"license": "Apache-2.0", "version": "0.4.0", "kind": "incremental-source-validation-candidate",
            "date": "2026-11-21", "base_archive": base["base_archive"], "base_sha256": base["base_sha256"],
            "upstream_revision": "67aff175f6d1093b1a81f8e9230607854d3fbaa6",
            "upstream_head_observed": "412e2aeb3f209df1c1a238de974d3a44185d7006", "upstream_integrated": False,
            "apple_build_executed": False, "physical_device_test_executed": False, "browser_rendering_verified": False,
            "wire_protocol": "iosAssist v1", "plugin_version": "0.1.0", "external_dependencies_added": 0,
            "manual_edits": MANUAL, "removed": removed, "renamed": [], "changed_files": list(changed)}
    changed["release-0.4.0.json"] = (json.dumps(info, indent=2, ensure_ascii=False) + "\n").encode()
    sums = {n: digest(data) for n, data in changed.items()}
    changed["SHA256SUMS-0.4.0.json"] = (json.dumps(sums, indent=2) + "\n").encode()
    return files, changed, info


def verify():
    files, expected, _ = payload()
    record = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert digest(ARCHIVE.read_bytes()) == record["sha256"]
    assert ARCHIVE.stat().st_size == record["bytes"]
    assert record["files"] == {n: digest(data) for n, data in expected.items()}
    assert record["source_files"] == {n: digest(data) for n, data in files.items()}
    with zipfile.ZipFile(ARCHIVE) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {NAME + "/" + n for n in expected}
        for name, data in expected.items():
            assert not Path(name).is_absolute() and ".." not in Path(name).parts
            assert archive.read(NAME + "/" + name) == data, name
    for name, data in files.items():
        assert (SNAPSHOT / name).read_bytes() == data, name
    print(f"PASS: {len(expected) - 2} changed/new source files, 2 delivery metadata files; archive, source snapshot and base verified.")


def build():
    assert not ARCHIVE.exists() and not MANIFEST.exists() and not SNAPSHOT.exists(), "Preserve previous artifacts; use --verify."
    validate_project(ROOT)
    files, content, info = payload()
    with zipfile.ZipFile(ARCHIVE, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(content.items()):
            entry = zipfile.ZipInfo(NAME + "/" + name, date_time=(2026, 11, 21, 12, 0, 0))
            entry.create_system = 3
            entry.external_attr = (0o100755 if name.endswith(".sh") else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    for name in files:
        target = SNAPSHOT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    record = {"archive": ARCHIVE.name, "sha256": digest(ARCHIVE.read_bytes()), "bytes": ARCHIVE.stat().st_size,
              "base": info["base_archive"], "base_sha256": info["base_sha256"], "manual_edits": MANUAL,
              "files": {n: digest(data) for n, data in content.items()}, "source_files": {n: digest(data) for n, data in files.items()}}
    MANIFEST.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    verify()
    print(str(ARCHIVE))
    print("SHA256 " + record["sha256"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    verify() if args.verify else build()
