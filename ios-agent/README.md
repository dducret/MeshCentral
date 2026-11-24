<!-- SPDX-License-Identifier: Apache-2.0 -->
# MeshCentral iOS agent: attended assistance 0.5.2 SDK 26 validation candidate

The [0.5.2 ReplayKit startup fix](docs/diffusion-replaykit-052-fr.md) prevents
the optional empty JavaScript-core reply from clearing Desktop availability
and reports extension configuration and startup failures on the iPad. Apply
it to the delivered 0.5.1 SDK 26 sources.

The [0.5.1 SDK 26 rollback](docs/retour-sdk26-051-fr.md) restores the ReplayKit
capture path from the delivered 0.5.0 with the unified session, screen masking,
chat and audio. It applies to the 0.5.1 ScreenCaptureKit sources and documents
the two app-target settings to revert in the configured Xcode 26 project.
The [SDK 27 prototype](docs/screencapturekit-051-fr.md) is archived separately.

The [0.5.0 session update](docs/seance-050-fr.md) brings screen, microphone and
conversation status together. A local control masks the screen while the live
chat and audio remain connected. Rebuild the app and extension with Rust 0.4.5
and update the two operator assets for the panel's masking indicator. The guide
records the Windows checks and the Release tests to run on Apple devices.

The [0.4.8 audio resume update](docs/reprise-audio-048-fr.md) adds a
large manual resume button after a background interruption on iPhone and iPad.
It reuses the original connected chat and unexpired consent. It requires a
rebuilt Rust 0.4.4 framework. Follow the guide for Release acceptance.

The [0.4.7 background audio candidate](docs/audio-arriere-plan-047-fr.md)
can retain an established two-way call after local acceptance with background
audio selected. That option is on by default for each supported invitation.
It requires the Xcode audio mode, a rebuilt Rust 0.4.3 framework and a physical
device running iOS/iPadOS 17.5.1 or later. Background audio was reported working
until opening an app that uses sound.

The [0.4.6 keyboard layout update](docs/chat-clavier-046-fr.md) enlarges the
composer text and gives Send and Finish priority above the iPhone keyboard.

The [0.4.6 chat text update](docs/chat-texte-046-fr.md) enlarges Messenger
messages and follows the system text size on iPhone and iPad. The compact chat
layout preserves space for the transcript. See the guide for device acceptance.

The [low-vision interface update](docs/assistance-basse-vision-fr.md) enlarges
the invitation, finish and connection controls and supports larger text.

The [assistance workflow update](docs/assistance-gestes.md) adds direct chat
connection on the home screen, a combined invitation and microphone action,
and one finish action for the session. See the [iPad checks](docs/assistance-gestes-fr.md).

The [MeshMessenger 1.3.1 compatibility patch](docs/messenger-rtc-promises.md)
adapts the four legacy WebRTC callback overloads to promises inside the
consented WKWebView, in Debug and Release. Follow the
[installation and live audio checks](docs/messenger-rtc-promises-fr.md).

The user confirmed two-way Messenger text on iPad with 0.4.4. The 0.4.5 update
lets the user request microphone access while the WebRTC data channel is still
connecting and reports capture and outbound audio connectivity separately.
See the [implementation record](docs/messenger-audio-045.md) and
[Mac/iPad acceptance procedure](docs/messenger-audio-045-fr.md).

If Swift files were not applied with the 0.4.4 documentation, use the
[eight-file recovery package and destination check](docs/ipad-chat-044-recovery-fr.md).
It repeats the original verified Swift sources; the app version remains 0.4.4.

The [0.4.4 iPad home and Messenger update](docs/ipad-chat-044.md) simplifies the
enrolled home to one primary assistance action with an Options menu. It adds a
native text composer, actual page/relay/audio readiness, bounded failure reporting
and exact-page URL comparison tolerant of default-port/query-encoding normalization.
Apply the [incremental installation and acceptance guide](docs/ipad-chat-044-update-fr.md)
after 0.4.3. The user reports local Chat acceptance but a blank page and no microphone
response; this update has not been built or validated on an Apple device here.
Rust/C ABI remain 0.4.2; screen sharing still uses the existing system picker.

