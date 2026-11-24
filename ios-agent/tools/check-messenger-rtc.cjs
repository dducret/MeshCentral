// SPDX-License-Identifier: Apache-2.0
'use strict';

// Run the shipped script with the actual server's negotiation functions. The
// optional path selects a downloaded production-version Messenger template.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const agent = path.resolve(__dirname, '..');
const native = fs.readFileSync(path.join(agent, 'apple/App/Sources/AssistanceView.swift'), 'utf8');
const template = fs.readFileSync(process.argv[2] ?? path.join(agent, '../views/messenger.handlebars'), 'utf8');

function swiftScript(name) {
    const match = new RegExp('private static let ' + name + ' = """([\\s\\S]*?)"""').exec(native);
    assert(match, name);
    return match[1];
}

function pageFunction(name) {
    const start = template.indexOf('        function ' + name + '(');
    assert(start !== -1, name);
    const end = template.indexOf('\n        function ', start + 1);
    assert(end > start, name);
    return template.slice(start, end);
}

const patch = swiftScript('rtcPromiseScript');
const diagnostics = swiftScript('rtcDiagnosticsScript');
const flush = () => new Promise(resolve => setImmediate(resolve));

function fixture({ debug = false, prefixed = false } = {}) {
    const calls = [], sent = [], hangups = [], events = [];
    const channel = { readyState: 'connecting' };
    const pageEvents = {};
    const config = { iceServers: [{ urls: 'turn:example.invalid:3478' }] };
    const error = new Error('fixture secret detail');
    let deferOffer;
    class Peer {
        constructor(options) {
            assert.equal(options, config);
            this.signalingState = 'stable';
        }
        createDataChannel(label) { assert.equal(label, 'DataChannel'); return channel; }
        createOffer(...args) {
            // Match the reported failure: legacy never fires either callback.
            if (typeof args[0] === 'function') return Promise.resolve();
            calls.push(['offer', this.id, ...args]);
            if (this.defer) return new Promise(resolve => { deferOffer = resolve; });
            return Promise.resolve({ type: 'offer', sdp: 'fixture offer' });
        }
        createAnswer(...args) {
            assert.deepEqual(args, []);
            calls.push(['answer', this.id]);
            return Promise.resolve({ type: 'answer', sdp: 'fixture answer' });
        }
        setLocalDescription(description, ...args) {
            assert.deepEqual(args, []);
            calls.push(['local', this.id, description.type]);
            return Promise.resolve();
        }
        setRemoteDescription(description, ...args) {
            assert.deepEqual(args, []);
            calls.push(['remote', this.id, description.type]);
            return description.type === 'bad' ? Promise.reject(error) : Promise.resolve();
        }
        addIceCandidate() { return Promise.resolve(); }
    }
    const iceMethod = Peer.prototype.addIceCandidate;
    const aliases = prefixed ? { webkitRTCPeerConnection: Peer } : { RTCPeerConnection: Peer, webkitRTCPeerConnection: Peer };
    const context = vm.createContext({
        ...aliases, webrtcconfiguration: config, webrtcSessions: {}, webchannel: null, multiWebRtc: true, serverRecording: false,
        window: { ...aliases, addEventListener: (name, cb) => { pageEvents[name] = cb; } },
        RTCSessionDescription: function(description) { Object.assign(this, description); },
        setTimeout: cb => { Promise.resolve().then(cb); return 1; },
        sendws: packet => sent.push(packet), updateControls() {},
        hangUpButtonClick: id => hangups.push(id),
        console: { debug: (...args) => events.push(args.join(' ')) },
    });
    vm.runInContext(patch + (debug ? '(' + diagnostics + ');' : '();'), context);
    assert.equal(Peer.prototype.addIceCandidate, iceMethod);
    vm.runInContext(pageFunction('startWebRTC') + pageFunction('webRtcHandleOffer'), context);
    return { context, calls, sent, hangups, events, channel, pageEvents, error,
        resolveOffer: () => deferOffer({ type: 'offer', sdp: 'discarded offer' }) };
}

