<!-- SPDX-License-Identifier: Apache-2.0 -->
# MeshMessenger 1.3.1 promise compatibility on iOS

The user reported separate iPhone simulator experiments with Chrome. WKWebView's
legacy success callbacks stalled even when WebKit reported a successful offer.
Modern promises restored SDP signaling and RTP in separate send and receive
experiments. The local Windows tree matched the delivered 0.4.5 snapshot and
did not contain that experimental DEBUG adapter.

The 1.3.1 Messenger template at `f436143527458d56da0336ea3047c006703fb4e4`
uses callback overloads inside `startWebRTC` and `webRtcHandleOffer`. The host
now installs a short compatibility adapter at document start in the page world,
only in the main frame of the WKWebView created for the consented conversation.
It adapts `createOffer`, `createAnswer`, `setLocalDescription` and
`setRemoteDescription` to their Promise overloads. The adapter keeps the receiver,
offer options, description input, callbacks and legacy resolved return contract.
Calls already using promises go straight to the original API. Pending completions
are ignored once the page or peer closes. A WebRTC rejection uses the original
failure callback, and an exception from a page callback stays distinct from a
WebRTC rejection. The server's timer, SDP/ICE messages, peer/track setup,
data-channel switch and normal hangup remain in the upstream page.

Debug can attach a diagnostic observer for the four operation names and the
fixed events `fulfilled`, `rejected` and `callback-failed`. The observer never
receives descriptions, error objects, peer identifiers or transport data.
Release builds inject the same functional adapter without the diagnostic
observer. The existing native checks on navigation, TLS, consent and microphone
permissions continue to apply. There are no new dependencies or server changes.

The shipped test uses the actual upstream functions and a peer fixture that
reproduces the missing callback. It exercises both SDP directions and the data
peer, Promise passthrough, failure cleanup, late completion and Debug redaction.
It can use the built-in checkout template or a path to the official 1.3.1 template.

```sh
node tools/check-messenger-rtc.cjs /path/to/messenger-1.3.1.handlebars
```

The 0.4.5 source patch is based on the actual delivered ZIP and its source
snapshot. Apple build, simulator interop, audibility and selected TURN pairs
require [the Mac/iOS acceptance procedure](messenger-rtc-promises-fr.md).

On Windows the Node test passed against the local checkout and the official
1.3.1 template. Existing Messenger routing, composer, microphone handling,
upstream registration and licensing checks passed. Xcode project structure
was checked with all 21 Swift references. The incremental ZIP was merged
against the delivery snapshot and checked byte for byte. A local headless
Chrome test could not establish a browser session in this VM. Release
compilation, same-session RTP and selected ICE pairs, audible voice, TURN
and the physical iPad were not verified for this patch.

On 2026-11-23 the user confirmed audible Chrome-to-iPad audio on a physical
iPad. The reverse direction was silent even though the iPad displayed an
active microphone and an established outbound link, with the iPadOS orange
indicator. The app's outbound label checks the local stream and peer ICE
state. It establishes neither media delivery nor audibility. Capture, RTP
delivery, decoded energy and playback still need to be distinguished for the
outbound path. The test did not establish the selected ICE pair or TURN usage.
The first Chrome evidence shows the open data channel. A second report shows
that the separate iPad-to-Chrome audio peer completed offer/answer and connected
over ICE and DTLS with an Opus inbound RTP entry and a direct local host pair.
Chrome also exposes a remote outbound RTP report. The available relay candidate
was not selected for this peer. The expanded inbound report later showed active
input at about 31 kbit/s, 11,947 packets received with zero reported losses, and
non-zero decoded audio energy. That confirms RTP delivery with an audio signal
on the physical iPad-to-Chrome path. The user subsequently confirmed audible
conversation. They did not identify the exact playback remedy. Audio via TURN
and the exact Release build remain unverified.

The Windows repository was on `master` at `67aff175f6d1093b1a81f8e9230607854d3fbaa6`.
Official default `master` was observed at `1eab6b80c90f9e9911f178aa518bf2192e47602c`.
Git metadata is read-only, so fetch and dedicated branch creation could not be
performed. The server checkout was not integrated or modified. References use
the exact deployed version where applicable.

- [MeshCentral 1.3.1 Messenger template](https://github.com/Ylianst/MeshCentral/blob/f436143527458d56da0336ea3047c006703fb4e4/views/messenger.handlebars)
- [W3C WebRTC legacy interface extensions](https://www.w3.org/TR/webrtc/#legacy-interface-extensions)
- [Apple WKUserScript page world](https://developer.apple.com/documentation/webkit/wkuserscript/init(source:injectiontime:formainframeonly:in:))
