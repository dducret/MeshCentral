// SPDX-License-Identifier: Apache-2.0
'use strict';
// Loopback-only integration fixture. Private keys arrive via the parent's stdin,
// stay in memory, and are never written to disk or logged. No npm packages used.
const https = require('node:https');
const crypto = require('node:crypto');
const readline = require('node:readline');
const { EventEmitter } = require('node:events');
const common = require('../../common.js');
const { CreateMeshAgent } = require('../../meshagent.js');
console.log = (...args) => console.error(...args);

// Minimal test-only RFC 6455 server adapter, no extensions or fragmented messages.
// Application authentication and RSA verification run in the real meshagent.js.
class FixtureSocket extends EventEmitter {
    constructor(socket, mode) {
        super(); this._socket = socket; this.mode = mode; this.pending = Buffer.alloc(0);
        socket.on('data', chunk => this.consume(chunk));
        socket.on('error', () => this.close());
        socket.on('close', () => this.emit('close'));
    }
    send(data, callback) {
        data = Buffer.from(data);
        if (this.mode === 'bad-signature' && data.readUInt16BE(0) === 2) data[data.length - 1] ^= 1;
        if (this.mode === 'bad-binding' && data.readUInt16BE(0) === 1) data[2] ^= 1;
        const header = data.length < 126 ? Buffer.from([0x82, data.length]) : Buffer.from([0x82, 126, data.length >> 8, data.length & 255]);
        this._socket.write(Buffer.concat([header, data]), callback);
    }
    close() { this._socket.destroy(); }
    consume(chunk) {
        if (this.pending.length + chunk.length > 32768) return this.close();
        this.pending = Buffer.concat([this.pending, chunk]);
        while (this.pending.length >= 2) {
            const bytes = this.pending, opcode = bytes[0] & 15;
            if ((bytes[0] & 0xf0) !== 0x80 || !(bytes[1] & 0x80)) return this.close();
            let length = bytes[1] & 127, offset = 2;
            if (length === 127) return this.close();
            if (length === 126) { if (bytes.length < 4) return; length = bytes.readUInt16BE(2); offset = 4; }
            if (length > 8580) return this.close();
            if (bytes.length < offset + 4 + length) return;
            const mask = bytes.subarray(offset, offset + 4);
            const payload = Buffer.from(bytes.subarray(offset + 4, offset + 4 + length));
            for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
            this.pending = bytes.subarray(offset + 4 + length);
            if (opcode === 8) return this.close();
            if (opcode !== 2) return this.close();
            if (this.mode === 'silent') continue;
            if (this.mode === 'oversized') { this.send(Buffer.alloc(9000)); continue; }
            if (this.mode === 'early-ack') { this.send(Buffer.from([0, 4])); continue; }
            this.emit('message', payload);
        }
    }
}

readline.createInterface({ input: process.stdin }).once('line', line => {
    const config = JSON.parse(line);
    const serverCert = Buffer.from(config.agentCertificate, 'base64');
    const tlsCert = new crypto.X509Certificate(config.tlsCertificate);
    const hash = crypto.createHash('sha384').update(tlsCert.raw).digest('binary');
    const server = https.createServer({ key: config.tlsKey, cert: config.tlsCertificate, minVersion: 'TLSv1.2' }, (_req, res) => { res.writeHead(404); res.end(); });
    server.on('upgrade', (req, socket, head) => {
        const mode = req.url.split('/')[1];
        if (!['valid', 'bad-signature', 'bad-binding', 'silent', 'oversized', 'early-ack'].includes(mode) ||
            req.headers['sec-websocket-version'] !== '13' || typeof req.headers['sec-websocket-key'] !== 'string') return socket.destroy();
        const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
        socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
        const ws = new FixtureSocket(socket, mode);
        const meshId = Buffer.from(config.meshID, 'hex').toString('base64').replace(/\+/g, '@').replace(/\//g, '$');
        const meshKey = `mesh/${mode}/${meshId}`;
        const nodeKey = `node/${mode}/${config.deviceID}`;
        const device = { _id: nodeKey, meshid: meshKey, name: 'iPhone de Chloé', rname: 'iPhone de Chloé', ip: '127.0.0.1', agent: { ver: 1, id: 0xfffffff0, caps: 0 } };
        const parent = {
            crypto,
            parent: {
                common, config: { settings: {}, domains: {} }, debug() {},
                meshAgentBinaries: {}, meshAgentsArchitectureNumbers: {},
                DispatchEvent() {}, SetConnectivityState() {}, ClearConnectivityState() {},
                certificateOperations: {
                    // Equivalent DER/public-key operations replace forge solely in
                    // this fixture; actual agent signatures are checked by upstream.
                    forge: {
                        asn1: { fromDer: der => Buffer.from(der, 'binary') },
                        md: { sha384: { create: () => null } },
                        pki: {
                            certificateFromAsn1: der => {
                                const certificate = new crypto.X509Certificate(der);
                                if (!certificate.verify(certificate.publicKey)) throw new Error('Invalid device certificate self-signature');
                                return { publicKey: certificate.publicKey };
                            },
                            getPublicKeyFingerprint: key => ({ data: crypto.createHash('sha384').update(key.export({ type: 'pkcs1', format: 'der' })).digest('binary') })
                        }
                    },
                    acceleratorPerformSignature(_index, data, tag, callback) {
                        callback(tag, crypto.sign('sha384', Buffer.from(data, 'binary'), config.agentKey).toString('binary'));
                    }
                }
            },
            agentStats: new Proxy({}, { get: (object, name) => object[name] ?? 0 }),
            trafficStats: { AgentCtrlIn: 0, AgentCtrlOut: 0 },
            webCertificateHashs: { [mode]: hash }, webCertificateFullHashs: { [mode]: hash },
            webCertificateHash: hash, webCertificateFullHash: hash,
            agentCertificateAsn1: serverCert.toString('binary'),
            meshes: { [meshKey]: { mtype: 2, name: 'Isolated fixture', links: {} } },
            wsagents: {}, wsagentsWithBadWebCerts: {}, wsagentsDisconnections: {}, duplicateAgentsLog: {},
            setAgentIssue() {}, CreateMeshDispatchTargets: () => [], CloneSafeNode: n => n,
        };
        const db = {
            // Pre-enrolled in-memory device; new-device policy/install dependencies
            // and the full web UI/database stack are deliberately outside this test.
            Get: (key, callback) => callback(null, key === nodeKey ? [device] : []),
            GetHash: (_key, callback) => callback(null, []), Set() {}
        };
        CreateMeshAgent(parent, db, ws, { clientIp: '127.0.0.1' }, { agentidletimeout: 0 }, { id: mode, limits: {} });
        if (head.length) ws.consume(head);
    });
    server.listen(0, '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\n'));
});
