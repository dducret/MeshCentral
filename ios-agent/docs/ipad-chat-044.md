<!-- SPDX-License-Identifier: Apache-2.0 -->
# iPad home and Messenger page integration 0.4.4

Date: 2026-11-22. Source delta after the actual 0.4.3 delivery, SHA-256
`9e4bff1b3e63458c91ee0166e30af35bf1a0c9211f3f047ce959d657dbb735c9`.
The user reports accepting Chat on the iPad while the site indicates refusal,
a blank area below the microphone controls, no text field and no visible response
to the microphone button. The exact remote wording/cause was not captured.
They also requested an essential-only enrolled home, ideally one button.

## Implemented changes

The enrolled home now has one primary **Démarrer l’assistance** action and an
Options gear. Connection details, chat-only connection, enrollment replacement,
guidance/documents/diagnostics and separate operator approval are available in
Options. Pending invitations/errors and actionable requests appear when needed.
Stop and session state remain visible on home, Options, assistance and Messenger.
The initial consent text still identifies first-authorized-technician approval,
ten-minute screen sharing, possible retention of images and hardware reporting.

The screen-sharing sequence is still **Start assistance -> tap the Apple broadcast
control -> confirm Start Broadcast in iPadOS**. This is one primary action per step,
not one total tap. No simulated tap, private subview access, permission bypass or
new capture API is introduced. The bounded preparation/revocation/consent policy
is unchanged. Simulator remains explicitly separate.

The conversation cover is attached to the NavigationStack owner, including while
Options or Assistance is the visible destination. Messenger now loads when its
WKWebView is mounted, with an explicit flexible frame
and minimum height for history. A visible native text composer passes its message
as a structured argument to `callAsyncJavaScript`, not interpolated executable
text. The adapter uses the server page's existing `xsend`/transport and local echo;
the duplicated HTML composer is hidden. No new wire protocol is introduced.
Messages are limited to 4096 UTF-8 bytes, one native send at a time. The adapter
requires an open selected transport, at most 65536 buffered bytes and fewer than
16 queued WebRTC-switch entries. It preserves the draft on a rejected attempt,
clears it after handoff to the existing page transport, and does not auto-resend.
This is not a remote receipt/reading acknowledgment. Closing clears the draft.

Raw URL equality formerly gated navigation, responses, microphone permission and
the native microphone action. `matchesPage` instead permits equivalent default
HTTPS port and query percent encoding while requiring the same HTTPS origin,
port, exact path and single identical id. Foreign hosts/ports/paths, different
IDs, credentials, fragments and extra auth/query parameters remain rejected.
Blocked main-frame navigation now reports an error instead of silently canceling.
This addresses a concrete rejection path in the source, not proof that it was
the cause on the reported device. It does not forward the operator's auth token.

A one-second poll reads only fixed boolean/numeric page state, never conversation
contents: compatible page, relay state, WebRTC readiness, media API availability
and an allowlisted media-error code. One poll may be pending; ten seconds without
its completion or twenty seconds without a usable page is terminal. The UI no
longer equates local acceptance or HTTP page loading with a connected conversation.
Messages can work over WSS while audio waits for WebRTC. Transport closure is
described as disconnection, not an invented local refusal. The local upstream
server explicitly ignores the openUrl result; no new accept/decline protocol is
invented to explain an unobserved server message.

Microphone actions are disabled until the compatible page and audio channel are
ready. Existing audio-only `micButtonClick` is retained. A transparent wrapper of
the public getUserMedia promise records only a bounded error category (permission,
missing device, unavailable device, other), leaving constraints and authorization
unchanged. Page loading never calls getUserMedia. Playback may start after explicit
conversation acceptance; microphone capture still requires a local action and the
WebKit/iPadOS permission. Camera requests remain denied. Terminal failures appear
in a banner after the conversation closes. No silent page reload or reconnection.
Page epochs reject stale script results; timers stop on close. Existing Rust
consent expiry/background/disconnection rules remain in force.

## Apple APIs and compatibility

Official documentation reviewed on 2026-11-22:

- [callAsyncJavaScript](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)):
  public API since iOS 14, structured arguments and main-frame execution in the
  page content world. No native script-message handler is exposed to the page.
- [Media playback policy](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/mediatypesrequiringuseractionforplayback):
  playback user-gesture policy is distinct from microphone capture permission.
- [System broadcast picker](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview):
  the documented user-tapped control is retained. Current Apple documentation
  marks it deprecated (availability metadata ends at iOS/iPadOS 27) and points to
  ScreenCaptureKit SCContentSharingPicker. This patch does not migrate the working
  capture/extension architecture; check the actual Mac SDK and device behavior.
  No claim is made that programmatic one-tap capture is supported by this adapter.

