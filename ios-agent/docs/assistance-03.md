<!-- SPDX-License-Identifier: Apache-2.0 -->
# Attended assistance 0.3

Implemented source milestone, 2026-11-20. The user confirmed simulator screen
viewing in 0.2. Version 0.3 has portable verification described below, but has
not been compiled in Xcode or exercised on a physical device in this environment.

## Supported workflow

One authenticated, locally accepted desktop session carries screen viewing,
chat, selected documents, annotated still captures and numeric diagnostics.
These features require that session; there is no unattended/background chat
service. Ordinary MeshCentral Desktop continues to display the screen.
The three original files in `operator/` add the extended technician UI without
changing server handlers or installing packages. They use the current browser
login, `control.ashx`, `authcookie`, a cryptographically random relay identifier,
and the same authorized protocol-2 tunnel request as the stock desktop viewer.

The built-in MeshCentral Chat and Files buttons are not repurposed. The stock
messenger uses a separate, predictable node/user relay identifier and an openUrl
flow; this implementation does not join that flow or launch arbitrary URLs.
The new panel is described in [operator installation](../operator/README.md).
No server changes or account agreements were applied by this development task.

Desktop rights and no-desktop restrictions are enforced by the existing parser
and Rust consent gate. Chat additionally requires CHATNOTIFY (0x4000).
NOFILES (0x400) disables selected-document exchange except for full administrators,
consistent with MeshCentral's file restriction. Still captures derive from
already-authorized screen media, not filesystem access. Guests are excluded.

## Protocol and boundaries

The existing WSS relay carries UTF-8 JSON envelopes with type `iosAssist`, v=1,
action and optional ctrlChannel `102938`. The latter makes stock viewers ignore
these new envelopes. Incoming/outgoing messages are limited to 16 KiB, pending
outgoing controls to 16, one screenshot frame to 512 KiB. The authenticated Rust
session gate is checked for local actions and incoming assistance messages as
well as screen frames. Closing the parent control connection revokes all sharing.

| Action | Payload and behavior |
| --- | --- |
| ready | Emitted only after local consent and capture confirmation; includes chatAllowed/documentsAllowed |
| chat | Plain text, maximum 1,024 UTF-8 bytes, last 40 lines retained; inbound rate capped |
| offer | UUID id, safe basename, integer size 1..2 MiB, document/capture kind, SHA-256 hex |
| ack | id and exact next offset; offset 0 is sent only after recipient acceptance |
| chunk | id, exact offset, base64 for 1..8,192 bytes; stop-and-wait, no pipelined bulk buffering |
| cancel | id; releases transfer state |
| captureRequest | Displays a local prompt; never takes/sends a still automatically |
| annotations | Current capture id and at most 32 strokes/512 total normalized points |
| diagnostics | Numeric FPS, JPEG kbit/s, relay RTT and quality tier; no URLs/identity/content |

The phone only accepts incoming document offers. Received bytes are bounded
before append; Rust owns per-document approval and ordered-transfer state,
and checks arithmetic/length limits. Foundation performs bounded JSON conversion;
CryptoKit computes SHA-256. Exact offsets prevent gaps
and overlaps. SHA-256 must match before exposing or acknowledging the finished
document. One incoming and one outgoing transfer are allowed, with a 60-second
acceptance/progress deadline. Cancellation and session end release state.
No MIME type or filename triggers opening, executing or writing a remote path.

Local document selection uses Apple's picker, security-scoped access and
NSFileCoordinator on a background task. Export uses the system save dialog.
The source filename is a display/download basename only. Archives, executables
and document content are never interpreted by the agent. Empty files are not
supported in this milestone. The technician may retain explicitly sent content.

A locally approved still is the latest JPEG from the authorized screen stream,
with a new UUID. The phone retains that still and displays normalized red strokes
on top; subsequent live-screen rotation does not alter its coordinate space.
A new capture resets the annotations. Invalid/obsolete incoming annotation
references fail closed. No overlay is drawn over other apps and no touch event
is injected. Clearing content locally does not erase copies already sent.

## Quality and diagnostics

