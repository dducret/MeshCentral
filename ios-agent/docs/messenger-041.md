<!-- SPDX-License-Identifier: Apache-2.0 -->
# MeshMessenger 0.4.1: implementation and verification

Date: 2026-11-21. Incremental source candidate following the delivered 0.4.0
`MeshCentral-iOS-0.4.0-ipad-assistance-update.zip`, SHA-256
`77521a5ae15ed57bb44cda8c5c0c17bfa40b61301760e11b167c7ff927e55560`.
User request: make the standard MeshCentral **Chat** / microphone conversation
available to this iPad agent. This is a foreground WebKit integration, not a
background VoIP engine, a Safari handoff or microphone capture in ReplayKit.

## Implemented path

1. The unmodified MeshCentral web UI opens its technician Messenger window and
   sends `meshmessenger`. The existing server checks Chat & Notify rights and
   routes `openUrl` with authenticated `userid`, operator name and effective rights.
2. The authenticated native control connection accepts only the HTTPS Messenger
   URL on its enrollment origin/port and domain path, with a single `id` query.
   Arbitrary URLs, credentials, fragments, extra/duplicate query parameters and
   guest requests are rejected. Rust checks the exact Messenger identifier against
   this device's SHA-384 PKCS#1 public-key node ID, operator ID, domain and rights.
   Requests are limited to one accepted parse per five seconds per connection.
3. An invitation is offered locally. During ReplayKit the extension writes the
   bounded invitation into its existing Keychain status; the app reads it only
   after checking the broadcast owner, heartbeat and deadline. No extension opens
   a browser or microphone. The person returns to the app to accept.
4. An explicit local button opens the server's existing Messenger page in a
   nonpersistent `WKWebView`. Rust owns offered/active/terminal consent state:
   120 s to accept, at most 600 s from invitation receipt, no renewal by repeated
   acceptance. At most one offered/open conversation exists in the containing app.
5. The person activates the microphone in Messenger. WebKit prompts for permission
   only for microphone requests from the exact main-frame page/origin. Camera and
   foreign frames/origins are denied. Native controls show capture state, mute/
   unmute and close. A native Activate Microphone button invokes only the page's
   existing audio-only action after its WebRTC data channel is ready, avoiding
   reliance on pre-permission device enumeration. There is no automatic invocation.
   The embedded view hides unrelated camera/file/export controls;
   the existing native assistance document path retains its own consent/bounds.

The WebKit session validates TLS chain/hostname, the optional enrolled private CA
and the exact leaf certificate hash seen on the authenticated control connection.
It does not accept arbitrary certificate challenges. Alternate web/agent origins
or ports, and certificate rotation during one conversation, are deliberately not
accepted by this candidate. WebKit WSS behavior with a private CA needs device
validation; never fix it by bypassing trust. No native object or credential bridge
is exposed to JavaScript. Top-level navigation stays on the invitation URL; new
windows, downloads and redirects to other pages are denied.

Closing, backgrounding, control disconnection, broadcast revocation or expiry
closes consent, disables WebKit capture/playback and unloads the page. Active
ReplayKit screen sharing may continue when the app backgrounds, but this audio
conversation does not. A new conversation requires a new Chat invitation and local
acceptance. Stop propagation and WebKit capture release are asynchronous OS work;
latency must be measured on hardware. System permission dialogs can temporarily
make the app inactive, so shutdown uses background, not every inactive transition.
If the process is killed, iPadOS owns resource teardown; no unattended restart is added.

Closing Messenger alone does not stop screen sharing. The persistent assistance
stop bar remains available in Messenger when a broadcast exists and ends both.
Voice can also be used with the ordinary foreground control connection, without
preparing screen sharing. No invitation push notification, auto-wake or persisted
conversation history is added. A technician receives no new decline acknowledgement;
their standard Messenger window may remain waiting after refusal/expiry.

## Platform and compatibility

App and extension release 0.4.1; native registration software number remains 4.
`iosAssist v1`, consoleVersion 1, operator 0.4.0 and plugin 0.1.0 are unchanged.
No upstream server file is modified or shipped. Existing server Messenger/STUN/
TURN configuration is reused; a successful text relay does not prove WebRTC media
can traverse the network. The source tests do not prove browser/iPad compatibility.

Reviewed public Apple/WebKit documentation on 2026-11-21:

- [WebKit getUserMedia support](https://webkit.org/blog/11353/mediarecorder-api/):
  WKWebView media capture support since iOS 14.3. Existing target remains iOS 16.
- [WKUIDelegate media permission](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:))
  and public WebKit headers: API introduced in iOS 15. Camera is denied here.
- [Microphone capture state](https://developer.apple.com/documentation/webkit/wkwebview/setmicrophonecapturestate(_:completionhandler:))
  and [media playback suspension](https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended(_:completionhandler:)).
- [Media authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media):
  add the microphone usage description to the app only. No camera purpose,
  background audio mode, new entitlement or distribution agreement is added.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  public WebKit, explicit permission and visible capture indicators. This review
  does not certify App Store acceptance or an installed Mac SDK.

Git remains at `67aff175f6d1093b1a81f8e9230607854d3fbaa6`, `master`, with official
`origin`. Remote default `master` HEAD was checked again as
`412e2aeb3f209df1c1a238de974d3a44185d7006`. `.git` is read-only: no fetch, branch,
commit or integration. Existing untracked sources and preceding deliveries are
preserved. Compatibility fixtures use the local revision.

## Actual Windows results

- PASS: Rust formatting, Clippy with warnings denied, 44 workspace tests
  (four new Messenger tests).
- PASS: `check-native.ps1`, 11 live loopback WSS/crypto cases plus existing
  consent/transfer/quality C ABI checks.
- PASS: compiled `check-messenger-abi.py` and existing `check-guidance-abi.py`.
- PASS: `check-messenger.cjs` executes the upstream Chat action, server invitation
  branch/rights rejection, microphone audio-only action and WebRTC button gating
  in bounded fixtures. It never opens a microphone or actual server/browser session.
- PASS: existing upstream, desktop, assistance, console, console-session and
  plugin Node checks; nine sharing-configuration Python tests.
- PASS: source licensing check; project structure validates 21 Swift references.
  The existing server FileSaver 2.0.2 body was matched to its upstream tag, its
  actual MIT license inspected and retained in the licensing inventory; the
  Messenger test checks that body hash. No third-party code is shipped in this delta.

Two new XCTest methods cover native invitation URL parsing and native consent
adaptation. They are supplied but **not executed**. Swift compilation, Xcode,
signing, simulator, rendered Messenger, WebRTC audio, Bluetooth/earpiece routing
and physical iPad operation remain **unverified**. The Windows VM cannot replace
these acceptance gates. See [the French installation/test procedure](messenger-041-update-fr.md).

Packaging verifies the actual 0.4.0 ZIP and full preserved source snapshot. Only
changed/new sources and delivery metadata are included. Configured Info.plist and
project.pbxproj are excluded, replaced by precise manual edits. No removal/rename,
binary, secret, SDK, server bundle or signing setting is delivered. The new
manifest/snapshot becomes the next delivery baseline; old artifacts are retained.
