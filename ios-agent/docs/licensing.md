<!-- SPDX-License-Identifier: Apache-2.0 -->
# Licensing inventory and release gates

Date: 2026-11-21. This inventory records observed metadata and source provenance;
it is not a legal opinion or certification of every upstream binary.

## New agent source

| Component | License / decision | Verification |
| --- | --- | --- |
| Original Rust core/bridge, Swift adapter and SwiftUI app, Xcode project, C header, tests, scripts, documentation | Apache-2.0 | SPDX headers and local LICENSE, preserving the repository's Apache-2.0 text and notices (ZIP normalizes line endings) |
| External Cargo dependencies, including build/dev/target dependencies | None | `cargo metadata --offline --locked`; fail-closed check in `tools/check-licenses.cjs` |
| Original native bridge / Apple SDK adapter | Apache-2.0 source; Apple SDK use authorized by the user on 2026-11-19 | No third-party wrappers or copied Apple sample implementations |
| External crypto/network libraries or media assets | None added | Foundation, Security and CryptoKit are platform APIs, not vendored code |
| Existing MeshCentral protocol/reference modules | Upstream declares Apache-2.0 | Read in place; original files and notices preserved; no server dependencies installed |
| Original operator HTML/CSS/JavaScript, assistance engine, App Group IPC and adaptive controller | Apache-2.0 | Original implementation, SPDX headers; no npm/Swift/Cargo library, copied snippet, font or image added |
| Original Assistance iOS plugin, console/report/template helpers and Rust health classifier | Apache-2.0 | No downloaded plugin or package; plugin includes the same LICENSE; Apple Network framework used under the existing SDK authorization |
| 0.4.0 broadcast watchdog/ABI, native revocation and scoped IPC, adaptive iPad UI, transfer progress, console freshness, regression checks and incremental packager | Apache-2.0 | Original source; zero new third-party dependencies/assets. Existing public Apple APIs and entitlements only. Source delta excludes linked binaries and SDKs; native distribution audit remains separate. |
| Original test-app icon and its asset catalog (`apple/App/MeshCentralAssets.xcassets`) | Apache-2.0, including both `Contents.json` files | Drawn at all 13 pixel sizes by the original `tools/generate_app_icon.py` using only Python stdlib; each PNG embeds an SPDX notice; no copied artwork, fonts or third-party image library |

Apache-2.0 is the default; MIT is the only fallback for future third-party code.
Before adding a dependency, inspect its actual LICENSE/NOTICE files, version,
enabled features and complete dependency graph, record the selected license branch
and reason, and extend the automated inventory deliberately. Metadata alone does
not establish license compliance. No MIT fallback is needed in this milestone.

The dependency checker allows exactly the two original workspace packages and the
bridge's local dependency on the core. Registry/Git/other path dependencies are
rejected. The Apple Swift package has no remote package dependencies; its binary
target is built locally from this same Rust source. Header checks include Rust,
Swift, C, C#, Python/shell scripts, Xcode project metadata and documentation.
The source ZIP contains no SDK, toolchain, third-party packages, server bundle,
compiled library or signing material. Its Xcode build compiles the Rust bridge
locally. Foundation, Security, CryptoKit, SwiftUI, Combine, UIKit, ReplayKit,
CoreGraphics, CoreImage, CoreMedia, ImageIO, UniformTypeIdentifiers and Network
are used as Apple platform APIs under the recorded SDK authorization.
Version 0.3's assistance features, JPEG encoder and broadcast extension add no third-party dependencies
or copied SDK samples. Browser compatibility tests read the existing Apache-2.0
upstream files in place; these files and server dependencies are not in the ZIP.

## Upstream server conflicts

The root `package-lock.json` at the analyzed revision declares these 16 package
entries outside the strict project allowlist. These are **not approved exceptions**
and are not dependencies of the new Rust package.

