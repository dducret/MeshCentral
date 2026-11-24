<!-- SPDX-License-Identifier: Apache-2.0 -->
# Read-only screen sharing: integration design

Baseline: MeshCentral 67aff175f6d1093b1a81f8e9230607854d3fbaa6.
The user reported successful simulator enrollment on 2026-11-19 and supplied a
server screenshot. This is user-reported Apple execution of the previous version,
not physical-device verification or local execution by this Windows agent.

## Transport and consent

The authenticated control connection advertises desktop support only when a
capture host is attached. The server's tunnel request must identify an operator
with desktop rights and a same-origin/domain meshrelay.ashx URL. TCP/UDP routing,
guest/public sessions and non-desktop protocols are excluded. WSS still requires
TLS trust and hostname validation; the relay leaf is bound to the authenticated
control connection's TLS leaf (a differing server-supplied relay pin is supported
only after strict parsing). Redirects and arbitrary destinations are rejected.

The relay receives c/cr, then protocol 2; cr is shown as server recording. Only
after this negotiation does the local UI ask to accept the named operator. A
fresh Rust consent ticket gates every outgoing frame; network options cannot
grant consent. Requests expire after 60 seconds; sessions after ten minutes.
Local rejection/stop, transport loss or capture failure revokes sharing.

Rust frames screen dimensions (command 7), JPEG tiles (3), and jumbo envelopes
(27), with bounded sizes. Apple SDKs encode JPEG. One frame may be in flight;
slow connections drop capture opportunities instead of accumulating a queue.
Keyboard, mouse, touch, clipboard, shell and arbitrary file operations are not
executed. Version 0.3 adds selected documents, chat and still annotations over
the same authorized relay; see [assistance](assistance-03.md).

## Native capture hosts

Simulator: explicitly labelled app-window capture using public UIKit rendering,
after local consent. This displays the actual app UI, not a synthetic picture,
and cannot capture SpringBoard, other apps or the Mac desktop.

iPhone: a ReplayKit broadcast-upload extension owns both control and relay
connections so app suspension does not break the broadcast. The app supplies a
short-lived, one-use start grant through its shared Keychain group; the extension
uses the same device key and enrollment. The system broadcast picker is used
directly, with its microphone button hidden. Audio buffers are discarded.

The extension starts with no permission to transmit images. The containing app
shows pending operator requests read from the shared Keychain; explicit decisions
are bound to the current broadcast and request UUIDs. The person stays in/returns
to the app to accept the request, then can switch apps. A visible app indicator,
local stop and iOS's broadcast controls terminate sharing. Expired grants, stale
decisions, capture pauses and missing shared-Keychain access fail closed.

Version 0.3 adds an App Group filesystem mailbox for selected user content,
with complete protection, atomic slots and backup exclusion. Start/stop consent
still uses the shared Keychain scoped to this app and its extension.
No private API or copied sample code is used. This source remains
Apache-2.0 with no external Cargo/Swift dependencies; Apple SDK use is authorized.

Apple platform capture and extension execution require Mac/device validation.
ReplayKit is retained for the iOS 16 baseline; current documentation marks future
SDK deprecations in favor of ScreenCaptureKit. That does not establish availability
of newer APIs on the user's SDK. References:
[broadcast handler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler),
[system picker](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview),
[shared Keychain](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

## Verification record for 0.2

Historical checks below. The user subsequently confirmed simulator screen
viewing works. See [0.3 verification](assistance-03.md) for the current source.

- Windows: `cargo fmt --all --check`, workspace Clippy with warnings denied and
  all 29 Rust tests pass. New tests cover desktop dimensions, output bounds,
  standard/jumbo boundary framing and view-only/forbidden rights.
- The 11 existing live TLS authentication cases pass after the bridge change.
  Their authenticated connections also exercise the C ABI share gate: no gate
  before authentication, no media before both approvals, no concurrent second
  viewer, fresh consent for a new request and revocation on control destruction.
- The actual upstream browser redirection and desktop parsers accept Rust
  dimensions and tile payloads across the 65535-byte threshold, with byte-for-byte
  delivery. These fixtures contain synthetic markers, not decoded screenshots.
- Xcode target references, extension embedding, independent Rust archive outputs,
  matching Keychain entitlements, plist/scheme XML, source license inventory and
  ZIP checksums are verified structurally. This is not `xcodebuild` execution.
- XCTest adds same-origin/domain/protocol/rights/forwarding rejection cases and
  a framing ABI check. These Apple tests and both capture hosts remain unexecuted
  here. Real relay WSS behavior and rendered screen output need the user's Mac
  test. Physical-device signing, broadcast memory/lifecycle and protected content
  remain unverified.

Remote HEAD still matches the baseline. `git fetch origin` and feature-branch
creation were attempted but denied by the read-only `.git` permissions. Local
work is preserved and the server files remain unchanged; no synchronization
reset, force push or background automation was used.
