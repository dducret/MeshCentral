// SPDX-License-Identifier: Apache-2.0
'use strict';
// Execute upstream browser transport/desktop parsers in a bounded VM with fake
// canvas/Image. Verifies byte delivery, not JPEG decoding or a rendered screenshot.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const lines = execFileSync('cargo', ['run', '--offline', '--locked', '--quiet', '--example', 'desktop_fixtures'],
    { cwd: root, encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 }).trim().split(/\r?\n/);
const frames = Object.fromEntries(lines.map(line => { const [key, hex] = line.split(' '); return [key, Buffer.from(hex, 'hex')]; }));
const images = [];
class TestImage { set src(value) { images.push(Buffer.from(value.split(',')[1], 'base64')); } }
const sandbox = { console, Uint8Array, ArrayBuffer, Image: TestImage, navigator: { platform: 'Win32' },
    window: { location: { protocol: 'https:', host: 'example.invalid', pathname: '/' } },
    btoa: text => Buffer.from(text, 'binary').toString('base64'), setInterval: () => 1, clearInterval: () => {},
    setTimeout, clearTimeout, WebSocket: { OPEN: 1 } };
vm.createContext(sandbox);
for (const file of ['agent-desktop-0.0.2.js', 'agent-redir-ws-0.1.1.js']) {
    vm.runInContext(fs.readFileSync(path.join(root, '..', 'public/scripts', file), 'utf8'), sandbox, { timeout: 2000 });
}
const canvas = { style: {}, width: 0, height: 0, getContext: () => ({ setTransform() {}, clearRect() {}, drawImage() {} }) };
const desktop = sandbox.CreateAgentRemoteDesktop(canvas, null);
desktop.onResize = () => {};
desktop.onScreenSizeChange = () => {};
const redirect = sandbox.CreateAgentRedirect(null, desktop, '', null, null, '/');
redirect.State = 3;
redirect.socket = { readyState: 1, send() {} };
desktop.parent = redirect;
desktop.State = 3;
// New assistance envelopes must be safely ignored by the stock desktop viewer.
redirect.xxOnMessage({ data: JSON.stringify({ctrlChannel:"102938",type:"iosAssist",v:1,action:"ready"}) });
redirect.xxOnMessage({ data: JSON.stringify({ctrlChannel:"102938",type:"iosAssist",v:1,action:"diagnostics",fps:2}) });
redirect.xxOnMessage({ data: JSON.stringify({ctrlChannel:"102938",type:"iosAssist",v:1,action:"guideStatus",id:"00000000-0000-4000-8000-000000000001",step:1,total:2,status:"waiting"}) });
for (const data of Object.values(frames)) {
    redirect.xxOnMessage({ data: data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) });
}
assert.equal(desktop.ScreenWidth, 720); assert.equal(desktop.ScreenHeight, 1280);
assert.deepEqual(images.map(x => x.length), [32, 65527, 65528, 90000]);
for (const image of images) {
    assert.equal(image[0], 255); assert.equal(image[1], 216);
    assert.equal(image.at(-2), 255); assert.equal(image.at(-1), 217);
    assert.ok(image.subarray(2, -2).every(x => x === 0x42));
}
// The stock viewer ignores the new envelope and uses its usual console
// and screen packets to replace the live frame.
redirect.xxOnMessage({ data: JSON.stringify({ctrlChannel:"102938",type:"iosAssist",v:1,action:"screenVisibility",hidden:true}) });
redirect.xxOnMessage({ data: JSON.stringify({ctrlChannel:"102938",type:"console",msg:"Écran masqué sur l’appareil."}) });
assert.equal(redirect.consoleMessage, 'Écran masqué sur l’appareil.');
const privacySize = Uint8Array.of(0, 7, 0, 8, 1, 64, 0, 180);
redirect.xxOnMessage({ data: privacySize.buffer });
assert.equal(desktop.ScreenWidth, 320); assert.equal(desktop.ScreenHeight, 180);
redirect.xxOnMessage({ data: JSON.stringify({ctrlChannel:"102938",type:"console",msg:null}) });
assert.equal(redirect.consoleMessage, null);
console.log('PASS: actual MeshCentral redirect and desktop parser accept Rust size/JPEG/jumbo framing and the stock privacy message and size.');
console.log('Scope: byte framing only; synthetic marker payloads, no real JPEG rendering, relay WSS or Apple capture executed.');
