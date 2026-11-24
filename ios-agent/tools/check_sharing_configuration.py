# SPDX-License-Identifier: Apache-2.0
"""Read-only check of app/ReplayKit sharing settings in a signed Mac archive.

Uses Python stdlib and Apple's codesign inspection tool. Never changes an
archive, profile or signature. Reports fixed diagnostic codes, not identifiers,
credentials, enrollment URLs, or raw tool output.
"""
import argparse
import plistlib
import subprocess
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError


def resolved(value):
    return (isinstance(value, str) and bool(value) and value == value.strip()
            and "$(" not in value and "${" not in value)


def strings(value):
    return set(v for v in value if isinstance(v, str)) if isinstance(value, list) else set()


def check_configuration(app_info, extension_info, app_rights, extension_rights):
    issues = []
    for label, info, rights in (("APP", app_info, app_rights), ("EXTENSION", extension_info, extension_rights)):
        group = info.get("MeshCentralAppGroup")
        groups = strings(rights.get("com.apple.security.application-groups"))
        if not resolved(group) or not group.startswith("group.") or len(group) <= 6:
            issues.append(f"{label}_APP_GROUP_INVALID: MeshCentralAppGroup est absent ou non résolu dans le Info.plist compilé.")
        elif group not in groups:
            issues.append(f"{label}_APP_GROUP_NOT_AUTHORIZED: MeshCentralAppGroup ne figure pas dans les App Groups de la signature.")
        keychain = info.get("MeshCentralKeychainGroup")
        # Apple also authorizes the application identifier and App Groups as
        # Keychain access groups, even without an explicit keychain list entry.
        allowed = strings(rights.get("keychain-access-groups")) | groups
        app_id = rights.get("application-identifier")
        if isinstance(app_id, str):
            allowed.add(app_id)
        if not resolved(keychain):
            issues.append(f"{label}_KEYCHAIN_GROUP_INVALID: MeshCentralKeychainGroup est absent ou non résolu.")
        elif keychain not in allowed:
            issues.append(f"{label}_KEYCHAIN_NOT_AUTHORIZED: le groupe de trousseau demandé n’est pas autorisé par la signature.")
    for key, code in (("MeshCentralAppGroup", "APP_GROUP_MISMATCH"),
                      ("MeshCentralKeychainGroup", "KEYCHAIN_GROUP_MISMATCH")):
        if app_info.get(key) != extension_info.get(key):
            issues.append(f"{code}: l’app et l’extension ne demandent pas le même groupe dans leurs Info.plist.")
    host = app_info.get("CFBundleIdentifier")
    if not resolved(host) or app_info.get("MeshCentralHostBundleID") != host or extension_info.get("MeshCentralHostBundleID") != host:
        issues.append("HOST_ID_MISMATCH: MeshCentralHostBundleID doit correspondre à l’identifiant de l’app dans les deux Info.plist.")
    if resolved(host) and extension_info.get("CFBundleIdentifier") != host + ".Broadcast":
        issues.append("PICKER_ID_MISMATCH: le Bundle ID de l’extension ne correspond pas à celui demandé par le bouton de diffusion.")
    extension = extension_info.get("NSExtension")
    if not isinstance(extension, dict) or extension.get("NSExtensionPointIdentifier") != "com.apple.broadcast-services-upload" or extension.get("RPBroadcastProcessMode") != "RPBroadcastProcessModeSampleBuffer":
        issues.append("REPLAYKIT_CONFIGURATION: point d’extension ou mode de traitement ReplayKit incorrect.")
    team = app_rights.get("com.apple.developer.team-identifier")
    if not resolved(team) or team != extension_rights.get("com.apple.developer.team-identifier"):
        issues.append("TEAM_MISMATCH: les signatures de l’app et de l’extension ne désignent pas la même Team.")
    return issues


def read_info(bundle):
    value = plistlib.loads((bundle / "Info.plist").read_bytes())
    if not isinstance(value, dict):
        raise ValueError("Info.plist non valide.")
    return value


def signed_entitlements(bundle):
    result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)],
                            capture_output=True, timeout=15, check=False)
    if result.returncode != 0:
        raise ValueError("Impossible de lire les droits signés. Sélectionnez une archive iOS signée.")
    for stream in (result.stdout, result.stderr):
        start, end = stream.find(b"<?xml"), stream.find(b"</plist>")
        if start >= 0 and end > start:
            value = plistlib.loads(stream[start:end + len(b"</plist>")])
        elif stream.startswith(b"bplist00"):
            value = plistlib.loads(stream)
        else:
            continue
        if isinstance(value, dict):
            return value
    raise ValueError("La signature ne fournit pas de droits lisibles au format plist.")


def inspect_archive(path):
    if path.suffix == ".xcarchive":
        apps = list((path / "Products/Applications").glob("*.app"))
    elif path.suffix == ".app":
        apps = [path]
    else:
        raise ValueError("Choisissez un dossier .xcarchive ou une application .app signée.")
    if len(apps) != 1 or not apps[0].is_dir():
        raise ValueError("Une seule application iOS doit être présente dans l’archive.")
    app = apps[0]
    extensions = []
    for bundle in (app / "PlugIns").glob("*.appex"):
        info = read_info(bundle)
        declaration = info.get("NSExtension", {})
        if isinstance(declaration, dict) and declaration.get("NSExtensionPointIdentifier") == "com.apple.broadcast-services-upload":
            extensions.append((bundle, info))
    if len(extensions) != 1:
        raise ValueError("L’app doit contenir une extension de diffusion ReplayKit unique.")
    extension, extension_info = extensions[0]
    return check_configuration(read_info(app), extension_info, signed_entitlements(app), signed_entitlements(extension))


def main():
    parser = argparse.ArgumentParser(description="Vérifier sans modification les groupes de partage d’une archive iOS.")
    parser.add_argument("archive", type=Path, help="Archive .xcarchive ou app iOS signée")
    args = parser.parse_args()
    if sys.platform != "darwin":
        print("Ce contrôle d’archive signée doit être exécuté sur le Mac avec Xcode.", file=sys.stderr)
        return 2
    try:
        issues = inspect_archive(args.archive.expanduser().resolve())
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError, subprocess.TimeoutExpired):
        print("LECTURE_IMPOSSIBLE: vérifiez le chemin de l’archive iOS signée et la disponibilité de codesign.", file=sys.stderr)
        return 2
    for issue in issues:
        print("ERREUR " + issue)
    if issues:
        return 1
    print("OK: groupes App Group/trousseau concordants et autorisés par les deux signatures ; identifiants et mode ReplayKit cohérents.")
    print("Ce résultat ne remplace pas le test d’accès au conteneur et de diffusion sur l’iPad.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