The Rust controller starts at balanced quality, drops a tier immediately for
send/relay RTT above 900 ms or frames above 300,000 bytes, and recovers one tier
after twelve successive samples below 250 ms and 180,000 bytes. This hysteresis
avoids rapid switching. Maximum JPEG profiles are:

| Tier | Maximum fps | Short/long side | JPEG quality |
| --- | --- | --- | --- |
| Economy | 1 | 360 / 640 | 0.30 |
| Balanced | 2 | 720 / 1280 | 0.50 |
| Detailed | 3 | 900 / 1600 | 0.65 |

Capture does not upscale the source. Simulator UIKit output can be smaller.
Only one capture/encode/send is in flight; missed opportunities are dropped.
Metrics are one-second samples of submitted JPEG frames/bytes. RTT is a WebSocket
ping to the relay server, not technician display latency or a speed test.
Send completion measures local transport backpressure, not acknowledged rendering.
The adaptive controller is therefore telemetry-based adjustment,
not end-to-end congestion control. Stock Desktop quality requests cannot raise
these limits. The operator panel receives the same numeric diagnostics.

The app can export an allowlisted JSON report (version, connection stage, TLS
verification result, frame/byte counts, rates, RTT, send delay, tier and sanitized
failure). Neither report contains the host, invitation, credentials, keys, node
IDs, operator identity, filenames, messages or images.

## iPhone extension and lifecycle

ReplayKit still owns the sole device control/desktop connection. The shared
Keychain retains only enrollment/identity, start grants, consent and stop decisions.
User content crosses an App Group container in bounded atomic JSON slots with
complete file protection and backup exclusion. App and extension must belong to
the same group `group.<MESH_HOST_BUNDLE_ID>`. Commands carry unique IDs, the app
waits for acknowledgment before replacing a command, and all slots are scoped
to the current broadcast UUID. The command queue is bounded to eight.

Files are removed at normal end, before a new grant and on app startup without
a live broadcast. After a crash, protected leftovers may remain until cleanup;
this is not a secure-erasure guarantee. Credentials never enter these files.
The app must be foregrounded to interact with chat, document pickers and capture
annotations. Broadcast viewing can continue after switching apps; user content
is not shown as a global overlay or notification. Locking/unavailable shared
storage fails closed when the next protected operation is attempted.

Public Apple references reviewed for this milestone:
[App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups),
[file coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator),
[file protection](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/completefileprotection).
Apple SDK use remains explicitly authorized; no new library or copied SDK sample
is included.

## Verification

- 34 Rust tests, rustfmt and workspace Clippy with warnings denied pass on Windows.
- Actual Rust DLL C ABI tests cover quality degradation/recovery and transfer
  bounds, in addition to 11 real loopback WSS/crypto cases and consent revocation.
- `check-assistance.cjs` runs the shipped operator script with a deterministic
  DOM/WebSocket host: tunnel construction, consent, plain-text chat, both transfer
  directions, duplicate acknowledgment, bad offsets/hash/size/name, capture
  annotation coordinates, diagnostic allowlist and disconnect cleanup.
- The actual upstream desktop/redirection parsers still accept the Rust frames
  and safely ignore the new control envelopes.
- Xcode project references, app/extension entitlements, source license inventory,
  source-only ZIP checksums and isolated Rust build are checked separately.
- Eight new XCTest methods cover the native assistance engine and permission
  restrictions; they are provided for Xcode, not claimed as executed here.

Required Mac acceptance: compile, run XCTest, connect both UIs to the real relay,
test acceptance/refusal and both document directions, freeze/annotate a capture,
exercise slow links, disconnect/reconnect and examine sanitized diagnostic exports.
Physical acceptance additionally covers App Group signing, device locking,
ReplayKit memory limits, rotation, protected content and app suspension.

Upstream HEAD remains 67aff175f6d1093b1a81f8e9230607854d3fbaa6.
Fetching and creating codex/ios-assistance-03 failed because `.git` is read-only.
Original server files are unchanged; no reset, force push or background updater
was used. All added source is Apache-2.0; no external Cargo, Swift or JS package.
