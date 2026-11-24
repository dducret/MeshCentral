<!-- SPDX-License-Identifier: Apache-2.0 -->
# Chat invitation repair 0.4.3

Date: 2026-11-22. Base: the actual delivered 0.4.2 inventory ZIP, SHA-256
`1c3b4b84fadc132918421ab8c7c2a07d4ae1db2a0407e0ba46d027ed62870b49`.
The user reports that hardware inventory works and Chat produces no visible
reaction while the iPad app is in the foreground. The deployment's precise cause
has not been established: no iPad logs or signed-in server session were inspected.

## Findings and changes

- Previously the invitation appeared only in a Form section, potentially below
  the current scroll position. A top safe-area banner now spans the NavigationStack
  on connection and assistance screens, with explicit Open/Decline controls.
  This does not open a page or microphone automatically. The existing invitation
  section remains available. Large text/narrow width can stack the actions.
- The control connection formerly used `try?` and silently discarded failures.
  A rejected Chat command now produces a fixed, allowlisted reason: command,
  URL structure, origin/path/port, rights or device/operator identity. The callback
  reaches the app directly, or through an optional BroadcastStatus rejection field
  when ReplayKit owns the connection. Reports contain a UUID and reason only;
  no remote URL, authentication parameter, operator identity or raw error text.
  Dismissing an extension report remembers its ID so polling cannot redisplay it.
- The existing upstream agent accepts both `action:openUrl` and
  `action:msg,type:openUrl`; the iPad now recognizes both with identical URL,
  identity, rights and consent checks. The checked-out web Chat handler emits the
  first form. Generic non-Messenger URL opening remains unsupported.
- An empty/whitespace realname previously prevented fallback to username and
  rejected an otherwise valid invitation. Display-name selection now chooses the
  first nonempty, bounded, control-free candidate. Identity still comes from the
  authenticated userid and Rust binding, never the display name.
- An invitation ID is no longer marked consumed before foreground/connection/busy
  eligibility checks. A still-valid invitation in the extension mailbox can be
  offered when the app returns and is ready. Existing 120 s offer expiry and 600 s
  conversation limit are unchanged; no background wake or consent reuse is added.
- Both valid and invalid invitation attempts now share the five-second admission
  limit. There is no queue of rejected payloads. Existing connection generation,
  extension owner/heartbeat/revocation and local-close checks remain in force.

The technician's browser URL includes its own title/authentication parameters.
The server-generated device invitation contains only the id query item. The fix
does not accept an operator session token on the iPad or remove origin/TLS checks.
An origin mismatch is reported, not rewritten to an unverified URL. LAN-only mode
can prevent upstream Chat dispatch altogether; no local rejection can be shown
for a command the server never sends. Dedicated DNS-domain inference and differing
agent/web origins remain outside this patch and must not be worked around by
relaxing validation.

## Platform, security and versions

No new capability, entitlement, background mode, permission or third-party package.
Apple's public [safe-area inset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:))
and [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)
documentation was reviewed on 2026-11-22. The latter requires iOS 16, matching
the existing deployment target. This is not a local Apple SDK build.
The microphone purpose requirement and foreground-only WebKit consent/TLS policy
from [0.4.1](messenger-041.md) continue to apply. A missing microphone purpose
is visible in the invitation banner when Open is attempted.

App/extension and displayed agent versions become 0.4.3. Rust crates, C ABI and
the existing 0.4.2 XCFramework remain unchanged. Registration version 4,
iosAssist v1, consoleVersion 1, plugin 0.1.0 and operator 0.4.0 are unchanged.
No Xcode source references, plist or entitlements need replacement. Rebuild both
native targets; do not regenerate the configured project.

Local upstream `master` remains `67aff175f6d1093b1a81f8e9230607854d3fbaa6`;
official origin/default master observed at
`412e2aeb3f209df1c1a238de974d3a44185d7006`. `.git` is read-only, so no fetch,
codex branch or commit was possible. No upstream source is modified/shipped.

## Verification

Windows: formatting, Clippy and all 48 Rust tests pass. Upstream, desktop,
assistance, console, console-session, plugin, inventory and license checks pass,
as do nine sharing-configuration tests. The Messenger test now executes the real
`routeCommandToNode` instead of stopping at a mocked routing hook. It verifies
default/named domains, percent-encoded @/$ node keys, admin/limited rights,
empty realname, id-only device URL and LAN-only non-dispatch, plus the existing
audio/WebRTC controls. All identities/addresses in fixtures are synthetic.

Two new XCTest cases cover encoded default-domain invitations, explicit HTTPS
port 443, both envelopes, empty display name fallback, typed rejection reasons
and absence of remote payload in diagnostic encoding. They were **not executed**:
no Swift/Xcode compiler, Apple SDK, simulator, iPad or rendered browser is available
for this verification. Windows interoperability checks do not run the Swift parser
or prove banner layout. Follow [the device acceptance guide](chat-043-update-fr.md).

The prior 0.4.2 archive and all 133 delivered source hashes were verified directly
against its retained manifest/snapshot. Older 0.4.1 artifacts are no longer present
locally; the old 0.4.2 packager therefore cannot re-verify its own historical base.
No missing archive was invented or recreated. The new packager uses the actual
verified 0.4.2 delivery and preserves all available artifacts.

Native Windows WSS/crypto checks passed all 11 live connection cases. Messenger,
inventory and guidance checks passed against the actual built 0.4.2 C ABI.
Structural Xcode validation passed for 21 Swift references, scheme/plist/build
phase; this is not native compilation. All source/dependency license checks passed.

The incremental delivery contains 18 changed/new source/document files plus two
release metadata files, with 136 files in its new source snapshot. The configured
project is excluded; the sole local project difference is the documented 0.4.3
marketing-version edit. `tools/package_chat_043.py --verify` checks ZIP contents,
hashes, prior delivery and full reconstruction by merging the delta and that
targeted edit. `dist/chat-043-delivery.json` records the authoritative new baseline.
