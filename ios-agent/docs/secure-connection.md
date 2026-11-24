<!-- SPDX-License-Identifier: Apache-2.0 -->
# Secure connection implementation

Date: 2026-11-19. MeshCentral baseline:
`67aff175f6d1093b1a81f8e9230607854d3fbaa6` (remote HEAD unchanged).

## Implemented components

- `src/auth.rs`: bounded handshake, correct nonce ordering, rejection on every
  authentication failure, and a server acknowledgment before session creation.
- `src/certificate.rs`: bounded DER assembly of an RSA device certificate. The
  platform supplies the RSA public key, random serial, dates, and signature.
  It emits UTCTime before 2050 and GeneralizedTime thereafter. It does not parse
  untrusted X.509 or implement any cryptographic primitive.
- `bridge/`: synchronous C ABI with bounded buffer checks and isolated unsafe
  pointer conversions. The header defines buffer ownership, callback lifetimes,
  serialization and error codes. Private keys never enter Rust.
- `apple/Sources/MeshCentralAgent/Identity.swift`: Security.framework RSA-3072
  key generation/storage, SHA-384 public-key pinning and RSA PKCS#1 v1.5 message
  signatures. A new certificate is signed from the same persistent key on load;
  MeshCentral's public-key-derived device ID remains stable.
- `apple/Sources/MeshCentralAgent/Connection.swift`: Foundation WSS transport,
  TLS peer authentication, Rust handshake integration, ordered identity/registration
  sends, bounded JSON control messages, core-info reporting and heartbeat.

## Trust and lifecycle rules

1. Enrollment supplies a trusted WSS endpoint, 48-byte server agent public-key
   fingerprint, 48-byte MeshID and an explicit architecture ID. There is no default
   iOS architecture assignment, TOFU, HTTP fallback, URL credential, query token or
   automatic redirect. Root and one-domain `agent.ashx` paths are accepted.
2. TLS requires chain and hostname validation. Optional private-CA DER is an
   explicitly provisioned trust anchor, restricted to that connection; it does not
   disable peer validation or install a system-wide CA. TLS 1.2 is the minimum.
3. SHA-384 of the actual TLS leaf certificate DER binds the MeshCentral challenge.
   This is separate from the server agent certificate's SHA-384 **PKCS#1 public-key**
   fingerprint. Both bindings must succeed before signing the device proof.
4. Server proof verification and device signing use Security.framework's
   `rsaSignatureMessagePKCS1v15SHA384`. CryptoKit hashes public data; CSPRNG bytes
   come from `SecRandomCopyBytes`. No private-key export API is called.
5. The private key is stored with `WhenUnlockedThisDeviceOnly` accessibility under
   an application-specific tag. Locked/unavailable Keychain errors fail closed;
   they do not replace the identity. This RSA key is not represented as a Secure
   Enclave key. Call identity creation off the UI thread and use a stable tag.
6. All network/ABI activity is serialized. The handshake has a 20-second deadline;
   messages are limited before WebSocket reassembly (8,580 bytes during auth,
   65,536 afterward). Heartbeats run every 60 seconds with a 15-second pong limit.
7. Every failure cancels the task, invalidates the session, releases the Rust handle
   and reports closure. Call `stop()` on user stop, app suspension or loss of the
   permitted foreground lifecycle. A connection object is single-use. Reconnection
   creates a fresh nonce and handshake and must not preserve assistance consent.

The adapter reports capabilities zero. It sends `coreinfo`, handles application
ping/pong and the empty JavaScript-core request, and ignores unsupported JSON
actions. No downloaded code, tunnel, shell, file access or remote input is executed.
The consent state machine remains a separately tested Rust facility; no media or
relay operation is exposed by this connection milestone.

## Build the application on Mac

The application project now lives at `apple/App/MeshCentralIOS.xcodeproj`, with
enrollment/connection screens and an automatic offline Rust build phase. Follow
[README-MAC.md](../README-MAC.md) for signing and iPhone testing. The project has
not been compiled on Mac; its SwiftUI sources and native transport remain
unverified on Apple platforms.

