<!-- SPDX-License-Identifier: Apache-2.0 -->
# Assistance console — design and verification

Historical 0.3.0 milestone. The current 0.4.0 source changes and verification are
recorded in [iPad assistance 0.4.0](ipad-040.md).

Date: 2026-11-20. Incremental baseline: the delivered guided-assistance update
(`3cdd11c3e9d20e92be86ca30423f9fde4fbcb0dd53c000022e683cbc8a1575d8`).

## Scope

An original Apache-2.0 MeshCentral plugin adds an Assistance iOS tab for our
experimental agent. It embeds the existing authorized same-origin operator
panel, with the selected device in the URL fragment (not a credential). The
panel must revalidate selection against the authenticated server's device list.
No custom privileged server endpoint, downloaded agent code or package is added.
Existing desktop/chat/file rights and local assistance consent remain enforced.

The upstream UI clears plugin tab content on device refresh. Keep the active
iframe outside that disposable region, hide it when another plugin is selected,
and terminate assistance on leaving the device page or switching devices.

The operator console gains separate device/pairing/consent/sharing states,
numeric network and image-health diagnostics, reusable instructional templates,
and an opt-in intervention report. Reports omit message/step/note content unless
explicitly selected at export, never include screenshots or transfer contents,
and are retained in memory only until discarded, reload or the next session.
Templates are explicitly exported/imported as bounded JSON; no browser database
or automatic persistence stores personal instructions on a shared workstation.

Apple Network APIs supply network-path status/interface/constraints. Rust owns
the portable connection-health classification; Swift owns platform observation.
All new Swift declarations stay in existing source files, preserving Xcode
references, signing, Bundle IDs, App Groups and Keychain configuration.

No touchscreen control, MDM, background audio or automatic resumption of consent
is claimed. Screen sharing still ends when the ReplayKit broadcast ends. These
larger capabilities need their own architecture and physical-device validation.

Official references: [MeshCentral hooks](https://docs.meshcentral.com/meshcentral/plugins/),
[NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor).

## Upstream baseline

Local revision: `67aff175f6d1093b1a81f8e9230607854d3fbaa6`; remote master observed:
`412e2aeb3f209df1c1a238de974d3a44185d7006`. Fetch and creation of
`codex/ios-assistance-console` failed because `.git` is read-only in this session.
No upstream integration or server deployment was performed.

## Protocol and state

The existing authorized `p=2` relay and `iosAssist` v1 envelope are retained.
`ready.consoleVersion = 1` advertises these additions; old agents remain usable
without the new telemetry. Core info identifies the connection owner as
`[app-connected]` or `[broadcast-ready]`; these markers are presence hints only.
Desktop capability and server connectivity also gate the console's request button.

The one-second diagnostic envelope adds `sendMS`, `networkState`,
`networkInterface`, `constrained`, `expensive`, `lowPower`, `thermalState`,
`frameAgeMS`, and `healthCode`. Native snapshots additionally retain the OS
version and feature version. Browser exports copy only explicitly accepted
numeric, boolean and enumerated fields, never the incoming object or socket URL.
Native terminal errors use fixed codes, not Foundation error descriptions.

`mc_connection_health` is a stateless Rust ABI entry point. In priority order:
unavailable/requires-connection path → 1; no completed image in 8 seconds → 2;
serious/critical thermal state → 5; relay RTT or send time >= 900 ms → 3;
constrained path → 4; otherwise 0 (no issue observed, not proof of connectivity).
The browser separately detects telemetry and displayed-image gaps at 10 seconds.
No diagnostic state changes consent, resumes a broadcast, or bypasses TLS.

The local plugin uses MeshCentral's supported `settings.plugins.list` loader.
This list replaces database-managed loading, so the installation instructions
explicitly preserve every other enabled plugin. No public download URL or
automatic updater is configured for this unpublished original plugin.

## Verification on 2026-11-20

Passed in the Windows workspace:

- `cargo fmt --all --check`, locked/offline workspace Clippy with warnings denied,
  and **37 Rust tests**.
- Debug bridge build and `check-guidance-abi.py` against the actual Rust DLL:
  guide lifecycle plus the health classifier through its C ABI.
- `check-assistance.cjs`: actual operator script, relay negotiation, consent,
  chat/transfer/annotation/guide flows, sanitized diagnostic and report behavior.
- `check-console.cjs`: template bounds, malformed import recovery, text rendering,
  report opt-in fields, 500-event bound, cleanup and diagnostic messages.
- `check-console-session.cjs`: authorized device selection, missing-device refusal,
  capability/presence events, origin/source-checked iframe messages, teardown
  after device disconnect/removal and malformed relay messages.
- `check-plugin.cjs`: plugin serialized by the actual upstream `prepExports`,
  domain-relative URLs, refresh preserving the iframe, device switches and leaving
  the plugin page. DOM/WebSocket fixtures do not validate browser rendering.
- `check-desktop.cjs`: Rust frames through the actual stock MeshCentral transport
  and desktop parsers; synthetic JPEG framing only, not real capture/rendering.
- `check-licenses.cjs`, `package_mac.validate_project` and actual HTML resource/ID
  checks. Zero added external dependencies; no changed Xcode metadata or entitlements.

No Swift compiler, Xcode, XCTest, deployed server/browser, or physical-device test
was run for this update. The physical-iPad success reported by the user applies
to the preceding screen-sharing build. Run the French guide's acceptance steps
before treating this console update as device-verified. Plugin compatibility was
checked against the local revision above, not every MeshCentral release/theme.

The incremental packager compares hashes with the source snapshot of the previous
guided update and verifies that snapshot against the delivered ZIP. Only changed
or new source/document files are included. No signing settings, enrollment data,
binary, SDK, cached build, unchanged project or inherited server package is shipped.
