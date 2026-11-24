<!-- SPDX-License-Identifier: Apache-2.0 -->
# iPad assistance 0.4.0 — implementation and verification

Date: 2026-11-21. Source validation candidate, not a signed or device-validated
release. Base: `MeshCentral-iOS-0.3.0-assistance-console-update.zip`, SHA-256
`decc71f6c8352e29c4e0f3102a4f5c6a2e316eb2bc5837b767beae61328e7a8b`.
The user approved P0 lifecycle/recovery and P1 iPad interaction/transfer clarity.
The earlier physical-iPad report does not validate these changes.

## P0: implemented lifecycle changes

- `session.rs` owns the portable preparation (120 s), broadcast (600 s) and
  silence/stop acknowledgement (10 s) policies. Additive C ABI functions expose
  remaining time and revocation-only decisions. They never grant assistance.
  Invalid phases, future/nonfinite native clock values and expired deadlines
  fail closed; remaining time saturates at zero. Broadcast duration starts at
  extension startup, including connection/consent time, as in the preceding build.
  Relay media sends and assistance actions also check the deadline, so a delayed
  timer cannot by itself extend permission to transmit.
- A Keychain owner record binds a broadcast UUID to revoked/completed flags.
  Only the containing app writes that record. The extension checks it after
  identity loading, before accepting a relay/capture callback and on its 0.5 s
  poll. Revocation cannot be overwritten by an extension shutdown callback.
  The existing Rust consent/capture gate remains mandatory on outgoing media.
- Missing heartbeat requests revocation and retains an explicit stopping state.
  It no longer silently treats a stale status as proof of termination. Pending,
  unconsumed preparation can be cancelled. Otherwise a stopped status is needed;
  after ten seconds without confirmation, the app offers a separate local
  **J’ai arrêté la diffusion dans iPadOS** confirmation. It requires the user to
  stop through iPadOS first and successfully persists revocation before releasing
  the UI. This is user confirmation, not programmatic proof of system termination.
  Reopening the app distinguishes a completed owner from an unconfirmed stop.
- A new preparation generates a new UUID and requires a new explicit choice of
  quick-start consent or separate technician confirmation, plus Apple's system
  broadcast start. There is no automatic reconnection or consent renewal.
- Document selections and in-flight imports are bound to a local content epoch;
  reads also carry an operation UUID. Backgrounding, disconnect or termination invalidates late completion and
  errors. Already submitted commands remain bound to the same broadcast; they are
  not resent on foreground. Missing command acknowledgement causes revocation.
- App Group content slots now include the broadcast UUID in their filenames,
  as well as the envelope. Old teardown clears only its own three slots. Startup
  and preparation remove recognized orphan/legacy slots, preserving unrelated
  files. Complete file protection, backup exclusion and the 6 MiB bound remain.
  App and extension must both be rebuilt from 0.4.0; mixed native builds are not
  supported. Protected leftovers after a crash are cleaned on the next preparation
  or startup; this is not a secure-erasure guarantee.
- Local “clear exchanges” also cancels pending transfers so subsequent chunks
  cannot repopulate cleared content. Browser file-read failures from an old session
  cannot overwrite the new/closed session's transfer state.

## P1: implemented interaction changes

The shared start section presents the next action, a preparation countdown,
separate confirmation mode and explicit relaunch. Root and assistance pages keep
a local stop/status bar outside their scrolling forms. The bar displays remaining
time while the broadcast is active. The actual stop still requires the extension
and transport queues to process teardown; queued/in-flight network data cannot
be recalled. Measure propagation on hardware, rather than asserting zero latency.

At widths of at least 850 points and standard Dynamic Type sizes, the active
assistance view places guidance/captures alongside chat/documents/diagnostics.
Narrow windows and accessibility text sizes use one column. Semantic fonts,
textual states, VoiceOver labels and 44-point primary controls are provided.
An enlarged, scrollable frozen capture has explicit 1x–4x zoom buttons and stop
access. Guidance illustrations retain their frozen image/strokes. No overlay or
input is injected into another app. New message/step/offer/capture indicators
appear in the app and on returning to it; no push/background notification service
or unread-history database is added.

Native transfer snapshots have separate optional sending/receiving summaries:
offered, transferring, completed, declined, cancelled and timedOut. Outgoing
progress counts acknowledgements, not queued bytes; final completion follows the
receiver's SHA-256 check. Progress publication is throttled to 0.5 s between
nonterminal chunks, limiting large App Group snapshot rewrites. Local previews,
export buffers and pending selections are dismissed on session end/background.
Native diagnostic stages/network/error codes have French labels; exported errors
remain fixed codes rather than Foundation descriptions or connection URLs.

The technician console distinguishes an absent first image, an old displayed
image (10 s), absent telemetry (10 s), and inactive session. It shows two transfer
progress indicators and resets them at disconnect. The time remaining is shown
only when the agent advertises it; stale telemetry makes it unknown. Health
suggestions remain observations, not definitive diagnoses.

## Compatibility and packaging

