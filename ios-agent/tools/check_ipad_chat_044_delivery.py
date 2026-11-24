# SPDX-License-Identifier: Apache-2.0
"""Read-only check of the eight Swift files shipped in the original 0.4.4 ZIP.

Run this script from the recovery package with --root pointing at the existing
Xcode source project. It deliberately does not read a manifest from that target
or overwrite local corrections. Exact byte hashes also detect line-ending edits.
"""
import argparse
import hashlib
from pathlib import Path

ORIGINAL_ARCHIVE = 'MeshCentral-iOS-0.4.4-ipad-chat-ui-update.zip'
ORIGINAL_SHA256 = '7e7d6df0e60e637752ec88896be6b594c77ef6aa7dbdfbb4880f13f419a05a5b'
EXPECTED = {
    'apple/App/Sources/AgentModel.swift': '6d0290d1c91142104575a5d6308a1c72ec70dffb77d381a154cd80a3fc10a4e1',
    'apple/App/Sources/AssistanceView.swift': 'c339cd387af40d5c0443f6e4a0bbe9457604320da531086066f8f5c76a1c2e28',
    'apple/App/Sources/MeshCentralIOSApp.swift': '18cac325425ac2950fd4b1077472a8b3db40da73badf7e6bc440c707ade391db',
    'apple/Sources/MeshCentralAgent/Connection.swift': '26391898c704832460d6cf65d09e98c6a85f5a64c811e972de6d20a8c43f5acf',
    'apple/Sources/MeshCentralAgent/ConnectionDiagnostics.swift': 'b0539640d9ddf9fa9af4a45d5281e168b92926d2123199f72b1245784929a8f2',
    'apple/Sources/MeshCentralAgent/DesktopRelay.swift': 'a4f1c91be145bdbc07221cdeaa3c8015d0577ed62e7463a7981c890dc9479f26',
    'apple/Sources/MeshCentralAgent/DesktopRequest.swift': '5af4ab8d3cfb5dfe5cbf47fdeffd29b0a43fd80a51e41b90abfa17c3e2be3885',
    'apple/Tests/MeshCentralAgentTests/AssistanceTests.swift': 'a6d26fab25dd779c5abe5e03c600bcaa8e3cfc0e35020c7d8222a5fc7721e30c',
}


def check(root):
    """Return (relative path, status, actual digest) without modifying anything."""
    results = []
    for name, expected in EXPECTED.items():
        try:
            actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
            results.append((name, 'OK' if actual == expected else 'DIFFERENT', actual))
        except FileNotFoundError:
            results.append((name, 'MISSING', None))
        except OSError:
            results.append((name, 'UNREADABLE', None))
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1],
                        help='Existing project root containing apple/ (not the .xcodeproj directory)')
    args = parser.parse_args(argv)
    print('Source root:', args.root.resolve())
    results = check(args.root)
    for name, status, actual in results:
        print(f'{status}: {name}')
        if status == 'DIFFERENT':
            print('  expected:', EXPECTED[name])
            print('  actual:  ', actual)
    failed = sum(status != 'OK' for _, status, _ in results)
    if failed:
        print(f'FAIL: {failed}/8 files differ or cannot be read. Nothing was written.')
        print('Compare local corrections before merging. A difference alone does not prove an older version.')
        return 1
    print('PASS: 8/8 Swift files match the original 0.4.4 delivery. No Apple build/device test performed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
