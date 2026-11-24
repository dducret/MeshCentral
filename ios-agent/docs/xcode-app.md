<!-- SPDX-License-Identifier: Apache-2.0 -->
# Xcode application and invitation enrollment

The application is a SwiftUI shell over the Rust C ABI and Apple
Security/Foundation transport. `apple/App/MeshCentralIOS.xcodeproj` is a normal
shared Xcode project; it does not require a project generator on the recipient's
Mac. The optional existing Swift package/XCFramework path remains separate.
Do not add the Swift package to this app: the project already compiles its native
sources and links the Rust static library directly.

## Build and ownership

- iOS deployment target 16.0; Swift language mode 5, compiler 5.9 or newer.
- The first build phase runs `Scripts/build-rust.sh`. It maps Xcode's SDK and
  architectures to Rust device/Apple Silicon simulator/Intel simulator targets,
  builds offline with the lockfile, then copies or merges the static archive into
  `BUILT_PRODUCTS_DIR`. Cargo intermediates stay in Xcode's target temporary folder.
- Xcode user-script sandboxing is disabled for this target because Cargo needs
  the rustup toolchain and its build directory. The script does not fetch packages.
- Headers and the C module map come from `bridge/include`; no compiled artifact
  is shipped. Signing Team and Bundle Identifier belong to the recipient.
- Version 0.2 embeds `MeshCentralBroadcast.appex`. Both targets inherit the
  `MESH_HOST_BUNDLE_ID` project setting and share that app's Keychain group. The
  extension builds its own archive name to avoid concurrent output collisions.
  Native source files are compiled in each target with no remote Swift packages.
- Version 0.3 additionally declares the same `group.$(MESH_HOST_BUNDLE_ID)`
  App Group in both targets and Info.plist files. Register/select this group
  for device signing. It carries bounded protected assistance content, not
  credential storage. See [assistance](assistance-03.md) and the Mac guide.
- `tools/generate_xcode.py` deterministically regenerates the checked-in project
  for maintainers. `tools/package_mac.py` creates and verifies the source ZIP.

## Enrollment trust boundary

`webserver.js` at the documented upstream revision constructs the mobile link
from the agent hostname/port, optional domain, server agent-key fingerprint and
group identifier. `views/agentinvite.handlebars` emits it as `var magenturl`.
The `c` parameter is a server-encrypted invitation, not something the client can
or should decode. The app obtains the mobile link by fetching the user's supplied
HTTPS invitation and validates the resulting enrollment locally.

The HTTPS request is ephemeral, bounded to 512 KiB and 25 seconds, accepts only a
successful HTML response, executes no scripts and rejects redirects. The TLS
chain and hostname must validate under system trust or an explicitly imported
private CA. This establishes the initial trust in the agent-key fingerprint;
the later WSS handshake separately verifies that pin and the observed TLS leaf
binding. A trusted web origin can intentionally advertise a separate agent host:
the UI displays that endpoint and requires explicit saving before connecting.
Only direct `/agentinvite` or `/domain/agentinvite` paths are supported initially.

Invitation tokens are never put in logs, fixture files, saved profiles or this
ZIP. Synthetic parser fixtures use `example.invalid`. Input and certificate files
are bounded to 16 KiB. Duplicate identifiers and ambiguous page fields fail
closed. Profile data uses a Keychain generic-password entry; RSA private keys use
Security key objects and are not exported. Private CA input permits a single
public DER/PEM certificate, never a private key.

The UI explicitly separates reading, inspecting/saving and connecting. Main-actor
state owns the connection; native key generation runs off the UI thread and
generation tokens invalidate late callbacks after disconnect/backgrounding.
Backgrounding stops the app-owned WSS/capture and clears pasted input. A user-started
ReplayKit extension separately owns its control connection and continues under
the system broadcast lifecycle. No silent reconnect is performed.
The per-server identity tag binds the bundle identifier, endpoint and server pin;
changing signing/bundle configuration or the server pin can create a new identity.

## Validation boundary

The provided test invitation was read successfully with the Windows system TLS
validator: HTTP 200 and one mobile link with two 48-byte identifiers. This was
read-only discovery, not enrollment of a physical device. The token and returned
identifiers were not written to disk. The server decides expiration/revocation;
the client never assumes a supplied link is permanently valid.

Rust tests and server interoperability tests cover the portable core. Xcode
project references, plist/scheme XML, archive contents and license inventory are
checked on Windows. The archive is also checked after extraction outside the
upstream checkout's source tree, without relying on parent server files. A shell
syntax-check attempt using Git Bash was blocked by the Windows sandbox before
the shell started; the Mac preparation/build scripts remain unexecuted here.
The SwiftUI UI, XCTest suite, Security Keychain behavior and
URLSession transport have **not been compiled or executed** on Apple platforms.
Mac/iPhone verification is a required next step, not an accomplished capability.

The experimental architecture ID remains. Version 0.2 announces Desktop only
when a capture host is attached and implements view-only relays with local consent.
ReplayKit and a shared Keychain mailbox are integrated in source; they require
Apple execution testing. Remote input and remote command execution are absent.