## Alternative library-only build on an Apple Silicon Mac

Prerequisites: Xcode with its SDKs/command-line tools, Rust 1.99 or later, and the
device, simulator and macOS ARM64 targets. SDK use is authorized, but account
agreement acceptance, publishing and purchase of membership are separate actions.

```sh
cd ios-agent
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin
sh apple/build-xcframework.sh
cd apple
swift test
```

The build script creates an original-source XCFramework; it does not download a
third-party binary. Existing framework output is preserved until moved aside.
The XCTest suite covers persistent identity, Apple signatures and pin failures,
malformed certificates, and endpoint rejection. Tests use a unique Keychain tag
and delete only that test key. These Apple checks have **not** run in this Windows
session. This alternative builds the reusable library, not a signed application.
The user later reported successful 0.1 simulator enrollment. The 0.2 capture,
relay and extension additions are documented separately in [screen-sharing.md](screen-sharing.md)
with simulator viewing subsequently reported working by the user.
Version 0.3 adds the [assistance layer](assistance-03.md); its Apple build and
device execution have not been performed in this Windows environment.

The application uses the same `Enrollment`, `KeychainIdentity` and
`MeshCentralConnection` types directly. Derive enrollment values from an authenticated
admin channel; do not hardcode a production MeshID, fingerprint, key or enrollment
secret into source. The integration fixture's architecture `0xfffffff0` is a test
value, not an upstream iOS assignment. Agree the real ID before deployment.

## Verification on Windows

Commands: `cargo fmt --all --check`, `cargo clippy --offline --locked --workspace
--all-targets -- -D warnings`, `cargo test --offline --locked --workspace`,
`node tools/check-licenses.cjs`, `node tools/check-upstream.cjs`, and
`./tools/check-native.ps1` (PowerShell 7.6.9 / .NET 10.0.14).

Observed results for this milestone: all 25 Rust tests passed; workspace Clippy
passed with warnings denied; formatting, source/license checks and the existing
in-memory upstream check passed. All 11 live TLS connection cases below passed.
Rust/Cargo version: 1.99.1; Node.js: 24.14.1. Apple XCTest remains unexecuted.

The live test starts a loopback-only HTTPS/WebSocket endpoint around the actual
checked-out `meshagent.js`. Node's native X.509 decoder replaces only the fixture's
forge parsing/fingerprinting adapter; real upstream nonce handling, RSA verification
and registration acknowledgment run unchanged. A minimal original test WebSocket
framer and an in-memory pre-enrolled device avoid installing the server's unrelated
dependency graph. TLS hostname/trust validation, RSA/SHA-384, generated certificate
parsing and the Rust C ABI run with real certificates and keys.

Eleven connection cases: valid authentication; stable-identity reconnect; wrong
server pin; altered server signature; wrong TLS hash binding; oversized message;
early acknowledgment; silent-server timeout; untrusted TLS CA; hostname mismatch;
and an altered agent signature rejected by the actual server. The native test
also validates the Rust-generated certificate's public key and self-signature.
Private keys are generated per run, passed through a private child-process stdin
pipe, and never written to files. The test server exits in a `finally` block.

This is not a test of Apple's TLS/Keychain behavior, new-device enrollment rules,
server UI/database installation, reverse proxies, relay/capture, mobile lifecycle,
or App Store acceptance. Those remain required validation gates.

## Official API references

- [URLSessionWebSocketTask](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask): native WebSocket transport, redirects and bounded receive buffering.
- [Generating cryptographic keys](https://developer.apple.com/documentation/security/generating-new-cryptographic-keys): persistent Keychain RSA keys.
- [SecKeyCopyExternalRepresentation](https://developer.apple.com/documentation/security/seckeycopyexternalrepresentation(_:_:)): RSA uses PKCS#1 serialization.
- [SecKeyCreateSignature](https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:)): native signing.
