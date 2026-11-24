# SPDX-License-Identifier: Apache-2.0
"""Build or verify the 0.4.5 source delta against the delivered 0.4.4 recovery."""
import argparse
import json
from pathlib import Path
import zipfile

from package_ipad_040 import DIST, PROJECT, ROOT, digest, sources
from package_mac import validate_project

NAME = 'MeshCentral-iOS-0.4.5-messenger-audio-update'
ARCHIVE = DIST / (NAME + '.zip')
MANIFEST = DIST / 'messenger-audio-045-delivery.json'
SNAPSHOT = DIST / 'messenger-audio-045-delivered'
BASE = DIST / 'ipad-chat-044-recovery-delivered'
BASE_SHA256 = 'c90d4985fbce4717f31cc03f34cce4f1c8daab3d11ab11a75bef837cddc09fe3'
MANUAL = {PROJECT: 'Set app and extension Marketing Version to 0.4.5 and use the same next Build. Preserve configured signing and identifiers.'}


def json_bytes(value):
    return (json.dumps(value, indent=2) + '\n').encode('utf-8')


def verify_zip(path, checksums):
    prefix = path.stem + '/'
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(checksums)
        assert set(archive.namelist()) == {prefix + name for name in checksums}
        for name, checksum in checksums.items():
            relative = Path(name)
            assert not relative.is_absolute() and '..' not in relative.parts
            assert digest(archive.read(prefix + name)) == checksum, name


def payload():
    base = json.loads((DIST / 'ipad-chat-044-recovery-delivery.json').read_text(encoding='utf-8'))
    base_archive = DIST / 'MeshCentral-iOS-0.4.4-swift-recovery.zip'
    assert base['archive'] == base_archive.name
    assert digest(base_archive.read_bytes()) == base['sha256'] == BASE_SHA256
    verify_zip(base_archive, base['files'])
    baseline = {name: (BASE / name).read_bytes() for name in base['source_files']}
    assert {name: digest(data) for name, data in baseline.items()} == base['source_files']

    files = sources()
    assert not set(baseline) - set(files), 'Document removals explicitly'
    project = baseline[PROJECT]
    previous = b'"MARKETING_VERSION" = "0.4.4"'
    assert project.count(previous) == 4
    assert files[PROJECT] == project.replace(previous, b'"MARKETING_VERSION" = "0.4.5"')
    changed = {name: data for name, data in files.items() if name != PROJECT and data != baseline.get(name)}
    assert not any(name.endswith(('.pbxproj', '.plist', '.entitlements', '.p12', '.mobileprovision')) for name in changed)
    metadata = {
        'license': 'Apache-2.0', 'version': '0.4.5', 'kind': 'incremental-source-update', 'date': '2026-11-22',
        'base_archive': base['archive'], 'base_sha256': BASE_SHA256, 'changed_files': list(changed),
        'removed': [], 'renamed': [], 'manual_edits': MANUAL,
        'installation_guide': 'docs/messenger-audio-045-fr.md', 'rust_abi_changed': False,
        'apple_build_executed': False, 'physical_device_test_executed': False,
        'upstream_revision': '67aff175f6d1093b1a81f8e9230607854d3fbaa6', 'upstream_integrated': False,
    }
    changed['release-0.4.5.json'] = json_bytes(metadata)
    changed['SHA256SUMS-0.4.5.json'] = json_bytes({name: digest(data) for name, data in changed.items()})
    return files, changed, metadata, baseline


def verify():
    files, content, metadata, merged = payload()
    record = json.loads(MANIFEST.read_text(encoding='utf-8'))
    assert record['archive'] == ARCHIVE.name and record['base'] == metadata['base_archive']
    assert record['base_sha256'] == BASE_SHA256 and record['manual_edits'] == MANUAL
    assert record['sha256'] == digest(ARCHIVE.read_bytes()) and record['bytes'] == ARCHIVE.stat().st_size
    assert record['files'] == {name: digest(data) for name, data in content.items()}
    assert record['source_files'] == {name: digest(data) for name, data in files.items()}
    verify_zip(ARCHIVE, record['files'])
    with zipfile.ZipFile(ARCHIVE) as archive:
        for name in metadata['changed_files']:
            merged[name] = archive.read(NAME + '/' + name)
    merged[PROJECT] = merged[PROJECT].replace(b'"MARKETING_VERSION" = "0.4.4"', b'"MARKETING_VERSION" = "0.4.5"')
    assert merged == files
    for name, data in files.items():
        assert (SNAPSHOT / name).read_bytes() == data, name
    print(f'PASS: original 0.4.4 recovery, ZIP entries, delta merge and snapshot; {len(content) - 2} changed/new files + 2 metadata, {len(files)} source files.')


def build():
    assert not any(path.exists() for path in (ARCHIVE, MANIFEST, SNAPSHOT)), 'Preserve previous artifacts; use --verify'
    validate_project(ROOT)
    files, content, metadata, _ = payload()
    with zipfile.ZipFile(ARCHIVE, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(content.items()):
            entry = zipfile.ZipInfo(NAME + '/' + name, date_time=(2026, 11, 22, 12, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    for name, data in files.items():
        path = SNAPSHOT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    record = {
        'archive': ARCHIVE.name, 'sha256': digest(ARCHIVE.read_bytes()), 'bytes': ARCHIVE.stat().st_size,
        'base': metadata['base_archive'], 'base_sha256': BASE_SHA256, 'manual_edits': MANUAL,
        'files': {name: digest(data) for name, data in content.items()},
        'source_files': {name: digest(data) for name, data in files.items()},
    }
    with MANIFEST.open('xb') as output:
        output.write(json_bytes(record))
    verify()
    print(ARCHIVE)
    print('SHA256 ' + record['sha256'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.verify:
        verify()
    else:
        build()