The [0.4.3 Chat repair](docs/chat-043.md) makes incoming invitations visible above
the navigation content and exposes bounded rejection reasons. It accepts both
existing upstream openUrl command envelopes and falls back from an empty display
name to the operator username. Apply the [0.4.2-to-0.4.3 guide](docs/chat-043-update-fr.md).
The user confirmed hardware inventory working on 2026-11-22 but reported no Chat
response with the app in the foreground. The exact deployed cause and this patch's
Apple acceptance remain unverified. Rust crates/C ABI remain at 0.4.2.

The [0.4.2 hardware inventory](docs/inventory-042.md) populates the standard
MeshCentral Details tab with model/platform, RAM, processing cores/architecture
and available battery status through authenticated `sysinfo`. Apply the
[incremental installation and iPad acceptance guide](docs/inventory-042-update-fr.md)
after the actual 0.4.1 delivery. No server/plugin patch or new entitlement.
Windows protocol/ABI checks pass; Swift/Xcode and physical-device acceptance
remain pending. This is a source candidate, not an installed or device-verified build.

The [0.4.1 MeshMessenger implementation](docs/messenger-041.md) adds the standard
web Chat invitation and a consenting, foreground-only audio/chat window on iPad.
Apply the [incremental Mac/iPad instructions](docs/messenger-041-update-fr.md)
after 0.4.0. WebKit audio, Swift compilation and device acceptance remain pending.

The preceding [0.4.0 implementation and verification record](docs/ipad-040.md)
covers broadcast revocation/relaunch, iPad layout, confirmed transfer progress and
console freshness. Apply its [incremental Mac/iPad guide](docs/ipad-040-update-fr.md)
after the delivered 0.3.0 assistance-console update. This is a source candidate:
Swift/Xcode, signing, real browser/server and physical-device acceptance remain
outstanding. The older milestones below describe the inherited foundation.

An Xcode application project now provides enrollment and connection screens over
the portable Rust core, C ABI and Apple SDK adapter. It supports HTTPS MeshCentral
invitations, mobile links, `.msh` files and manual enrollment, authenticated WSS,
pinned server identity and a persistent device key in the Keychain. Follow the
[Mac/iPhone guide](README-MAC.md) to compile and sign it locally. The Apple sources
and XCTest suite have **not been compiled or run** in this Windows environment.
The user reported successful compilation and simulator enrollment of 0.1 with a
server screenshot, and subsequently confirmed simulator screen viewing in 0.2.
Version 0.3 adds chat, adaptive quality, annotated still captures, selected-document
exchange and sanitized diagnostics. The new Apple version remains uncompiled here;
The user has now reported successful physical-iPad viewing with the prior fixes.
The incremental [guided-assistance update](docs/guided-assistance.md) adds ordered
instructions, local done/help responses, frozen illustrated steps and explicit
quick-start consent. These additions still require Mac/device verification.
Install the dependency-free [technician panel](operator/README.md) to use the
extended features; standard Desktop viewing continues to work.

The [Assistance iOS console update](docs/assistance-console.md) adds a local
MeshCentral plugin, selected-device panel, live connection-health assessment,
five editable guide templates, bounded JSON template import/export and an opt-in
intervention report. See the [incremental installation guide](docs/assistance-console-update-fr.md).
No new third-party dependency or Xcode configuration change is required.

The Rust core remains `no_std`, allocator-free and free of unsafe code. Pointer
handling is isolated in `bridge/`, which uses Rust's standard library. Neither
crate has an external dependency. Cryptography runs in the platform SDK, not a
handwritten RSA implementation. The Rust DER encoder only assembles the device
certificate to be signed by that SDK.

Live TLS authentication has been exercised using the Rust bridge, a Windows .NET
native-crypto test host and the actual `meshagent.js` handler in an isolated
loopback fixture. That verifies the protocol/ABI and server interaction, not the
Apple transport. The read-only desktop relay, local consent and capture hosts are
implemented in source. Rust-generated frames are exercised through the actual
upstream browser parsers; this does not validate JPEG rendering or Apple capture.

## Design and findings