async function testRelease() {
    const { context, calls, sent, hangups, events, channel } = fixture();
    // Outbound offer (session 1), inbound offer/answer (session 2), and the
    // original data offer (session 0) all share the patched browser API.
    const dataPeer = context.startWebRTC(0, true);
    const outgoing = context.startWebRTC(1, false);
    context.startWebRTC(2, false);
    dataPeer.onnegotiationneeded();
    outgoing.onnegotiationneeded();
    context.webRtcHandleOffer(2, { type: 'offer' });
    await flush();
    assert.deepEqual(sent.map(({ action, sdp, id }) => [action, sdp.type, id]).sort(), [
        ['webRtcSdp', 'answer', 2], ['webRtcSdp', 'offer', 0], ['webRtcSdp', 'offer', 1],
    ]);
    for (const id of [0, 1]) {
        assert(calls.findIndex(([op, peer]) => op === 'offer' && peer === id) <
               calls.findIndex(([op, peer]) => op === 'local' && peer === id));
        context.webRtcHandleOffer(id, { type: 'answer' });
    }
    const inbound = calls.filter(([, id]) => id === 2);
    assert.deepEqual(inbound, [['remote', 2, 'offer'], ['answer', 2], ['local', 2, 'answer']]);
    await flush();
    assert(calls.some(([op, id, type]) => op === 'remote' && id === 1 && type === 'answer'));
    assert.equal(sent.length, 3, 'a remote answer must not create another offer or answer');
    channel.readyState = 'open';
    channel.onopen();
    assert.equal(channel.ok, true);
    assert.equal(sent.at(-1).action, 'rtcSwitch');
    context.webRtcHandleOffer(2, { type: 'bad' });
    await flush();
    assert.deepEqual(hangups, [2], 'rejection still uses the page error handler');
    assert.deepEqual(events, [], 'Release must remain silent');
}

async function testAPIAndDebug() {
    const { context, sent, calls, events, pageEvents, error, resolveOffer } = fixture({ debug: true, prefixed: true });
    const peer = context.startWebRTC(1, false);
    const options = { iceRestart: true };
    assert.equal((await peer.createOffer(options)).type, 'offer', 'native Promise overload still returns the offer');
    assert.deepEqual(events, []);
    const reported = [];
    assert.equal(await peer.createOffer(value => reported.push(value.type), () => assert.fail(), options), undefined);
    assert.equal(await peer.setRemoteDescription({ type: 'bad' }, () => assert.fail(), value => reported.push(value)), undefined);
    await flush();
    assert.deepEqual(reported, ['offer', error]);
    assert.equal(calls.filter(([op, , opts]) => op === 'offer' && opts === options).length, 2);
    assert.deepEqual(events, ['MeshMessenger RTC createOffer fulfilled', 'MeshMessenger RTC setRemoteDescription rejected']);

    let unrelatedFailure = false;
    await peer.createAnswer(() => { throw error; }, () => { unrelatedFailure = true; });
    await flush();
    assert.equal(unrelatedFailure, false, 'a page callback error must not look like a WebRTC rejection');
    assert.deepEqual(events.slice(2), ['MeshMessenger RTC createAnswer fulfilled', 'MeshMessenger RTC createAnswer callback-failed']);

    peer.defer = true;
    peer.onnegotiationneeded();
    await flush();
    peer.signalingState = 'closed';
    resolveOffer();
    await flush();
    assert.deepEqual(sent, [], 'a closed peer must not signal after delayed completion');

    const other = context.startWebRTC(2, false);
    other.defer = true;
    other.onnegotiationneeded();
    await flush();
    pageEvents.pagehide();
    resolveOffer();
    await flush();
    assert.deepEqual(sent, [], 'a closed page must not signal after delayed completion');
    assert.equal(events.length, 4);
}

(async () => {
    await testRelease();
    await testAPIAndDebug();
    console.log('PASS: upstream data/voice offers, inbound SDP answer, error cleanup, legacy/Promise contracts, stale completion and Debug-only fixed events. Node fixture, no media engine.');
})().catch(error => { console.error(error); process.exitCode = 1; });