Deployment target stays iOS 16. No additional entitlement, purpose key, background
mode, third-party dependency or Apple agreement. Existing microphone description,
signing, privacy declarations and distribution acceptance remain prerequisites.
No Apple SDK is executed or redistributed on Windows. No App Store/TestFlight
submission is performed.

Native app/extension and displayed versions are 0.4.4. Rust crates/C ABI and the
0.4.2 XCFramework remain unchanged. Registration version 4, iosAssist v1,
consoleVersion 1, plugin 0.1.0 and operator 0.4.0 are unchanged. No new Swift file
reference is needed and configured project/plist/entitlements are excluded.

## Verification and delivery

Windows checks: formatting, Clippy and all 48 Rust tests; upstream, desktop,
assistance, console, console-session, plugin, Messenger, inventory and license
checks; nine sharing-configuration tests. The new `check-messenger-page.cjs`
executes actual page startup/relay `c` handling and upstream xsend with the actual
native adapter scripts: waiting/connected/disconnected states, WSS/WebRTC sends,
text/HTML escaping, UTF-8 bounds, transport backpressure, no automatic capture and
permission-denial reporting. These use isolated VM/DOM/WebSocket fixtures and
are not real browser rendering, real WebRTC or Swift/WebKit execution.

One new XCTest checks equivalent page URL forms and hostile origin/path/id/query
variants. It is not executed here. No Xcode compilation, signing, XCTest, simulator,
physical-iPad, keyboard layout or two-way media validation is claimed. The manual
[acceptance procedure](ipad-chat-044-update-fr.md) remains necessary, including
the exact server refusal wording if it recurs.

Local upstream master: `67aff175f6d1093b1a81f8e9230607854d3fbaa6`.
Official origin/default master observed at
`412e2aeb3f209df1c1a238de974d3a44185d7006`. `.git` is read-only, so no fetch,
branch creation, commit or integration. Upstream tracked files are unchanged.
The actual 0.4.3 ZIP and all 136 baseline source hashes were verified. Earlier
0.4.2 artifacts are absent locally and were not fabricated. All available prior
artifacts are preserved. New manifest: `dist/ipad-chat-044-delivery.json`.

Native Windows WSS/crypto: all 11 live connection scenarios passed. Messenger,
inventory and guidance checks passed against the built 0.4.2 C ABI. Structural
Xcode validation passed for the existing 21 Swift references, scheme/plist/build
phase. License/source checks passed with no added dependency.

The delivery has 17 modified/new source/document files plus two release metadata
files and a 140-file snapshot. `tools/package_ipad_chat_044.py --verify` verifies
the ZIP/base/snapshot hashes and reconstructs the complete current tree from the
0.4.3 baseline, the delta and the targeted manual project version edit. It excludes
unchanged sources, build output, configured project/plist/entitlements and secrets.

## Delivery consistency follow-up, 2026-11-22

The user reported eight Swift mismatches in a copy of the project and subsequently
clarified there was no local correction to preserve. A fresh audit of the current
Windows source tree found all 140 original source hashes matching the original
manifest before this follow-up. The original ZIP SHA-256 and all 19 entries match;
the eight Swift files also match the snapshot and extracted ZIP directory.
The native Messenger composer is present in `MessengerConversationView`.
The reported divergent copy has not been identified or inspected, and the absent
0.4.3 artifacts prevent independently comparing the reported seven older files.
No Swift source was changed during this follow-up.

The recovery ZIP deliberately repeats those eight verified Swift files, together
with new/modified verification tools and instructions. This is a recovery of an
incomplete application of the existing 0.4.4 update, not a new app version. The
standalone checker pins the original eight hashes and checks an explicit target
root on Windows or Mac, reports every mismatch and never writes to that target.
It does not require older archives, and does not accept the target's own manifest
as proof of correctness. Local changes and newline conversions also differ by
design; they must not be silently overwritten to obtain a passing hash.

See [the recovery instructions](ipad-chat-044-recovery-fr.md) and
`dist/ipad-chat-044-recovery-delivery.json` for the new actual delivery baseline.
The original ZIP/manifest/snapshot remain preserved. Git state and official
default-branch revisions were rechecked and are unchanged from above; `.git`
remains read-only, so fetch/branch writes were not attempted. Apple/device
acceptance is still pending; no new Apple capability or dependency is introduced.

Executed on Windows for this follow-up: both Messenger checks (including the
actual native adapter scripts), assistance, inventory, upstream and licensing
checks; six new delivery-checker regression tests; structural Xcode validation
of the existing 21 Swift references. All passed. Rust/native binaries are
unchanged, so Rust formatting/Clippy/workspace and live WSS tests from the
original milestone were not rerun. The recovery packager checks the original
ZIP/140-file snapshot, all recovery entries/current source hashes, and a full
merge starting with all eight Swift files absent. Apple compilation and device
tests remain unexecuted.