- [MeshCentral protocol](docs/protocol.md): wire layout and authentication trust boundaries.
- [iOS feasibility and architecture](docs/ios-feasibility.md): supported-API candidates, limitations, and implementation sequence.
- [Licensing inventory](docs/licensing.md): source policy, upstream conflicts, and platform/toolchain boundaries.
- [Secure connection and native build](docs/secure-connection.md): trust policy, C ABI, Apple build steps and verification boundaries.
- [Xcode application](docs/xcode-app.md): build, invitation handling, UI lifecycle and validation boundaries.
- [Screen sharing](docs/screen-sharing.md): relay policy, consent, simulator and ReplayKit extension ownership.
- [Assistance 0.3](docs/assistance-03.md): five features, bounds, App Group IPC and verification.
- [Guided assistance and quick start](docs/guided-assistance.md), with [incremental installation in French](docs/guided-assistance-update-fr.md).
- [iPad assistance 0.4.0](docs/ipad-040.md), [installation and acceptance](docs/ipad-040-update-fr.md).
- [Integrated console and diagnostics](docs/assistance-console.md), [local plugin](plugin/iosAssistance/README.md).

The 0.5.2 Git snapshot on `codex/ios-agent` is based on MeshCentral
`7d52d950b6d066e7212d7831b87b5da9359651a5`, the tip of the official
and fork `master` branches on 2026-11-24. Windows verification on that
revision passed Rust formatting, Clippy, 52 Rust tests, the license and
interoperability checks below, 11 native WSS cases, the C ABI checks, and
nine ReplayKit configuration tests. Xcode 26 Release, signing and physical
device acceptance for 0.5.2 are pending.

## Portable development

Run from this directory with Rust 1.99.1 (the initial validated toolchain),
rustfmt, Clippy, and Node.js 24 for the interoperability and license checks:

```text
cargo fmt --all --check
cargo clippy --offline --locked --workspace --all-targets -- -D warnings
cargo test --offline --locked --workspace
node tools/check-licenses.cjs
node tools/check-upstream.cjs
node tools/check-desktop.cjs
node tools/check-assistance.cjs
node tools/check-console.cjs
node tools/check-console-session.cjs
node tools/check-plugin.cjs
node tools/check-messenger.cjs
node tools/check-messenger-page.cjs
node tools/check-messenger-rtc.cjs
node tools/check-inventory.cjs
# PowerShell 7 / .NET 10 on Windows:
./tools/check-native.ps1
python tools/check-guidance-abi.py target/debug/meshcentral_ios_bridge.dll
python tools/check-messenger-abi.py target/debug/meshcentral_ios_bridge.dll
python tools/check-inventory-abi.py target/debug/meshcentral_ios_bridge.dll
python -m unittest discover -s tools -p test_sharing_configuration.py
```

The upstream check feeds Rust-generated frames into the actual checked-out
`meshagent.js` handler using an in-memory WebSocket and a controlled server
environment. It does not run a deployed server, use a real device, or establish TLS.
Test-only identity providers are not cryptographic implementations.

The native integration test uses ephemeral certificates and in-memory keys,
mandatory TLS trust/hostname checks, distinct TLS and agent identity certificates,
and the real server's agent-signature verification and registration acknowledgment.
It tests a pre-enrolled in-memory device, not the full MeshCentral deployment or
new-device enrollment policy. See the detailed verification record in the native
connection document.

Do not add crates without reviewing their complete resolved graph and actual
license files. The initial dependency check rejects **all** external crates so a
dependency cannot accidentally bypass that review.

## Remaining native acceptance

1. Compile and test the Apple adapter on Mac/Xcode, then run the same trust and
   failure scenarios on a physical iPhone. Apple SDK use was explicitly authorized
   by the user on 2026-11-19; original code and added dependencies remain restricted
   to Apache-2.0 or MIT.
2. Validate the implemented enrollment UI against a MeshCentral test group on
   iPhone. Agree an iOS architecture ID; the prototype uses an explicitly
   experimental ID and does not impersonate Android or macOS.
3. Run the implemented desktop path in the simulator against a test server and
   verify visible output, explicit consent, rejection, disconnect and recording UI.
4. Build and verify the ReplayKit extension on a physical iPhone, including
   keychain sharing, rotation, protected content, app suspension and system stop.
   Desktop is advertised only by attached experimental capture hosts. Complete
   end-to-end validation before distributing this as a production capability.

The deployment target is iOS 16 or newer, subject to SDK and physical-device
validation. The user reported earlier simulator and physical-iPad sharing. The 0.4.2
sources have not been built or run on Apple platforms in this Windows session.

Original code and documentation: [Apache-2.0](LICENSE).
