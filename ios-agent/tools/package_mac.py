# SPDX-License-Identifier: Apache-2.0
"""Build and structurally verify a source-only Mac ZIP, using Python stdlib."""
import hashlib
import json
import plistlib
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "MeshCentral-iOS/"
OUTPUT = ROOT / "dist/MeshCentral-iOS-Assistance-0.5.2-sdk26.zip"
EXTENSIONS = {".html", ".js", ".css", ".rs", ".swift", ".h", ".modulemap", ".cjs", ".cs", ".ps1", ".py", ".sh", ".md", ".toml", ".pbxproj", ".plist", ".xcscheme", ".entitlements", ".patch"}
EXCLUDED = {"target", "dist", "Artifacts", ".build", ".swiftpm", "xcuserdata", "DerivedData", "__pycache__"}


def openstep(text):
    """Read the generated OpenStep subset; validate the actual file, not its model."""
    text = re.sub(r"//[^\n]*", "", text)
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[0-9]+', text)
    position = 0

    def take(expected=None):
        nonlocal position
        value = tokens[position]
        position += 1
        if expected is not None:
            assert value == expected, (value, expected)
        return value

    def parse():
        token = take()
        if token == "{":
            result = {}
            while tokens[position] != "}":
                key = json.loads(take())
                take("=")
                assert key not in result
                result[key] = parse()
                take(";")
            take("}")
            return result
        if token == "(":
            result = []
            while tokens[position] != ")":
                result.append(parse())
                take(",")
            take(")")
            return result
        return json.loads(token)

    result = parse()
    assert position == len(tokens)
    return result


