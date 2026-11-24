<!-- SPDX-License-Identifier: Apache-2.0 -->
# Hardware inventory 0.4.2: implementation and verification

Date: 2026-11-22. Incremental source candidate after the actual preserved
`MeshCentral-iOS-0.4.1-messenger-update.zip`, SHA-256
`6f2457b3a62ad42cf2fe13fb68b78136a7d64d10f71956e578491dde1d99f2eb`.
Delivery is not evidence of installation or device validation. Follow the
[French installation/acceptance guide](inventory-042-update-fr.md).

## Implemented fields

| Facts | Native source | Existing Details schema/section |
| --- | --- | --- |
| Apple, generic iPad/iPhone model, technical platform such as iPad14,3 | UIDevice.model, uname.machine | hardware.mobile; identifiers.chassis_manufacturer/product_name; Mobile Device/System |
| arm64 and available processing core count | Compile target, ProcessInfo.processorCount | identifiers.cpu_name; CPU under upstream Motherboard |
| Total physical RAM in integer MiB | ProcessInfo.physicalMemory | hardware.darwin.memory; Memory |
| Charge percentage, charging/discharging when known | UIDevice batteryLevel/batteryState | hardware.battery; Battery |
| OS version | Existing coreinfo osdesc | Operating System |

No serial, IMEI, UDID/IDFV, personal device name, MAC/IP/DNS, disk capacity/free
space, installed applications, uptime, CPU frequency/usage or battery health/cycles
are added. No marketing-name/SoC lookup table or Android/Windows identity is
invented. OS and agent architecture registration retain their existing semantics.
Darwin memory is only a server display schema, not registration as a macOS agent.
Simulator reports its label and host architecture; host RAM/core count/battery are
omitted. Unknown battery readings are omitted; 0% is a string because upstream's
truthiness test hides numeric zero. Full battery means not currently charging.

## Control connection and bounds

After authentication/coreinfo, the existing control connection sends
`{"action":"sysinfocheck"}`. The unmodified server responds with `sysinfo` and an
optional stored hash. The native collector obtains a snapshot on the main actor;
Rust writes a deterministic `{hardware:...}` body into at most 2048 bytes. CryptoKit
SHA-384 hashes those bytes before the hash field is added. A differing hash sends
`{action:"sysinfo",data:{hardware:...,hash:"..."}}`. The hash deduplicates snapshots;
it is not a separate device identity. No timestamps are sent in the hash input.

The server's existing `meshagent.js` validates/stores `si<nodeid>`, supplies the
collection-receipt timestamp and emits `sysinfohash`. Its normal `getsysinfo`
handler requires visibility and Device Details rights (0x00100000). The web UI
reads the stored document and updates Details. No server endpoint, privilege or
configuration change is introduced.

The web Refresh button sends `msg/type=sysinfo` through the existing agent route
(which also requires remote-control or remote-view permission). The native agent
additionally requires the server-supplied Device Details right. Such a request
resends even an unchanged snapshot, refreshing the server timestamp. An inventory
is not a live battery monitor: reconnect or request Refresh to obtain new readings.
Read-only Details users can read the cached inventory even when they cannot route
Refresh; this preserves upstream authorization.

Rust InventoryGate permits one pending collection/send and one accepted request
per 5000 monotonic milliseconds per connection. Early/repeated refreshes are
dropped, not queued; retry after five seconds. Authentication and all handle
operations stay on the serial connection queue. Closing frees the gate; late
main-queue callbacks check the terminal connection state before serialization or
sending. Reconnection creates a fresh connection/gate and does not restore any
assistance consent. Existing incoming control messages remain bounded at 65536
bytes. Hardware labels are ASCII allowlisted and limited to 64 bytes each; invalid
facts/short output are rejected. C callers discard partial output on zero return.

The existing app and ReplayKit connection owners share this collector. No new
background mode/task, socket, polling timer, permission prompt, camera/microphone
access or replay capture capability is added. UIKit collection uses the main actor,
temporarily enables battery monitoring and restores its previous setting. The
ordinary app connection still ends in the background; a separately consented
ReplayKit session follows its existing lifetime. Details remain cached on the
server after disconnect; the connection screen explicitly discloses that behavior.

## Apple API and distribution review

Official documentation checked on 2026-11-22:

