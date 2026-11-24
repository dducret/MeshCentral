<!-- SPDX-License-Identifier: Apache-2.0 -->
# iOS feasibility and proposed architecture

Research date: 2026-11-19. The statements below are documentation findings and
engineering decisions; no iOS device or SDK was exercised in this Windows session.
The user subsequently reported successful 0.1 simulator enrollment. Version 0.2
adds a read-only simulator app-view host and a ReplayKit broadcast extension in
source. The user subsequently confirmed simulator viewing works in 0.2.
Version 0.3 implements attended chat, adaptive quality, annotated stills,
selected documents and diagnostics; see [the current scope](assistance-03.md).
No physical capture path has yet been verified here.

## Capability assessment

| Capability | Initial direction | Evidence and limit |
| --- | --- | --- |
| User-started screen sharing | Candidate for the first native milestone | ReplayKit offers a system broadcast picker and a sample-buffer broadcast extension [1][2]. Physical-device testing remains required. |
| Screen guidance | Operator sees the screen; the person performs actions | No public general-purpose cross-app input injection API was identified in the reviewed documentation. Do not promise remote taps or system-wide annotation. |
| Screen/audio recording | Screen only initially, microphone disabled | Apple requires explicit consent and a visible or audible indication when recording user activity [3]. |
| Permanent unattended availability | Excluded from the first release | Background runtime is scheduled or time limited; an ordinary socket is not a guarantee of permanent execution [4]. |
| Remote shell, unrestricted files, downloaded agent code | Excluded | Sandbox and downloaded-code restrictions conflict with a desktop-agent feature set [3]. |
| Device identity and secure transport | Implemented; simulator enrollment reported by user | Persistent signing keys, trusted server pin, TLS verification, secure credential storage, and a fresh nonce per connection. Physical-device verification remains required. |

Apple provides remote control inside FaceTime, subject to its own conditions [5].
That feature is not evidence of an SDK that an independent MeshCentral app can use.
The decision to exclude general remote input is an engineering conclusion from
the reviewed APIs, not a claim that no Apple product can control an iPhone.

## Capture APIs are evolving

The retrieved Apple pages mark ReplayKit broadcast APIs deprecated and reference
ScreenCaptureKit. The Markdown availability metadata for `SCContentSharingPicker`
lists iOS 27.0+, while the ReplayKit picker begins at iOS 12 and its sample handler
at iOS 10 [1][2][6]. This is documentation metadata, **not verification of a released
SDK or device availability**. Keep capture behind a native adapter; check the
actual Xcode SDK annotations and deployment target before selecting ReplayKit
for the proposed iOS 16+ baseline, or a version-gated ScreenCaptureKit path.
Do not assume the macOS implementation or older ReplayKit tutorials apply unchanged.

## Proposed split

- Rust `no_std` core: bounded wire codecs, authentication sequencing and signing
  transcripts, local consent, and later relay policy and backpressure.
- Small native iOS host: enrollment UI, local approval/stop, TLS/WebSocket and
  certificate adapter, secure key storage, application lifecycle, and signing.
- Native capture implementation: system consent UI plus the applicable capture
  API/extension, orientation-aware images, bounded queues, and immediate teardown.

When a broadcast extension is used, its lifecycle is separate from the containing
app. Design the necessary App Group/Keychain access groups, minimal short-lived
session transfer, and stop/revocation signaling explicitly. Do not assume the
containing app stays running or share unrestricted long-lived credentials with
every process. A broadcast pause, finish, error, or network loss must stop media;
the containing app and extension need a tested revocation mechanism.

The first visible workflow is: enroll with trusted server details, connect,
identify the helper, approve one screen-sharing request, accept the system capture
UI, show session/recording status, and stop at any time. No media may leave before
both local approval and system capture confirmation. Reconnection needs new consent.

## Toolchain and distribution gates

The portable Rust library can be checked on Windows. Native iOS builds need the
Apple SDK and a suitable Mac/Xcode environment; Rust documents device
`aarch64-apple-ios` and Apple Silicon simulator `aarch64-apple-ios-sim` targets [7].
No Apple target, SDK or app-signing profile is installed in this Windows
environment. The native Swift package is now accompanied by an Xcode application
project with enrollment and connection screens. Its sources are packaged for
compilation on Mac; the iOS 16 deployment target remains unvalidated on device.

Apple SDK use was explicitly authorized on 2026-11-19, with original code and added
dependencies still limited to Apache-2.0/MIT. The [native connection adapter](secure-connection.md)
now has source and tests, pending Mac/Xcode execution. Apple developer tools and
distribution retain their separate agreements [8]; none was accepted on the user's
behalf and no Apple sample implementation was copied here.

## Official sources

1. [RPSystemBroadcastPickerView](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview) ([availability metadata](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview.md)).
2. [RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler) ([availability metadata](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler.md)).
3. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), especially 2.5.1, 2.5.2, 2.5.4 and 2.5.14.
4. [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app).
5. [Remote control in a FaceTime call](https://support.apple.com/guide/iphone/request-give-remote-control-a-facetime-call-iph5d70f34a3/ios).
6. [SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker) ([availability metadata](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker.md)).
7. [Rust iOS target support](https://doc.rust-lang.org/rustc/platform-support/apple-ios.html).
8. [Apple agreements and guidelines](https://developer.apple.com/support/terms/).
