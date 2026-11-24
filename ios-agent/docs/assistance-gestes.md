<!-- SPDX-License-Identifier: Apache-2.0 -->
# Assistance entry and exit 0.4.5

The user confirmed audible two-way MeshMessenger audio on a physical iPad
on 2026-11-23. Earlier Chrome stats established an active, direct Opus stream
from iPad to Chrome on the local network. The user did not specify which
playback remedy restored audibility. TURN and the Release build identity for
that trial were not established.

The enrolled home exposes chat-only connection alongside screen-sharing
preparation. A single invitation banner presents audio, text-only and refuse
choices. The audio choice creates the same consented Messenger host and arms
one microphone request for 30 seconds. The request is consumed once the exact
invitation page is connected in the foreground. Repeated navigation, stop and
expiry cancel it. The existing camera denial, exact-page TLS and WebKit
permission checks still apply. A declined request leaves the manual audio
action available. No microphone preference is persisted.

The common finish action closes Messenger and disconnects the ordinary client.
For ReplayKit it reuses revocation and extension stop acknowledgement. The
finish event clears the root navigation path. A chat-only close remains in an
overflow menu while screen sharing so the UI can preserve the ongoing share.
The app stays on its home screen for the normal iPadOS exit gesture.

The version remains 0.4.5. The previous ZIP and its 150-source snapshot form
the package baseline. SwiftUI navigation is available on the existing iOS 16
target. The Rust bridge, server and SDK/dependency graph are unchanged. See
[installation and device acceptance](assistance-gestes-fr.md).

Windows upstream and local repository revisions were unchanged from the
[RTC record](messenger-rtc-promises.md). Git metadata is read-only, so fetch
and branch writes were unavailable. Windows checks cover existing Messenger
negotiation, permission and text scripts, licensing and Xcode reference
structure. The Xcode build, voice shortcut, accessibility layout and stop
confirmation require testing on Apple platforms.

- [Apple microphone permissions](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:))
- [Apple ReplayKit system picker](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview)
- [Apple guidance on quitting iOS apps](https://developer.apple.com/library/archive/qa/qa1561/_index.html)
