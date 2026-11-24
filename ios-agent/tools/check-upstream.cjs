// SPDX-License-Identifier: Apache-2.0
'use strict';
// In-memory protocol compatibility check, NOT a live server or TLS test.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const upstream = path.resolve(root, '..');
const common = require(path.join(upstream, 'common.js'));
const { CreateMeshAgent } = require(path.join(upstream, 'meshagent.js'));
const accelerator = require(path.join(upstream, 'meshaccelerator.js'));

const output = execFileSync('cargo', ['run', '--quiet', '--offline', '--locked',
    '--example', 'wire_fixtures'], { cwd: root, encoding: 'utf8' });
const frames = Object.fromEntries(output.trim().split(/\r?\n/).map(line => {
    const [name, hex] = line.split(' ');
    assert.match(hex, /^(?:[0-9a-f]{2})+$/);
    return [name, Buffer.from(hex, 'hex')];
}));

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const tlsHash = Buffer.alloc(48, 0x11).toString('binary');
const sent = [];
const ws = new EventEmitter();
ws._socket = { remotePort: 12345, bytesRead: 0, bytesWritten: 0 };
ws.send = data => sent.push(Buffer.from(data));
const certificate = Buffer.from('synthetic certificate placeholder');
let signedTranscript;
let device, latestNodeEvent, deferDeviceRead = false, completeRead;
const db = {
    Get(_key, callback) {
        if (deferDeviceRead) {
            assert.equal(completeRead, undefined);
            completeRead = () => callback(null, [structuredClone(device)]);
        } else { callback(null, [structuredClone(device)]); }
    },
    Set(value) { device = structuredClone(value); }
};
const parent = {
    // A deterministic nonce is exclusively for this in-memory test.
    crypto: { ...crypto, randomBytes: length => Buffer.alloc(length, 0x44) },
    parent: {
        common, debug() {},
        meshAgentsArchitectureNumbers: {},
        DispatchEvent(_targets, _agent, event) { latestNodeEvent = event; },
        certificateOperations: {
            forge: {},
            acceleratorPerformSignature(_index, data, tag, callback) {
                signedTranscript = Buffer.from(data, 'binary');
                // Exercise the real upstream accelerator without starting workers.
                const originalSend = process.send;
                try {
                    process.send = signature => callback(tag, signature);
                    accelerator.processMessage({ action: 'sign', key: privateKey, data });
                } finally {
                    if (originalSend === undefined) delete process.send;
                    else process.send = originalSend;
                }
            },
        },
    },
    agentStats: { createMeshAgentCount: 0 },
    trafficStats: { AgentCtrlIn: 0, AgentCtrlOut: 0 },
    webCertificateHashs: { '': tlsHash },
    webCertificateFullHashs: { '': tlsHash },
    webCertificateHash: tlsHash,
    agentCertificateAsn1: certificate.toString('binary'),
    meshes: {},
    CreateMeshDispatchTargets: () => [],
    CloneSafeNode: node => structuredClone(node),
};
const agent = CreateMeshAgent(parent, db, ws, { clientIp: '127.0.0.1' },
    { agentidletimeout: 0 }, { id: '' });

ws.emit('message', frames.challenge);
assert.equal(sent.length, 2, 'Server must return challenge and identity proof');
assert.deepEqual(sent[0], Buffer.concat([Buffer.from([0, 1]), Buffer.alloc(48, 0x11), Buffer.alloc(48, 0x44)]));
assert.deepEqual(signedTranscript, Buffer.concat([Buffer.alloc(48, 0x11), Buffer.alloc(48, 0x33), Buffer.alloc(48, 0x44)]));
assert.equal(sent[1].readUInt16BE(0), 2);
assert.equal(sent[1].readUInt16BE(2), certificate.length);
assert(crypto.verify('sha384', signedTranscript, publicKey, sent[1].subarray(4 + certificate.length)));
ws.emit('message', frames.challenge);
assert.equal(sent.length, 2, 'Repeated agent challenge must not be processed again');

ws.emit('message', frames.info);
assert.deepEqual(agent.agentInfo, {
    infoVersion: 1, agentId: 0xfffffff0, agentVersion: 1, platformType: 1,
    capabilities: 0, computerName: 'iPhone de Chloé',
});
assert.equal(agent.meshid, Buffer.alloc(48, 0x77).toString('base64').replace(/\+/g, '@').replace(/\//g, '$'));
assert.equal(agent.authenticated, 0, 'No real device identity was supplied; enrollment must remain incomplete');
console.log('PASS: Rust challenge/registration accepted by the actual meshagent.js handler.');
console.log('PASS: actual upstream signing transcript, RSA/SHA-384 signature and duplicate challenge handling.');

// Enter an authenticated fixture state to isolate the real node-record update path.
agent.dbNodeKey = 'node//synthetic';
agent.dbMeshKey = 'mesh//synthetic';
agent.authenticated = 2;
parent.meshes[agent.dbMeshKey] = { mtype: 2 };
device = { meshid: agent.dbMeshKey, agent: { caps: 0 } };
const announce = (caps, role) => ws.emit('message', JSON.stringify({ action: 'coreinfo', caps, value: role }));
const desktopReady = 'MeshCentral iOS Rust 0.5.2 [broadcast-ready] console-1';
const chatOnly = 'MeshCentral iOS Rust 0.5.2 [app-connected] console-1';
const retry = [];
const originalTimeout = global.setTimeout;
try {
    global.setTimeout = callback => retry.push(callback);
    deferDeviceRead = true;
    announce(1, desktopReady);
    ws.emit('message', Buffer.from([0, 11, 0, 0])); // Old empty CoreModuleHash reply.
    announce(1, desktopReady);
    retry.shift()(); // The clear retries while the first DB read is still busy.
    deferDeviceRead = false;
    completeRead();
    retry.shift()(); // The second advertisement takes effect first.
    assert.equal(device.agent.caps, 1);
    retry.shift()();
    assert.equal(retry.length, 0);
    assert.equal(device.agent.caps, 0, 'Delayed empty core reply erased the desktop capability');
    assert.equal(device.agent.core, undefined);
} finally { global.setTimeout = originalTimeout; }

// The native agent has no JavaScript core. Its startup only announces coreinfo.
announce(1, desktopReady);
assert.equal(device.agent.caps, 1);
assert.equal(latestNodeEvent.action, 'changenode');
assert.equal(latestNodeEvent.node.agent.core, desktopReady);
assert.equal(latestNodeEvent.node.agent.caps, 1);
announce(0, chatOnly);
assert.equal(latestNodeEvent.node.agent.caps, 0);
assert.equal(latestNodeEvent.node.agent.core, chatOnly);
console.log('PASS: real MeshCentral handler reproduces late capability clearing and advertises native Desktop versus chat-only correctly without the empty reply.');
console.log('Scope: no TLS, real X.509 verification, completed enrollment, relay or iOS device exercised.');
