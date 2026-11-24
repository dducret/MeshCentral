# SPDX-License-Identifier: Apache-2.0
"""Maintainer tool: generate the checked-in Xcode project with only Python stdlib."""
import hashlib
import json
import plistlib
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apple/App"
PROJECT = APP / "MeshCentralIOS.xcodeproj"
objects = {}


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def obj(label, isa, **fields):
    key = uid(label)
    objects[key] = dict(isa=isa, **fields)
    return key


def configs(name, settings):
    result = []
    for mode in ("Debug", "Release"):
        values = dict(settings)
        if name == "project":
            values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O",
                          DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym",
                          ONLY_ACTIVE_ARCH="YES" if mode == "Debug" else "NO",
                          ENABLE_TESTABILITY="YES" if mode == "Debug" else "NO")
            if mode == "Debug":
                values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = ["$(inherited)", "DEBUG"]
        result.append(obj(f"{name}-{mode}", "XCBuildConfiguration", name=mode, buildSettings=values))
    return obj(f"{name}-config", "XCConfigurationList", buildConfigurations=result,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def source_phase(name, files):
    refs, builds = [], []
    for file in files:
        ref = obj(file, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=file, sourceTree="<group>")
        refs.append(ref)
        builds.append(obj(name + file + "-build", "PBXBuildFile", fileRef=ref))
    return refs, obj(name + "-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647,
                     files=builds, runOnlyForDeploymentPostprocessing=0)


app_files = [p.relative_to(APP).as_posix() for p in sorted((APP / "Sources").glob("*.swift"))]
app_files += ["../Sources/MeshCentralAgent/" + p.name for p in sorted((ROOT / "apple/Sources/MeshCentralAgent").glob("*.swift"))]
test_files = ["../Tests/MeshCentralAgentTests/" + p.name for p in sorted((ROOT / "apple/Tests/MeshCentralAgentTests").glob("*.swift"))]
app_refs, app_sources = source_phase("app", app_files)
test_refs, test_sources = source_phase("tests", test_files)
extension_files = ["../Broadcast/SampleHandler.swift"] + ["../Sources/MeshCentralAgent/" + p.name for p in sorted((ROOT / "apple/Sources/MeshCentralAgent").glob("*.swift"))]
extension_refs, extension_sources = source_phase("broadcast", extension_files)
extension_product = obj("broadcast-product", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0,
                        path="MeshCentralBroadcast.appex", sourceTree="BUILT_PRODUCTS_DIR")
product = obj("app-product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
              path="MeshCentralIOS.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = obj("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0,
                   path="MeshCentralIOSTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
lib = obj("rust-lib", "PBXFileReference", explicitFileType="archive.ar", path="libmeshcentral_ios_bridge.a", sourceTree="BUILT_PRODUCTS_DIR")
lib_build = obj("rust-link", "PBXBuildFile", fileRef=lib)
frameworks = obj("app-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[lib_build], runOnlyForDeploymentPostprocessing=0)
test_frameworks = obj("test-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
rust_phase = obj("rust-build", "PBXShellScriptBuildPhase", name="Build Rust core (offline)", buildActionMask=2147483647,
                 files=[], inputPaths=[], outputPaths=["$(BUILT_PRODUCTS_DIR)/libmeshcentral_ios_bridge.a"],
                 runOnlyForDeploymentPostprocessing=0, alwaysOutOfDate=1, shellPath="/bin/sh",
                 shellScript='/bin/sh "${SRCROOT}/Scripts/build-rust.sh"\n')
assets_ref = obj("app-assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog",
                 path="MeshCentralAssets.xcassets", sourceTree="<group>")
assets_build = obj("app-assets-build", "PBXBuildFile", fileRef=assets_ref)
resources = obj("app-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[assets_build], runOnlyForDeploymentPostprocessing=0)
extension_lib = obj("broadcast-rust-lib", "PBXFileReference", explicitFileType="archive.ar", path="libmeshcentral_ios_broadcast.a", sourceTree="BUILT_PRODUCTS_DIR")
extension_frameworks = obj("broadcast-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647,
    files=[obj("broadcast-rust-link", "PBXBuildFile", fileRef=extension_lib)], runOnlyForDeploymentPostprocessing=0)
extension_rust = obj("broadcast-rust-build", "PBXShellScriptBuildPhase", name="Build broadcast Rust core (offline)", buildActionMask=2147483647,
    files=[], inputPaths=[], outputPaths=["$(BUILT_PRODUCTS_DIR)/libmeshcentral_ios_broadcast.a"], runOnlyForDeploymentPostprocessing=0,
    alwaysOutOfDate=1, shellPath="/bin/sh", shellScript='/bin/sh "${SRCROOT}/Scripts/build-rust.sh"\n')
embed_extension = obj("embed-broadcast", "PBXCopyFilesBuildPhase", name="Embed Broadcast Extension", buildActionMask=2147483647,
    dstPath="", dstSubfolderSpec=13, runOnlyForDeploymentPostprocessing=0,
    files=[obj("embed-broadcast-build", "PBXBuildFile", fileRef=extension_product, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})])
plist_ref = obj("Info.plist", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
scripts = [obj("script-" + name, "PBXFileReference", lastKnownFileType="text.script.sh", path="Scripts/" + name, sourceTree="<group>")
           for name in ("build-rust.sh", "prepare-mac.sh")]
products = obj("products", "PBXGroup", name="Products", children=[product, test_product, extension_product, lib, extension_lib], sourceTree="<group>")
extra_refs = [obj("extra-" + name, "PBXFileReference", lastKnownFileType="text.plist.xml", path=name, sourceTree="<group>")
              for name in ["MeshCentral.entitlements", "../Broadcast/Info.plist", "../Broadcast/MeshCentralBroadcast.entitlements"]]
group = obj("main-group", "PBXGroup", children=list(dict.fromkeys(app_refs + extension_refs + test_refs + [plist_ref, assets_ref] + extra_refs + scripts + [products])), sourceTree="<group>")
common = dict(CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", SDKROOT="iphoneos",
              IPHONEOS_DEPLOYMENT_TARGET="16.0", SWIFT_VERSION="5.0", SWIFT_STRICT_CONCURRENCY="minimal",
              ENABLE_USER_SCRIPT_SANDBOXING="NO", CODE_SIGN_STYLE="Automatic", DEVELOPMENT_TEAM="",
              SUPPORTED_PLATFORMS="iphoneos iphonesimulator", TARGETED_DEVICE_FAMILY="1,2",
              SUPPORTS_MACCATALYST="NO", SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD="NO",
              SWIFT_INCLUDE_PATHS=['$(SRCROOT)/../../bridge/include'],
              HEADER_SEARCH_PATHS=['$(SRCROOT)/../../bridge/include'], MESH_HOST_BUNDLE_ID="org.meshcentral.iosagent.demo")
project_config = configs("project", common)
app_config = configs("app", dict(PRODUCT_BUNDLE_IDENTIFIER="$(MESH_HOST_BUNDLE_ID)", PRODUCT_NAME="$(TARGET_NAME)",
    INFOPLIST_FILE="Info.plist", GENERATE_INFOPLIST_FILE="NO", CURRENT_PROJECT_VERSION="3", MARKETING_VERSION="0.5.2",
    CODE_SIGN_ENTITLEMENTS="MeshCentral.entitlements", ASSETCATALOG_COMPILER_APPICON_NAME="MeshCentralAppIcon",
    LIBRARY_SEARCH_PATHS=["$(inherited)", "$(BUILT_PRODUCTS_DIR)"], OTHER_LDFLAGS=["$(inherited)", "-lc++", "-liconv"],
    LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"], ENABLE_PREVIEWS="YES"))
extension_config = configs("broadcast", dict(PRODUCT_BUNDLE_IDENTIFIER="$(MESH_HOST_BUNDLE_ID).Broadcast", PRODUCT_NAME="$(TARGET_NAME)",
    INFOPLIST_FILE="../Broadcast/Info.plist", GENERATE_INFOPLIST_FILE="NO", CURRENT_PROJECT_VERSION="3", MARKETING_VERSION="0.5.2",
    CODE_SIGN_ENTITLEMENTS="../Broadcast/MeshCentralBroadcast.entitlements", APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES",
    RUST_OUTPUT_NAME="libmeshcentral_ios_broadcast.a", LIBRARY_SEARCH_PATHS=["$(inherited)", "$(BUILT_PRODUCTS_DIR)"],
    OTHER_LDFLAGS=["$(inherited)", "-lc++", "-liconv"], LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]))
extension_target = obj("broadcast-target", "PBXNativeTarget", buildConfigurationList=extension_config,
    buildPhases=[extension_rust, extension_sources, extension_frameworks], buildRules=[], dependencies=[], name="MeshCentralBroadcast",
    productName="MeshCentralBroadcast", productReference=extension_product, productType="com.apple.product-type.app-extension")
extension_proxy = obj("broadcast-proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
    remoteGlobalIDString=extension_target, remoteInfo="MeshCentralBroadcast")
extension_dependency = obj("broadcast-dependency", "PBXTargetDependency", target=extension_target, targetProxy=extension_proxy)
test_config = configs("tests", dict(PRODUCT_BUNDLE_IDENTIFIER="$(MESH_HOST_BUNDLE_ID).tests", PRODUCT_NAME="$(TARGET_NAME)",
    GENERATE_INFOPLIST_FILE="YES", TEST_HOST="$(BUILT_PRODUCTS_DIR)/MeshCentralIOS.app/MeshCentralIOS",
    BUNDLE_LOADER="$(TEST_HOST)", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]))
app_target = obj("app-target", "PBXNativeTarget", buildConfigurationList=app_config,
    buildPhases=[rust_phase, app_sources, frameworks, resources, embed_extension], buildRules=[], dependencies=[extension_dependency], name="MeshCentralIOS",
    productName="MeshCentralIOS", productReference=product, productType="com.apple.product-type.application")
proxy = obj("host-proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
            remoteGlobalIDString=app_target, remoteInfo="MeshCentralIOS")
dependency = obj("test-host-dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
test_target = obj("tests-target", "PBXNativeTarget", buildConfigurationList=test_config,
    buildPhases=[test_sources, test_frameworks], buildRules=[], dependencies=[dependency], name="MeshCentralIOSTests",
    productName="MeshCentralIOSTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
project = obj("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600",
    "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"}, test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}}},
    buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="fr", hasScannedForEncodings=0,
    knownRegions=["fr", "en", "Base"], mainGroup=group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, test_target, extension_target])


def encode(value, level=0):
    pad = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join(pad + "\t" + json.dumps(k) + " = " + encode(v, level + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + encode(v, level + 1) + ",\n" for v in value) + pad + ")"
    return str(value) if isinstance(value, int) else json.dumps(value)


PROJECT.mkdir(parents=True, exist_ok=True)
payload = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n// SPDX-License-Identifier: Apache-2.0\n" + encode(payload) + "\n", encoding="utf-8", newline="\n")
info = dict(CFBundleDevelopmentRegion="fr", CFBundleDisplayName="MeshCentral", CFBundleExecutable="$(EXECUTABLE_NAME)",
            CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)", CFBundleInfoDictionaryVersion="6.0", CFBundleName="$(PRODUCT_NAME)",
            CFBundlePackageType="APPL", CFBundleShortVersionString="$(MARKETING_VERSION)", CFBundleVersion="$(CURRENT_PROJECT_VERSION)",
            MeshCentralHostBundleID="$(MESH_HOST_BUNDLE_ID)", MeshCentralKeychainGroup="$(AppIdentifierPrefix)$(MESH_HOST_BUNDLE_ID)",
            MeshCentralAppGroup="group.$(MESH_HOST_BUNDLE_ID)",
            LSRequiresIPhoneOS=True, UILaunchScreen={}, UIApplicationSupportsIndirectInputEvents=True,
            NSLocalNetworkUsageDescription="Se connecter à votre serveur MeshCentral lorsqu’il se trouve sur le réseau local.",
            NSMicrophoneUsageDescription="Parler avec le technicien dans une conversation MeshMessenger que vous avez acceptée.",
            UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
            **{"UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]})
plist = plistlib.dumps(info).replace(b"<plist version", b"<!-- SPDX-License-Identifier: Apache-2.0 -->\n<plist version", 1)
(APP / "Info.plist").write_bytes(plist)
extension_info = {key: value for key, value in info.items() if key.startswith("CFBundle") or key.startswith("MeshCentral")}
extension_info.update(CFBundleDisplayName="MeshCentral Screen", CFBundlePackageType="XPC!", NSExtension={
    "NSExtensionPointIdentifier": "com.apple.broadcast-services-upload",
    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SampleHandler",
    "RPBroadcastProcessMode": "RPBroadcastProcessModeSampleBuffer"})
for path, value in [(ROOT / "apple/Broadcast/Info.plist", extension_info),
                    (APP / "MeshCentral.entitlements", {"keychain-access-groups": ["$(AppIdentifierPrefix)$(MESH_HOST_BUNDLE_ID)"]}),
                    (ROOT / "apple/Broadcast/MeshCentralBroadcast.entitlements", {"keychain-access-groups": ["$(AppIdentifierPrefix)$(MESH_HOST_BUNDLE_ID)"]})]:
    if path.suffix == ".entitlements":
        value["com.apple.security.application-groups"] = ["group.$(MESH_HOST_BUNDLE_ID)"]
    path.write_bytes(plistlib.dumps(value).replace(b"<plist version", b"<!-- SPDX-License-Identifier: Apache-2.0 -->\n<plist version", 1))
scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")


def reference(parent, target, name, suffix):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                  BuildableName=name + suffix, BlueprintName=name, ReferencedContainer="container:MeshCentralIOS.xcodeproj")


build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build, "BuildActionEntries")
entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
reference(entry, app_target, "MeshCentralIOS", ".app")
test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                     selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testable = ET.SubElement(ET.SubElement(test, "Testables"), "TestableReference", skipped="NO")
reference(testable, test_target, "MeshCentralIOSTests", ".xctest")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                       selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, "MeshCentralIOS", ".app")
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, "MeshCentralIOS", ".app")
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme)
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "MeshCentralIOS.xcscheme").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!-- SPDX-License-Identifier: Apache-2.0 -->\n' + ET.tostring(scheme, encoding="unicode") + "\n", encoding="utf-8", newline="\n")
for relative in app_files + test_files + extension_files:
    assert (APP / relative).is_file(), relative
assert len(objects) == len(set(objects))
print(f"Generated Xcode project: {len(app_files)} app sources, {len(test_files)} test sources, broadcast extension; three targets.")
