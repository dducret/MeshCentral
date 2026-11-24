# SPDX-License-Identifier: Apache-2.0
"""iPad home/Messenger source delta from the actual, preserved 0.4.3 delivery."""
import argparse
import json
from pathlib import Path
import shutil
import zipfile

from package_ipad_040 import ROOT, DIST, sources, digest
from package_mac import validate_project

NAME = 'MeshCentral-iOS-0.4.4-ipad-chat-ui-update'
ARCHIVE = DIST / (NAME + '.zip')
MANIFEST = DIST / 'ipad-chat-044-delivery.json'
SNAPSHOT = DIST / 'ipad-chat-044-delivered'
BASE = DIST / 'chat-043-delivered'
PROJECT = 'apple/App/MeshCentralIOS.xcodeproj/project.pbxproj'
MANUAL = {PROJECT: 'Set app and extension Marketing Version to 0.4.4; use the same next Build on your Mac. Preserve Team, identifiers, signing and all other settings. See docs/ipad-chat-044-update-fr.md.'}


def baseline():
    record = json.loads((DIST / 'chat-043-delivery.json').read_text())
    assert record['sha256'] == '9e4bff1b3e63458c91ee0166e30af35bf1a0c9211f3f047ce959d657dbb735c9'
    assert digest((DIST / record['archive']).read_bytes()) == record['sha256']
    prefix = Path(record['archive']).stem + '/'
    with zipfile.ZipFile(DIST / record['archive']) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {prefix + n for n in record['files']}
        for name, checksum in record['files'].items():
            assert digest(archive.read(prefix + name)) == checksum, name
    for name, checksum in record['source_files'].items():
        assert digest((BASE / name).read_bytes()) == checksum, name
    return record


def payload():
    base = baseline(); files = sources()
    assert not set(base['source_files']) - set(files), 'Document removals explicitly'
    assert files[PROJECT] == (BASE / PROJECT).read_bytes().replace(b'"MARKETING_VERSION" = "0.4.3"', b'"MARKETING_VERSION" = "0.4.4"')
    changed = {n:d for n,d in files.items() if n not in MANUAL and digest(d) != base['source_files'].get(n)}
    assert not any(n.endswith(('.pbxproj','.plist','.entitlements','.p12','.mobileprovision')) for n in changed)
    metadata = {'license':'Apache-2.0', 'version':'0.4.4', 'kind':'incremental-source-validation-candidate', 'date':'2026-11-22',
        'base_archive':base['archive'], 'base_sha256':base['sha256'], 'changed_files':list(changed), 'removed':[], 'renamed':[],
        'manual_edits':MANUAL, 'upstream_revision':'67aff175f6d1093b1a81f8e9230607854d3fbaa6',
        'upstream_head_observed':'412e2aeb3f209df1c1a238de974d3a44185d7006', 'upstream_integrated':False,
        'apple_build_executed':False, 'physical_device_test_executed':False, 'browser_rendering_verified':False,
        'chat_mode':'normalized exact-page validation, visible native composer, bounded page status; simplified assistance home',
        'rust_crate_version':'0.4.2', 'rust_abi_changed':False,
        'wire_protocol':'existing MeshMessenger; iosAssist v1 unchanged', 'plugin_version':'0.1.0', 'operator_version':'0.4.0',
        'external_cargo_dependencies_added':0, 'server_files_shipped':0}
    changed['release-0.4.4.json']=(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n').encode()
    changed['SHA256SUMS-0.4.4.json']=(json.dumps({n:digest(d) for n,d in changed.items()},indent=2)+'\n').encode()
    return files,changed,metadata


def verify():
    files,expected,_metadata=payload(); record=json.loads(MANIFEST.read_text())
    assert record['sha256']==digest(ARCHIVE.read_bytes()) and record['bytes']==ARCHIVE.stat().st_size
    assert record['files']=={n:digest(d) for n,d in expected.items()}
    assert record['source_files']=={n:digest(d) for n,d in files.items()}
    merged={n:(BASE/n).read_bytes() for n in baseline()['source_files']}
    with zipfile.ZipFile(ARCHIVE) as archive:
        assert archive.testzip() is None and set(archive.namelist())=={NAME+'/'+n for n in expected}
        for name,data in expected.items():
            assert not Path(name).is_absolute() and '..' not in Path(name).parts
            assert archive.read(NAME+'/'+name)==data,name
            if name in files: merged[name]=data
    merged[PROJECT]=merged[PROJECT].replace(b'"MARKETING_VERSION" = "0.4.3"',b'"MARKETING_VERSION" = "0.4.4"')
    assert merged==files, 'Delta plus targeted version edits must reconstruct all current sources'
    for name,data in files.items(): assert (SNAPSHOT/name).read_bytes()==data,name
    print(f'PASS: ZIP/base/snapshot and incremental merge; {len(expected)-2} changed/new files + 2 metadata; {len(files)} source files.')


def build():
    assert not ARCHIVE.exists() and not MANIFEST.exists() and not SNAPSHOT.exists(), 'Preserve prior delivery; use --verify'
    validate_project(ROOT); files,content,metadata=payload()
    with zipfile.ZipFile(ARCHIVE,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for name,data in sorted(content.items()):
            entry=zipfile.ZipInfo(NAME+'/'+name,date_time=(2026,11,22,12,0,0));entry.create_system=3
            entry.external_attr=(0o100755 if name.endswith('.sh') else 0o100644)<<16
            entry.compress_type=zipfile.ZIP_DEFLATED;archive.writestr(entry,data)
    for name in files:
        target=SNAPSHOT/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,target)
    record={'archive':ARCHIVE.name,'sha256':digest(ARCHIVE.read_bytes()),'bytes':ARCHIVE.stat().st_size,
        'base':metadata['base_archive'],'base_sha256':metadata['base_sha256'],'manual_edits':MANUAL,
        'files':{n:digest(d) for n,d in content.items()},'source_files':{n:digest(d) for n,d in files.items()}}
    MANIFEST.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');verify()
    print(str(ARCHIVE));print('SHA256 '+record['sha256'])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--verify',action='store_true')
    args=parser.parse_args();verify() if args.verify else build()