| Package | Version | Declared license |
| --- | --- | --- |
| @zip.js/zip.js | 2.8.26 | BSD-3-Clause |
| body-parser/node_modules/qs | 6.16.1 | BSD-3-Clause |
| express-handlebars | 8.0.5 | BSD-3-Clause |
| express-ws | 5.0.2 | BSD-2-Clause |
| glob | 13.0.7 | BlueOak-1.0.0 |
| graceful-fs | 4.2.11 | ISC |
| inherits | 2.0.4 | ISC |
| lru-cache | 11.5.3 | BlueOak-1.0.0 |
| minimatch | 10.2.6 | BlueOak-1.0.0 |
| minipass | 7.1.3 | BlueOak-1.0.0 |
| node-forge | 1.4.1 | BSD-3-Clause OR GPL-2.0 |
| path-scurry | 2.0.2 | BlueOak-1.0.0 |
| qs | 6.15.3 | BSD-3-Clause |
| setprototypeof | 1.2.0 | ISC |
| source-map | 0.6.1 | BSD-3-Clause |
| uglify-js | 3.19.3 | BSD-2-Clause |

Do not relicense these packages by editing metadata. Audit actual usage and
license texts before replacing or removing them for any distributed server bundle.
The existing server is preserved, not represented as allowlist-compliant.

## Platform and tooling are separate unresolved boundaries

