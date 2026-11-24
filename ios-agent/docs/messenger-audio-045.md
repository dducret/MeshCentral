<!-- SPDX-License-Identifier: Apache-2.0 -->
# Messenger microphone and ICE 0.4.5

On 2026-11-22 the user confirmed two-way text, a disabled iPad microphone button
with WebRTC waiting, and no microphone icon in the technician's Messenger page.
They reported an absent microphone setting and a blank screen. The latter was
not reproduced here. The observed controls establish that the shared data channel
had not opened. They do not identify the underlying ICE or network failure.

The upstream Messenger page uses an independent peer connection for outbound
media when `multiWebRtc` is true. The app can therefore invoke the existing
audio-only `micButtonClick` once the text relay is paired. Older shared-peer
pages retain the open data-channel requirement. The injected adapter arms one
audio-only request per local tap. The Swift permission delegate still requires
the active invitation, current main frame, HTTPS origin and microphone-only type
and returns the system prompt. Late capture after page exit or relay replacement
stops its tracks. Swift ignores completions from a replaced navigation.

WebKit documents that ICE candidate exposure can change once capture is authorized.
After a successful capture, the adapter requests one ICE restart on the existing
data peer if it has a remote description, stable signaling and is still trying
to connect. No new data peer is created by the adapter. A fresh outbound media
peer uses the existing server signaling and ICE configuration. The remote player
is marked inline. The UI shows the local capture state separately from outbound
ICE connectivity and reports when audio setup has waited more than 15 seconds.
An ICE connection does not prove remote playback. The upstream technician icon
still depends on the data channel and the browser's own media availability.

Platform references reviewed 2026-11-22. The previously used iOS 15+ WebKit
permission delegate and capture state APIs remain within the iOS 16 target.
The host uses its existing microphone usage description. Inline playback and
feature detection use public Web APIs. There is no added framework or dependency.

- [Apple microphone permission](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [WebKit media permission delegate](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:))
- [WebKit ICE candidate policy](https://webkit.org/blog/7763/a-closer-look-into-webrtc/)
- [WebKit inline playback](https://webkit.org/blog/6784/new-video-policies-for-ios/)
- [W3C ICE restart](https://www.w3.org/TR/webrtc/#dom-rtcpeerconnection-restartice)

The Windows Messenger checks exercise the actual upstream capture button and
`startLocalStream` plus the embedded scripts in fixtures. They cover WSS text,
no capture on load, a tap before the data channel opens, denied permission and
retry, one ICE restart, separate outbound status and late stream cleanup. The
legacy shared-peer guard is tested. These fixtures do not execute Swift, WKWebView,
real ICE, or audio. Compile, sign, and validate on iPad using the
[installation and acceptance procedure](messenger-audio-045-fr.md).

Windows checks passed for Messenger routing/page scripts, upstream registration,
desktop framing, assistance, licensing, 15 Python regressions, and validation
of Xcode project structure with 21 Swift references. Packaging verifies every
entry and reconstructs the full source tree from the 0.4.4 snapshot, shipped
delta, and the targeted project version edit.

The incremental source package is based on the actual 0.4.4 Swift recovery ZIP
and its 144-file source snapshot. Native versions move to 0.4.5. The Rust crates
and C ABI remain 0.4.2. The Xcode version edit is manual on the Mac. Git remained
on local `master` revision `67aff175f6d1093b1a81f8e9230607854d3fbaa6`.
Official `origin/master` was observed at `412e2aeb3f209df1c1a238de974d3a44185d7006`.
`.git` is read-only in this workspace. The previous delivery and tracked upstream
server sources are preserved. See `dist/messenger-audio-045-delivery.json`.
