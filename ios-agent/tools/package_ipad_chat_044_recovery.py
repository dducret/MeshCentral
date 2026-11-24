# SPDX-License-Identifier: Apache-2.0
"""Recover the eight Swift files from the verified actual 0.4.4 delivery.

Preserves the original archive/manifest/snapshot. The repeated Swift files are
intentional recovery payload for an incompletely updated project, not new code.
No older 0.4.3 archive is required to verify this delivery.
"""
import argparse
import json
from pathlib import Path
import zipfile

from check_ipad_chat_044_delivery import EXPECTED, ORIGINAL_ARCHIVE, ORIGINAL_SHA256
from package_ipad_040 import ROOT, DIST, sources, digest
from package_mac import validate_project

NAME = 'MeshCentral-iOS-0.4.4-swift-recovery'
ARCHIVE = DIST / (NAME + '.zip')
MANIFEST = DIST / 'ipad-chat-044-recovery-delivery.json'
SNAPSHOT = DIST / 'ipad-chat-044-recovery-delivered'
BASE = DIST / 'ipad-chat-044-delivered'


def baseline():
    record = json.loads((DIST / 'ipad-chat-044-delivery.json').read_text(encoding='utf-8'))
    assert record['archive'] == ORIGINAL_ARCHIVE
    assert record['sha256'] == ORIGINAL_SHA256 == digest((DIST / ORIGINAL_ARCHIVE).read_bytes())
    assert record['bytes'] == (DIST / ORIGINAL_ARCHIVE).stat().st_size
    prefix = Path(ORIGINAL_ARCHIVE).stem + '/'
    with zipfile.ZipFile(DIST / ORIGINAL_ARCHIVE) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(record['files'])
        assert set(archive.namelist()) == {prefix + n for n in record['files']}
        for name, checksum in record['files'].items():
            assert digest(archive.read(prefix + name)) == checksum, name
    for name, checksum in record['source_files'].items():
        assert digest((BASE / name).read_bytes()) == checksum, name
    for name, checksum in EXPECTED.items():
        assert record['files'][name] == record['source_files'][name] == checksum, name
    return record


def payload():
    base = baseline()
    files = sources()
    assert not set(base['source_files']) - set(files), 'Document removals explicitly'
    for name, checksum in EXPECTED.items():
        assert digest(files[name]) == checksum, 'Recovery must preserve original Swift: ' + name
    changed = {n: d for n, d in files.items() if digest(d) != base['source_files'].get(n)}
    content = changed | {n: files[n] for n in EXPECTED}
    assert not any(n.endswith(('.pbxproj', '.plist', '.entitlements', '.p12', '.mobileprovision')) for n in content)
    metadata = {
        'license': 'Apache-2.0', 'version': '0.4.4', 'kind': 'incremental-source-recovery', 'date': '2026-11-22',
        'base_archive': base['archive'], 'base_sha256': base['sha256'],
        'changed_files': list(changed), 'recovery_files': list(EXPECTED),
        'recovery_reason': 'Reported incomplete Swift application of 0.4.4; repeat the eight original verified Swift files.',
        'removed': [], 'renamed': [], 'manual_edits': {},
        'installation_guide': 'docs/ipad-chat-044-recovery-fr.md',
        'upstream_revision': '67aff175f6d1093b1a81f8e9230607854d3fbaa6',
        'upstream_head_observed': '412e2aeb3f209df1c1a238de974d3a44185d7006', 'upstream_integrated': False,
        'apple_build_executed': False, 'physical_device_test_executed': False,
        'rust_crate_version': '0.4.2', 'rust_abi_changed': False, 'external_dependencies_added': 0,
    }
    content['release-0.4.4-recovery.json'] = (json.dumps(metadata, indent=2) + '\n').encode()
    content['SHA256SUMS-0.4.4-recovery.json'] = (json.dumps({n: digest(d) for n, d in content.items()}, indent=2) + '\n').encode()
    return files, content, metadata


def verify():
    files, expected, _ = payload()
    record = json.loads(MANIFEST.read_text(encoding='utf-8'))
    assert record['base'] == ORIGINAL_ARCHIVE and record['base_sha256'] == ORIGINAL_SHA256
    assert record['sha256'] == digest(ARCHIVE.read_bytes()) and record['bytes'] == ARCHIVE.stat().st_size
    assert record['files'] == {n: digest(d) for n, d in expected.items()}
    assert record['source_files'] == {n: digest(d) for n, d in files.items()}
    # Exercise recovery from a project missing all eight Swift files, rather
    # than allowing an already-complete baseline to mask an incomplete ZIP.
    merged = {n: (BASE / n).read_bytes() for n in baseline()['source_files'] if n not in EXPECTED}
    with zipfile.ZipFile(ARCHIVE) as archive:
        assert archive.testzip() is None and len(archive.namelist()) == len(expected)
        assert set(archive.namelist()) == {NAME + '/' + n for n in expected}
        for name, data in expected.items():
            assert not Path(name).is_absolute() and '..' not in Path(name).parts
            assert archive.read(NAME + '/' + name) == data, name
            if name in files:
                merged[name] = data
    assert merged == files, 'Recovery must reconstruct the complete current source tree'
    for name, data in files.items():
        assert (SNAPSHOT / name).read_bytes() == data, name
    print(f'PASS: original ZIP, recovery ZIP, full merge and snapshot; 8 recovery Swift files, {len(expected)-10} changed/new files, 2 metadata; {len(files)} sources.')


def build():
    assert not ARCHIVE.exists() and not MANIFEST.exists() and not SNAPSHOT.exists(), 'Preserve prior delivery; use --verify'
    validate_project(ROOT)
    files, content, metadata = payload()
    with zipfile.ZipFile(ARCHIVE, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(content.items()):
            entry = zipfile.ZipInfo(NAME + '/' + name, date_time=(2026, 11, 22, 12, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    for name, data in files.items():
        target = SNAPSHOT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    record = {
        'archive': ARCHIVE.name, 'sha256': digest(ARCHIVE.read_bytes()), 'bytes': ARCHIVE.stat().st_size,
        'base': ORIGINAL_ARCHIVE, 'base_sha256': ORIGINAL_SHA256, 'manual_edits': {},
        'recovery_files': metadata['recovery_files'],
        'files': {n: digest(d) for n, d in content.items()},
        'source_files': {n: digest(d) for n, d in files.items()},
    }
    MANIFEST.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    verify()
    print(ARCHIVE)
    print('SHA256 ' + record['sha256'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    verify() if args.verify else build()