def validate_project(root):
    app = root / "apple/App"
    project = app / "MeshCentralIOS.xcodeproj"
    document = openstep((project / "project.pbxproj").read_text(encoding="utf-8"))
    objects = document["objects"]
    main = objects[document["rootObject"]]
    assert main["isa"] == "PBXProject"
    assert len(main["targets"]) == 3
    sources = set()
    for value in objects.values():
        if value["isa"] == "PBXFileReference" and value["sourceTree"] == "<group>":
            path = (app / value["path"]).resolve()
            assert path.is_relative_to(root.resolve()), path
            if value.get("lastKnownFileType") == "folder.assetcatalog":
                assert path.is_dir() and (path / "Contents.json").is_file(), path
            else:
                assert path.is_file(), path
        if value["isa"] == "PBXBuildFile":
            assert value["fileRef"] in objects
        if value["isa"] == "PBXSourcesBuildPhase":
            for build in value["files"]:
                sources.add(objects[objects[build]["fileRef"]]["path"])
    expected = {p.relative_to(app).as_posix() for p in (app / "Sources").glob("*.swift")}
    expected |= {"../Sources/MeshCentralAgent/" + p.name for p in (root / "apple/Sources/MeshCentralAgent").glob("*.swift")}
    expected |= {"../Tests/MeshCentralAgentTests/" + p.name for p in (root / "apple/Tests/MeshCentralAgentTests").glob("*.swift")}
    expected.add("../Broadcast/SampleHandler.swift")
    assert sources == expected, (sources, expected)
    native_sources = {"../Sources/MeshCentralAgent/" + p.name for p in (root / "apple/Sources/MeshCentralAgent").glob("*.swift")}
    targets = {objects[key]["name"]: objects[key] for key in main["targets"]}
    extension_target = targets["MeshCentralBroadcast"]
    extension_sources = set()
    for phase in extension_target["buildPhases"]:
        if objects[phase]["isa"] == "PBXSourcesBuildPhase":
            extension_sources |= {objects[objects[build]["fileRef"]]["path"] for build in objects[phase]["files"]}
    assert extension_sources == native_sources | {"../Broadcast/SampleHandler.swift"}
    assert objects[extension_target["buildPhases"][0]]["outputPaths"] == ["$(BUILT_PRODUCTS_DIR)/libmeshcentral_ios_broadcast.a"]
    target = next(objects[key] for key in main["targets"] if objects[key]["name"] == "MeshCentralIOS")
    assert objects[target["buildPhases"][0]]["isa"] == "PBXShellScriptBuildPhase"
    assert objects[target["buildPhases"][0]]["outputPaths"] == ["$(BUILT_PRODUCTS_DIR)/libmeshcentral_ios_bridge.a"]
    assert any(objects[phase]["isa"] == "PBXCopyFilesBuildPhase" and objects[phase]["dstSubfolderSpec"] == 13 for phase in target["buildPhases"])
    assert any(objects[objects[dep]["target"]]["name"] == "MeshCentralBroadcast" for dep in target["dependencies"])
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert "NSAppTransportSecurity" not in info
    assert "audio" in info["UIBackgroundModes"] and "screen-capture" not in info["UIBackgroundModes"]
    for native in (target, extension_target):
        for key in objects[native["buildConfigurationList"]]["buildConfigurations"]:
            flags = objects[key]["buildSettings"]["OTHER_LDFLAGS"]
            assert all("ScreenCaptureKit" not in flag for flag in flags), objects[key]["name"]
    assert all("ScreenCaptureKit.framework" not in value.get("path", "") for value in objects.values())
    extension = plistlib.loads((root / "apple/Broadcast/Info.plist").read_bytes())
    assert "NSAppTransportSecurity" not in extension and "UIBackgroundModes" not in extension
    assert extension["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.broadcast-services-upload"
    # ReplayKit's process mode is a direct child of NSExtension. A nested
    # NSExtensionAttributes value is ignored by upload validation.
    assert extension["NSExtension"].get("RPBroadcastProcessMode") == "RPBroadcastProcessModeSampleBuffer", "Broadcast process mode must be directly inside NSExtension"
    assert "RPBroadcastProcessMode" not in extension["NSExtension"].get("NSExtensionAttributes", {})
    assert "RPBroadcastProcessMode" not in extension
    assert plistlib.loads((app / "MeshCentral.entitlements").read_bytes()) == plistlib.loads((root / "apple/Broadcast/MeshCentralBroadcast.entitlements").read_bytes())
    entitlements = plistlib.loads((app / "MeshCentral.entitlements").read_bytes())
    assert entitlements["com.apple.security.application-groups"] == ["group.$(MESH_HOST_BUNDLE_ID)"]
    assert info["MeshCentralAppGroup"] == extension["MeshCentralAppGroup"] == "group.$(MESH_HOST_BUNDLE_ID)"
    assert "com.apple.security.application-groups" not in extension
    scheme = ET.parse(project / "xcshareddata/xcschemes/MeshCentralIOS.xcscheme")
    for ref in scheme.findall(".//BuildableReference"):
        assert ref.attrib["BlueprintIdentifier"] in main["targets"]
    assert (root / "bridge/include/module.modulemap").is_file()
    print(f"PASS: Xcode references, {len(sources)} Swift source files, scheme, plist and build phase.")


def collect():
    paths = [ROOT / name for name in ("Cargo.toml", "Cargo.lock", "LICENSE", ".gitignore", "README.md", "README-MAC.md")]
    for directory in ("src", "bridge", "tests", "examples", "docs", "tools", "apple", "operator", "plugin"):
        for path in (ROOT / directory).rglob("*"):
            if not path.is_file() or any(part in EXCLUDED for part in path.relative_to(ROOT).parts):
                continue
            is_asset = "MeshCentralAssets.xcassets" in path.parts and path.suffix in {".json", ".png"}
            if path.suffix in EXTENSIONS or path.name in {".gitignore", "LICENSE"} or is_asset or ("plugin" in path.parts and path.name == "config.json"):
                paths.append(path)
    payload = {}
    for path in sorted(set(paths)):
        assert not path.is_symlink()
        name = path.relative_to(ROOT).as_posix()
        if name == "README.md":
            name = "DEVELOPMENT.md"
        elif name == "README-MAC.md":
            # Preserve both the landing page and development-doc relative links.
            payload["README.md"] = path.read_text(encoding="utf-8").replace("\r\n", "\n").encode()
        data = path.read_bytes() if path.suffix == ".png" else path.read_text(encoding="utf-8").replace("\r\n", "\n").encode()
        assert not re.search(rb"[?&]c=[A-Za-z0-9@$%_=+/-]{80,}", data), "Possible real invitation token: " + name
        payload[name] = data
    payload["release-info.json"] = (json.dumps({
        "license": "Apache-2.0", "version": "0.5.2", "package": "source-only Xcode attended assistance prototype",
        "date": "2026-11-24", "upstream_revision": "67aff175f6d1093b1a81f8e9230607854d3fbaa6",
        "minimum_ios": "16.0", "minimum_rust": "1.99", "external_cargo_dependencies": 0,
        "apple_build_executed": False, "physical_device_test_executed": False,
        "screen_sharing_implemented": True, "screen_sharing_device_verified": False, "invitation_token_included": False,
        "features": ["attended_chat", "adaptive_jpeg", "still_capture_annotations", "selected_documents", "connection_diagnostics", "guided_assistance", "integrated_console", "broadcast_revocation_watchdog", "ipad_layout", "confirmed_transfer_progress", "foreground_meshmessenger_audio_candidate"],
        "operator_panel_deployed": False, "external_javascript_dependencies": 0,
        "previous_version_user_report": "Physical iPad sharing and foreground Messenger audio reported on preceding builds; background audio requires device acceptance",
        "checks": ["Rust fmt/clippy/tests on Windows", "original-source license inventory",
                   "Xcode project structural validation (not xcodebuild)", "archive checksums and isolated extraction"]
    }, indent=2) + "\n").encode()
    manifest = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())}
    payload["SHA256SUMS.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    return payload


def build():
    validate_project(ROOT)
    files = collect()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            item = zipfile.ZipInfo(PREFIX + name, date_time=(2026, 11, 21, 12, 0, 0))
            item.create_system = 3
            item.external_attr = (0o100755 if name.endswith(".sh") else 0o100644) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, data)
    with zipfile.ZipFile(OUTPUT) as archive:
        assert archive.testzip() is None
        manifest = json.loads(archive.read(PREFIX + "SHA256SUMS.json"))
        assert set(archive.namelist()) == {PREFIX + n for n in manifest} | {PREFIX + "SHA256SUMS.json"}
        for name, digest in manifest.items():
            assert ".." not in Path(name).parts and not Path(name).is_absolute()
            data = archive.read(PREFIX + name)
            assert hashlib.sha256(data).hexdigest() == digest
            if name.endswith(".sh"):
                assert b"\r" not in data
                assert (archive.getinfo(PREFIX + name).external_attr >> 16) & 0o111
    print(f"PASS: {len(files)} files, manifest verified, source-only ZIP, executable LF shell scripts.")
    print(str(OUTPUT))
    print("SHA256 " + hashlib.sha256(OUTPUT.read_bytes()).hexdigest())


if __name__ == "__main__":
    build()