`iosAssist` stays v1 and `consoleVersion` stays 1. Additive `ready.sessionTiming=1`
and bounded `diagnostics.remainingSeconds` (0..600) are optional. The console
accepts 0.3.0 agents without pretending they provide timing; older consoles ignore
the added fields. Optional `cancel.reason` uses `rejected` or `timeout`; absence
retains the generic cancellation label. No rights, authentication or relay route
changes. Plugin stays 0.1.0, unmodified. Native agent registration software version
changes from 3 to 4; that is not a wire-protocol version change.

Local upstream: `67aff175f6d1093b1a81f8e9230607854d3fbaa6`. Official `origin`
still points at Ylianst/MeshCentral, default branch `master`; remote HEAD observed
again on 2026-11-21: `412e2aeb3f209df1c1a238de974d3a44185d7006`.
`.git` is explicitly read-only in this session, so no fetch, branch creation,
commit or integration was performed. `AGENTS.md` and `ios-agent/` remain untracked;
tracked upstream sources are unchanged. Compatibility checks target the local
revision, not every release or theme. Use a `codex/` branch when Git writes become
available, preserving all existing sources and divergent history.

`tools/package_ipad_040.py` verifies the preceding ZIP and the 114-file source
baseline before computing its delta. It excludes the configured Xcode project:
only its marketing version changed locally, with precise recipient-side edits in
the [French installation/acceptance guide](ipad-040-update-fr.md). No entitlement,
Info.plist, signing setting, SDK, binary, build cache or server bundle is shipped.
No source removal or rename is required. The new delivery manifest and complete
source snapshot are retained locally for the next incremental delivery. The
packager refuses to overwrite an existing artifact.
The delta contains 35 modified/new source or documentation files and two delivery
metadata files. An in-memory merge onto the preserved delivered baseline,
including the documented Marketing Version edit, reproduced all 118 current
source files byte for byte. The recipient still selects their own next Build.

## Verification boundaries

Portable regression coverage adds Rust/ABI watchdog boundaries, separate transfer
progress and backward-compatible timing/diagnostics, plus late browser file-read
completion. New XCTest cases cover native clock adaptation, transfer approval/
acknowledgement/clear/refusal, diagnostic labels and session-scoped cleanup.
XCTest, Swift compilation and actual iPad behavior are not executable here.

The graphical service inventory was reachable through munim-computer-use.
Opening the local preview tab was blocked because the tool requires approval
while this session's policy is `never`. No rendered browser validation, deployed
server session or Apple-device operation was performed. The temporary loopback
preview server was stopped. See the acceptance guide for those outstanding gates.

Windows checks executed on 2026-11-21 (Rust 1.99.1, Node 24.14.1, Python 3.14.4):

| Check, from `ios-agent/` | Actual result |
| --- | --- |
| `cargo fmt --all --check` | PASS |
| `cargo clippy --offline --locked --workspace --all-targets -- -D warnings` | PASS, no warnings |
| `cargo test --offline --locked --workspace` | PASS, 40 tests |
| `node tools/check-licenses.cjs` | PASS, original Apache-2.0 sources, two workspace crates, no external Cargo dependency |
| `node tools/check-upstream.cjs` | PASS against the local upstream revision above |
| `node tools/check-desktop.cjs` | PASS using the upstream desktop parser and synthetic frames |
| `./tools/check-native.ps1` | PASS, 11 live loopback WSS/crypto scenarios and consent/transfer/quality ABI checks |
| `python tools/check-guidance-abi.py target/debug/meshcentral_ios_bridge.dll` | PASS, watchdog boundaries and guidance/health ABI |
| `node tools/check-assistance.cjs` | PASS, transfers, consent, clearing, guidance, late browser callbacks and timing negotiation |
| `node tools/check-console.cjs` | PASS, console models, stale images/telemetry and bounded remaining time |
| `node tools/check-console-session.cjs` | PASS, frame lifecycle and session isolation |
| `node tools/check-plugin.cjs` | PASS, plugin routes, permissions and integration fixtures |
| `python -B -m unittest discover -s tools -p test_sharing_configuration.py` | PASS, 9 configuration checks |
| `package_mac.validate_project` | PASS, 21 Swift source references and project/scheme/plist structure; not a Swift compiler |
| HTML resource/selector inspection | PASS, 56 unique IDs, three local resources and 34 literal selectors |
| Simulated merge of incremental payload onto the actual delivery baseline | PASS, 118 source files match after the targeted Marketing Version edit |

No Swift compiler or Xcode toolchain is installed in this Windows workspace.
The new XCTest cases are supplied but not executed. Code review and project
structure checks do not establish Swift type-checking, signing, simulator or
physical-device results. These remain explicit acceptance gates in the guide.

## Apple API review

Reviewed official documentation on 2026-11-21:

- [ReplayKit picker](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview)
  and [sample handler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler):
  keep the existing public system-start and extension lifecycle. Documentation
  metadata includes OS 27 boundaries; it does not establish the installed SDK's
  availability. Check the actual Mac SDK annotations before accepting the build.
- [Dynamic Type accessibility sizes](https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize),
  available since iOS/iPadOS 15, and [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).
  The project still targets iOS 16. Zoom uses ordinary SwiftUI buttons and scrolling.
- [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
  and [background UI lifecycle](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background):
  existing entitlements are reused; no extra background mode or entitlement.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  public APIs, local consent and visible stop remain the design constraints.
  SDK authorization does not imply account agreement acceptance, publishing or
  distribution approval. No Apple account or server was modified.