- [physicalMemory](https://developer.apple.com/documentation/foundation/processinfo/physicalmemory)
  and [processorCount](https://developer.apple.com/documentation/foundation/processinfo/processorcount):
  public Foundation APIs, iOS 2+, respectively physical bytes and processing cores.
- [UIDevice.model](https://developer.apple.com/documentation/uikit/uidevice/model):
  generic model, not the precise commercial generation.
- [uname](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/uname.3.html):
  public libc platform field; the adapter only reads machine, never nodename.
- [batteryLevel](https://developer.apple.com/documentation/uikit/uidevice/batterylevel):
  iOS 3+, 0..1 with monitoring enabled; -1 is unavailable. Values are checked for
  finiteness/range before conversion. Battery state is optional when unknown.
- [Required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
  and [API categories/reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype):
  disk-space access is deliberately excluded. The display-to-user reason 85F4.1
  cannot simply be reused for Internet inventory reporting. No fingerprinting or
  tracking purpose is implemented. Monotonic time only limits local requests and
  is never exported.

No additional entitlement or purpose string is required for these inventory facts.
The deployment target remains iOS 16. API availability review does not substitute
for compilation with the recipient's actual Apple SDK. No Apple SDK is installed
or executed on this Windows host. Before binary distribution, validate the complete
app/extension privacy report, required-reason declarations for existing API uses
(including local elapsed-time measurements), App Privacy disclosures for server
collection/retention, signing and chosen distribution channel. No App Store/TestFlight
submission or new Apple agreement is performed or implied by this source delivery.

## Verification and compatibility

Local upstream revision: `67aff175f6d1093b1a81f8e9230607854d3fbaa6`, on master.
Official origin/default master observed at
`412e2aeb3f209df1c1a238de974d3a44185d7006`. `.git` is read-only: no fetch, branch
creation, merge or commit was possible; upstream tracked files are unchanged.
Tests execute the local upstream revision, not the remote head or a deployed server.

Windows checks executed:

- Rust formatting, Clippy with warnings denied and all **48 workspace tests**.
- Built bridge + inventory ABI: actual JSON, nulls, lengths, permissions, pending
  send, rate limit, malformed facts and short output.
- `check-inventory.cjs`: five Rust fixtures through actual upstream sysinfo /
  sysinfocheck branches, Mongo validation, store/event, getsysinfo rights and
  Details HTML-generation function, plus the real Refresh button function.
  Cases include 0%, unavailable, charging, full and simulator. This is isolated
  JavaScript execution, not a rendered-browser test or live database deployment.
- Existing upstream, desktop, assistance, console, console-session, plugin,
  Messenger and license checks; guidance/Messenger ABI checks; nine Python
  sharing-configuration tests.
- Native Windows WSS/crypto suite: **11 live connection cases passed**, including
  trust/hostname/pin failures, altered proofs, timeout and consent/revocation ABI
  checks. No persistent test credentials. This is not the Apple transport.
- Xcode structure validation: **21 existing Swift source references**, scheme,
  plist and build phase; this is not compilation or signing.

Two focused XCTest cases cover hash deduplication/forced refresh, simulator/
unknown battery and percentage conversion. Added to an existing referenced test
file; **not executed on Windows**. No Swift build, XCTest, simulator, physical
iPad, real browser or App Store acceptance is claimed. The manual acceptance
must verify initial/forced refresh, app/extension ownership transitions and late
callbacks after disconnect, as well as preceding screen/chat behavior.

Rust crates, native diagnostics/coreinfo/capability version, project marketing
version and future project/package templates are intentionally 0.4.2. Existing
registration version 4, iosAssist v1, consoleVersion 1, plugin 0.1.0 and operator
0.4.0 remain unchanged. No new Swift project reference or dependency is needed.
The delta excludes configured project/plist/entitlements; change Version/Build
precisely on the Mac and rebuild MeshCore.xcframework from the updated Rust ABI.

## Delivery verification

The source ZIP, preserved 0.4.1 archive/snapshot, changed-file hashes and a
reconstruction of the full current source tree are verified by
`python -B tools/package_inventory_042.py --verify`. The local
`dist/inventory-042-delivery.json` is the authoritative checksum/file manifest
and records the actual preceding delivery. Prior archives/snapshots are preserved.
The delta contains 23 changed/new source/document files plus two release metadata
files; the delivered snapshot has 133 files. The project version edit is manual
and excluded from the ZIP. No unchanged source, build output, framework or secret
is included.