Rust is generally Apache-2.0 OR MIT ([official policy](https://rust-lang.org/policies/licenses/));
select Apache-2.0 where offered. That general statement does not audit compiler,
linker, standard runtime, compiler-builtins, OS libraries, Node.js or Python
distributions and their bundled third-party components. The portable library uses
only `core`; the C bridge uses the standard library for owned handles and certificate
buffers. Host tests use already installed Node.js/.NET tools. No toolchain, test
executable, SDK binary or prebuilt framework is committed or distributed here.

Before distributing native binaries, inventory the actual linked artifacts and
required notices, including any license exceptions. The source/package checks do
not certify a linked Windows or iOS binary.

Apple's SDK, system frameworks, signing and distribution have their own
[agreements](https://developer.apple.com/support/terms/). On 2026-11-19 the user
explicitly authorized Apple SDK use, conditional on original code and added
dependencies remaining Apache-2.0 or MIT. That decision is recorded in `AGENTS.md`
and covers the Foundation/Security/CryptoKit adapter in this milestone. It does
not change third-party library requirements, approve publishing, or accept any
developer-account agreement on the user's behalf. No Apple component is bundled.

## 0.4.7 Background audio trial

The Rust consent policy, C bridge changes, Swift and JavaScript adapter, tests
and instructions are original Apache-2.0 code. The resolved Cargo graph still
contains the two workspace crates and no external dependencies. The Apple audio
background mode and existing WebKit SDK are used under the same SDK boundary.
No SDK, browser framework or server package enters the incremental source ZIP.

## 0.4.5 Messenger microphone and ICE

Original Swift, embedded scripts, tests, packager and documentation are
Apache-2.0. The existing Apple WebKit SDK and public web APIs are used without
additional dependencies or redistributing any framework or upstream server code.
The 1.3.1 callback compatibility patch and its fixtures are also original
Apache-2.0 code. Tests load upstream negotiation functions from the checkout
or the specified official template at run time. The template is not shipped.

## 0.5.1 SDK 26 rollback

The rollback restores the delivered 0.5.0 ReplayKit implementation under the
0.5.1 app version. It adds no dependency or SDK material to the source ZIP.
The SDK 27 prototype and its delivery record are retained separately.
[SDK 26 installation and acceptance](retour-sdk26-051-fr.md)

## Archived 0.5.1 ScreenCaptureKit prototype

The capture adapter, lifecycle integration and project settings are original
Apache-2.0 material. ScreenCaptureKit is accessed as an authorized Apple system
framework through Xcode 27 or newer. The implementation does not copy Apple's
sample or ship the framework, SDK, a third-party package or a new asset. The
original Rust 0.4.5 crates remain the complete Cargo dependency graph. The
installation and distribution boundary is recorded in [the 0.5.1 guide](screencapturekit-051-fr.md).

## 0.5.0 session and screen masking

The SwiftUI session, Rust video authorization policy, C bridge, shared-Keychain
command, browser behavior and tests are original Apache-2.0 code. Core Graphics
and Image I/O generate the neutral privacy image at runtime using the authorized
Apple SDK. The source delta adds no image asset, external dependency, SDK binary
or copied upstream code. The resolved Cargo graph contains the two original crates.

## 0.4.4 iPad home and Messenger page integration

The original simplified SwiftUI home, native composer, page-status/URL handling,
JavaScript adapters, regression fixtures and delta packager are Apache-2.0.
No external Cargo/Swift/npm component, icon database or binary is added. The two
Rust crates and C ABI remain 0.4.2. The new test executes upstream Apache-2.0
Messenger functions from the checkout; none of that server code is redistributed.
System symbols, SwiftUI and WebKit/ReplayKit are authorized Apple SDK use, with
no SDK/framework copied into this source-only delta. Prior FileSaver runtime
review still applies to the unchanged server page. No user URL, token, node data
or conversation is included in tests or artifacts. See [the 0.4.4 record](ipad-chat-044.md).

The 0.4.4 recovery repeats eight byte-identical original Swift files and adds
original Apache-2.0 Python verification/packaging tools, tests and documentation.
Only the Python standard library is used; no runtime, external package, asset,
binary or Apple SDK is redistributed. Source/license checks still cover the same
two original Cargo crates with no external dependencies.

## 0.4.3 Chat repair

Original native banner, invitation handling/diagnosis, tests and source packager
are Apache-2.0. No new dependency, binary or asset is added. The Rust crates/C ABI
remain 0.4.2 with the same two-package, zero-external-dependency graph. Existing
SwiftUI/UIKit/WebKit are used under the previously authorized Apple SDK boundary.
The extended interoperability test reads upstream Apache-2.0 routing code in
place; no server source or complete server bundle is shipped. User-provided
operator URLs, authentication parameters and personal node data are not fixtures,
logs or delivery contents. See [the verification record](chat-043.md).

## 0.4.2 hardware inventory

Original Rust serializer/policy, C ABI, native collection, tests and incremental
packager are Apache-2.0. There are no new Cargo/npm/Swift dependencies, copied
model databases, third-party binaries or assets. The resolved Cargo graph remains
the two original workspace crates, with no external build/dev/transitive crates.
Foundation, UIKit, Darwin libc and CryptoKit are authorized Apple platform SDK
uses; none is redistributed in the source ZIP. The actual upstream sysinfo and
Details functions are read from the local Apache-2.0 checkout for tests, not copied
into the delivery. Existing upstream license conflicts remain outside this delta;
no server redistribution is made or approved. See the API/distribution boundary
and executed checks in [the inventory record](inventory-042.md).

## 0.4.1 MeshMessenger runtime boundary

Original invitation/Rust consent, WebKit host, tests and packager are Apache-2.0.
WebKit is used as an authorized Apple platform framework; no WebRTC binary,
codec wrapper, Swift/npm package or SDK is copied into this source delta.

The embedded page is the existing server MeshMessenger. Its original template,
common JavaScript, stylesheet and assets remain upstream Apache-2.0 files read in
place; no server bundle is redistributed or declared fully license-compliant.
Server-specific custom scripts/styles remain part of the operator's deployment.

The page also references the existing `public/scripts/filesaver.min.js`.
Its body was matched byte-for-byte (after removing the distributed header/source
map comment and surrounding whitespace) to FileSaver.js **v2.0.2** on 2026-11-21.
The tag's actual LICENSE.md and package.json were inspected: **MIT**, no runtime
package dependencies. MIT fallback is justified by reuse of the existing upstream
Messenger page; the file is not copied or modified. Its Babel development graph
is neither installed nor used to rebuild it. This does not approve redistribution
of Babel tooling or the inherited MeshCentral server dependency conflicts above.
The embedded view hides save/file controls and denies downloads; the server still
loads its ordinary script. `check-messenger.cjs` checks the audited body hash:
`fc6fd8aa395cb265022e2789d5e0926c0aa9dee87370d9f22487047e399f51d4`.

Original license notice retained from
[FileSaver.js v2.0.2](https://github.com/eligrey/FileSaver.js/blob/v2.0.2/LICENSE.md):

```text
The MIT License

Copyright © 2016 [Eli Grey][1].

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

  [1]: http://eligrey.com
```
