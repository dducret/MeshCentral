<!-- SPDX-License-Identifier: Apache-2.0 -->
# Interactive guided assistance — incremental update, 2026-11-20

## Design and scope

Extend the existing, explicitly accepted protocol-2 assistance relay. The
technician prepares up to 20 instructions and sends one immutable step at a time.
Only the local user can mark a step done, request help, or stop the guide. The
technician explicitly sends the next step after completion. Chat remains available
for clarification. Guidance requires the existing Chat / Notify permission.

Rust owns the ordered-step state machine and response transitions. Swift adapts
bounded JSON and the App Group mailbox and renders the current step. No new
Xcode source references, capabilities, entitlements, or dependencies are needed.

Each step may reference a locally approved capture, with its normalized strokes
frozen at dispatch. New captures cannot silently change an earlier instruction.
A technician capture request freezes the last shared frame for a local preview
and explicit sending consent, allowing a Settings screenshot to survive the
return to our app. Nothing is drawn over other applications or clicked remotely.
Steps, feedback and images are transient and cleared when the session ends.

The person returns to the Assistance page to read instructions, respond, and
approve captures. There is no background notification service. Existing ReplayKit
consent, ten-minute session duration, TLS checks and per-document consent remain.

## Baseline

Apply on top of 0.3.0 with the TestFlight fixes and `sharing-preflight-fix`.
Do not replace the Xcode project, Info.plists, entitlements, or signing settings.
The user has reported successful physical-iPad screen sharing; the new guided
workflow still requires a Mac build and device acceptance testing.

Local upstream baseline: `67aff175f6d1093b1a81f8e9230607854d3fbaa6`.
Official remote master observed: `412e2aeb3f209df1c1a238de974d3a44185d7006`.
Fetch and creating `codex/ios-guided-assistance` were blocked by read-only `.git`.
No upstream integration or server deployment was performed.

All additions are original Apache-2.0; no third-party dependency is added.

## Wire extension (iosAssist v1)

`ready.guidedAssistance = 1` advertises support; an old agent leaves the panel's
guide controls disabled. Guide actions are subject to the same live Rust session
gate as chat and frames, and additionally require Chat / Notify rights.

- `guideStep`: UUID `id`, integer `step` and `total` (1..20), nonblank `text`
  (at most 800 UTF-8 bytes), optional current `captureID` and bounded `strokes`.
  The entire JSON message remains limited to 16 KiB. The attached capture is
  copied from previously approved media, never fetched from a path or URL.
- `guideStatus`: same `id`, `step`, `total`, and `status` (`waiting`, `help`,
  `done`, `stopped`). Only local UI responses call Rust's completion function.
- `guideError`: id, step and a fixed reason for an obsolete capture, active
  guide or invalid ordering. These expected races do not terminate screen sharing.
- `guideStop`: the technician can cancel the matching guide, but cannot mark
  a step complete. Stop leaves chat and screen sharing available.
- `captureRequest` now freezes a bounded frame locally. `captureDeclined`
  reports refusal. The existing offer/ack/chunk protocol sends approved bytes.

Only one current step/illustration is retained. A new step requires completion
of the previous one; duplicate, skipped, stale and remotely fabricated completion
messages cannot advance the Rust state. Clearing exchanges cancels the guide.
Up to 32 unique guide IDs per session are retained to reject replay after clearing.
The technician plan is held only in page memory and erased at disconnect.
Neither instructions nor images are included in diagnostic reports.

## Quick start

The local button **Préparer et autoriser l’assistance** records explicit consent
for the first authorized technician joining this broadcast. This is a one-use,
120-second start grant in the shared Keychain, not an enrollment preference and
not a field accepted from the network. The extension consumes that grant only
after ReplayKit's system start. Normal authenticated tunnel parsing and the Rust
consent gate still apply; the grant does not authorize arbitrary control or files.
The first request consumes the consent; termination, interruption and a new
broadcast require fresh consent. A pending local stop is checked before approval.

**Valider séparément l’identité du technicien** retains the former workflow.
Old grants lacking the new optional field default to this separate confirmation.
The picker and **Lancer la diffusion** remain required. No simulated picker tap,
private API, persistent unattended authorization or new entitlement is used.
See [Apple's picker API](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview).

## Checks performed on Windows

- 36 Rust tests; workspace rustfmt and Clippy with warnings denied.
- Actual compiled Rust C ABI: step bounds, matching local completion, help,
  stale replies, cancellation and null handles (`tools/check-guidance-abi.py`).
- Shipped operator JavaScript in a deterministic DOM/WebSocket host: capability
  negotiation, chat permission, plan bounds, annotated step, help, next-step gate,
  stale replies, recoverable capture errors, plain-text rendering and cleanup.
- Swift XCTest scenarios are provided for the engine/IPC and frozen capture;
  no Swift compiler or Xcode is available here, so they have not been executed.
- Upstream desktop parsers still accept the Rust frames and ignore the added
  guide envelopes. License inventory and Xcode file references pass.
- The attempted Chrome visual check was denied by automatic approval because
  the browser tool requires approval while this session's policy is `never`.
  No browser rendering or live operator/server session was verified here.

Mac/device acceptance: build both targets, run XCTest, use the updated operator
page, test help/complete/stop, freeze a Settings frame then return to approve it,
replace the general capture and verify the step retains its illustration, clear
the exchanges, reconnect, and test both quick start and separate confirmation.
These device checks are outstanding; do not label them as already verified.
