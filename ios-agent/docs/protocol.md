<!-- SPDX-License-Identifier: Apache-2.0 -->
# MeshCentral protocol findings

Source baseline: `67aff175f6d1093b1a81f8e9230607854d3fbaa6`, inspected 2026-11-19.
This document describes the subset needed by the Rust foundation, not every
MeshAgent command or a claim of full interoperability.

## Control connection and enrollment

The control connection is a WebSocket at `wss://host[:port]/[domain/]agent.ashx`.
See `webserver.js` around lines 6424-6449 and 8126-8157. Enrollment must carry a
trusted server agent public-key fingerprint (`ServerID`), a device group
identifier (`MeshID`), and the server address. The agent identity is its own
certificate/key pair, not the operator's password. Keep this identity stable
across reconnections; do not send credentials to arbitrary relay URLs.

Two hashes must not be confused: the TLS certificate hash observed on the WSS
connection and the pinned public-key hash of the server's **agent certificate**.
`webserver.js:301-308` computes them separately. `certoperations.js:646-669`
accepts full certificate hashes and describes public-key serialization: RSA uses
PKCS#1 DER, rather than SubjectPublicKeyInfo DER. The future adapter should use
SHA-384 of the actual peer certificate DER for the TLS binding, and verify the
server agent certificate's RSA public-key fingerprint against enrollment data.
Normal TLS chain/hostname validation or explicitly configured local CA trust
must also succeed. There is no "ignore certificate errors" mode in this design.

## Binary handshake

Numbers are big-endian (`common.js:23-30`). Each item is one complete WebSocket
binary message; there is no stream-wide length prefix on the control channel.
See `meshagent.js:471-605`, `meshagent.js:1212-1265`, and `meshaccelerator.js:30-36`.

| Command | Layout after the 16-bit command | Meaning |
| --- | --- | --- |
| 1 | TLS hash: 48 bytes; sender nonce: 48 bytes | Challenge, exactly 98 bytes total |
| 2 | Certificate length: u16; X.509 DER; signature | Certificate and authentication proof |
| 3 | Four u32 values; 48-byte MeshID; capabilities u32; name length u16; UTF-8 name | Agent registration |
| 4 | Empty | Server confirms completed registration; an agent-side use can skip server proof, which this implementation never requests |
| 5 | Expected ServerID hash | Optional server certificate selection; only the modern 48-byte variant is encoded here |

Command 3 offsets: information version 2, architecture ID 6, agent version 10,
platform/icon type 14, MeshID 18, capabilities 66, name length 70, name 72.
The old server also accepts a 70-byte nameless variant. This implementation emits
the 72-byte minimum with an explicit name length. It accepts only modern 48-byte
MeshIDs whose final 16 bytes are not all zero, because the server interprets that
pattern as a legacy 32-byte ID. Platform values are 1 through 8, and do not assign
an iOS architecture ID. Architecture registration remains an integration task.

For `H = observed TLS certificate hash`, `A = agent nonce`, and `S = server nonce`:

- The server signs `H || A || S` with its agent private key.
- The client verifies the pinned server identity **and** that signature.
- The agent signs `H || S || A` with its persistent device private key.
- The server verifies the agent signature, derives the node ID from its public
  key, checks the group/enrollment policy, and sends command 4 when complete.

Signatures use SHA-384 with RSA PKCS#1 v1.5, not RSA-PSS. This initial codec accepts
raw 2048/3072-bit RSA signatures (256/384 bytes). Legacy PKCS#7 and larger RSA keys
are intentionally unsupported and rejected. `IdentityProvider` is the explicit
trusted adapter boundary; implementors must parse X.509, validate key properties,
check the pinned fingerprint, verify the signature, and securely sign. The Apple
SDK provider now exists behind the C bridge; its Mac/device validation is pending.
The Windows native test provider exercises real certificates/signatures.
No cryptographic primitive is implemented by hand.

The handshake rejects wrong order, repeated challenges/proofs, mismatched TLS
hashes, malformed or oversized messages, early acknowledgments, and provider
failures. Errors close the logical handshake. A new connection requires fresh
cryptographically random nonces and a new handshake instance. Adapters must impose
an authentication deadline, cap WebSocket reassembly before allocating, and close
the underlying socket on failure. Output frames must be sent in the returned order;
do not reuse a handshake after a send failure.

## After authentication

Registration still advertises capabilities zero. The native transport handles
bounded JSON control, ping/pong and `coreinfo`. Version 0.2 announces desktop (1)
through `coreinfo` only when a capture host is attached. It never announces
terminal (2), files (4), console (8), or downloadable JavaScript (16).
See `agents/meshcore.js:854`. The server may send
command 10 to unknown architecture IDs (`meshagent.js:1006-1024`); an iOS adapter
must handle this without downloading/executing a JavaScript core or self-updating
an application executable.

The current registry in `agenttypes.js` has no dedicated iOS entry. The Xcode
prototype uses experimental ID `0xfffffff0` with experimental read-only Desktop;
it may display as unknown. Before production deployment, agree an assigned ID
and any small registry/UI adaptation with upstream.

## Assistance relay and screen format

`agents/meshcore.js:1398-1432` receives an authenticated JSON message with
`action: "msg"`, `type: "tunnel"`, relay URL, session ID, operator information,
rights, and consent flags. The relay pairs peers and sends `c`, or `cr` when
recording (`meshrelay.js:489-565`). The agent then receives a protocol selection;
2 means desktop (`agents/meshcore.js:3730-3744`). Enforce operator rights and
same-server/domain relay allowlisting in addition to local consent. Show recording
status before approval. Reject terminal, files, registry, input injection, and
arbitrary destination tunneling in the first iOS implementation.

The browser desktop protocol is **not** simply an H.264 stream. In
`public/scripts/agent-desktop-0.0.2.js:219-245`, command 7 sets width/height and
command 3 carries an image tile with x/y coordinates. Desktop messages have a
command/size header distinct from control-channel messages; large frames use
command 27 wrapping. Initially, investigate ImageIO-encoded JPEG tiles, resize
and orientation handling, bounded queues, and a conservative frame rate. This
format is implemented by `src/desktop.rs` and the Apple JPEG encoder since 0.2.

Version 0.3 adds bounded `iosAssist` control envelopes on that authorized relay.
The new panel uses authenticated control/relay requests, per-document acceptance
and capture-bound annotations; no protocol-5 filesystem access is advertised.
See [assistance protocol](assistance-03.md) for exact limits and verification.
`tools/check-desktop.cjs` exercises the actual browser transport and desktop
parsers with Rust frames, including the jumbo threshold. It validates framing,
not real image decoding. Raw ReplayKit buffers are never sent directly.

`AssistanceSession` models the local consent gate after authentication.
Adapters must bind each ticket to one authenticated relay and display its operator.
Only local UI events may approve it; network messages must never call approval.
OS capture confirmation is a second gate. Stop, timeout, transport loss, or capture
failure revokes the ticket; reconnecting cannot reuse it. Remote input stays denied.
The bridge now shares this gate between the live control handle and a single
viewer, using a mutex in the standard-library ABI layer. Destroying the control
handle revokes a live share. Real authenticated ABI tests cover this revocation.
