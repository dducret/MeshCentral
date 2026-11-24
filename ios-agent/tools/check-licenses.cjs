// SPDX-License-Identifier: Apache-2.0
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');

const metadata = JSON.parse(execFileSync('cargo', [
    'metadata', '--offline', '--locked', '--format-version', '1',
], { cwd: root, encoding: 'utf8' }));
assert.deepEqual(metadata.packages.map(p => p.name).sort(), ['meshcentral-ios-bridge', 'meshcentral-ios-core']);
for (const pkg of metadata.packages) {
    assert.equal(pkg.source, null, 'External packages require explicit license review');
    assert.equal(pkg.license, 'Apache-2.0');
    const expected = path.join(root, pkg.name.endsWith('-bridge') ? 'bridge' : '', 'Cargo.toml');
    assert.equal(path.resolve(pkg.manifest_path), expected, 'Only the reviewed local packages are allowed');
    assert.equal(pkg.dependencies.length, pkg.name.endsWith('-bridge') ? 1 : 0);
    for (const dep of pkg.dependencies) {
        assert.equal(dep.name, 'meshcentral-ios-core');
        assert.equal(path.resolve(dep.path), root);
        assert.equal(dep.source, null);
    }
}
assert.equal(metadata.resolve.nodes.length, 2);
const license = fs.readFileSync(path.join(root, 'LICENSE'), 'utf8').replace(/\r\n/g, '\n');
assert.equal(createHash('sha256').update(license).digest('hex'),
    'b7158523c38e5d643531d44ddbedbc823f0797f58f88ad4acef8ab037a6fc94b',
    'Preserve the reviewed Apache-2.0 license text, including upstream notices');
const pluginRoot = path.join(root, 'plugin/iosAssistance');
assert.equal(fs.readFileSync(path.join(pluginRoot, 'LICENSE'), 'utf8').replace(/\r\n/g, '\n'), license);
assert.equal(JSON.parse(fs.readFileSync(path.join(pluginRoot, 'config.json'), 'utf8')).license, 'Apache-2.0');

function checkHeaders(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        if (['target', 'dist', '.git', 'Artifacts', '.build', '.swiftpm', 'xcuserdata', 'DerivedData', '__pycache__'].includes(entry.name)) continue;
        const filename = path.join(directory, entry.name);
        if (entry.isDirectory()) { checkHeaders(filename); continue; }
        if (!/\.(rs|cjs|js|html|css|md|toml|swift|cs|h|ps1|sh|modulemap|py|pbxproj|xcscheme|plist|entitlements)$/.test(entry.name)) continue;
        assert.match(fs.readFileSync(filename, 'utf8').split(/\r?\n/).slice(0, 5).join('\n'),
            /SPDX-License-Identifier: Apache-2\.0/, filename);
    }
}
checkHeaders(root);
console.log('PASS: Apache-2.0 source headers and license; only two original workspace crates, zero external Cargo dependencies.');
console.log('Scope: source package only; upstream server, tooling and linked binaries need separate audits.');
